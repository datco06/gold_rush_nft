// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

/// @title Cửa hàng nhân vật Gold Rush — bản 2 (nhiều màn chơi, cọc vào màn). Chỉ dùng trên mạng thử nghiệm.
///
/// ERC-1155 giữ hai loại thứ:
///   * id 0 = VÀNG: đúc khi người chơi nộp PHIẾU VÀNG do máy chủ trọng tài ký (EIP-712).
///   * id 1, 2, 3… = NHÂN VẬT: mua bằng cách ĐỐT vàng, mỗi ví tối đa 1 bản mỗi loại.
///
/// MÀN CHƠI (mới ở bản 2). Mỗi màn có `coc` và `thuongToiDa`:
///   * coc = 0 → màn luyện tập: phiếu trả số xu nhặt được, thua không mất gì.
///   * coc > 0 → vào màn bằng `vaoMan(man)`: hợp đồng ĐỐT `coc` vàng ngay lập tức và ghi một VÉ.
///       - Hoàn thành: phiếu của máy chủ (ghi đúng số vé) đúc lại cọc + xu + thưởng.
///       - Không hoàn thành (chết, hết giờ, bỏ ngang, đóng trình duyệt): không có phiếu, cọc đã đốt
///         là mất. "Trừ vàng khi thua" vì vậy TỰ ĐỘNG và KHÔNG CẦN giao dịch nào lúc thua — không ai
///         phải tin người chơi sẽ tự nộp một giao dịch phạt chính mình.
///
/// Gộp giao dịch: kế thừa `Multicall` → app gói "nhận các phiếu đang chờ + vào màn mới" (hoặc
/// "+ mua nhân vật") vào MỘT giao dịch, MetaMask chỉ hỏi một lần. `multicall` dùng delegatecall
/// vào chính hợp đồng nên `msg.sender` vẫn là người chơi.
///
/// TẤT CẢ đều KHÔNG CHUYỂN NHƯỢNG (soulbound) — Nghị định 147/2024/NĐ-CP, Điều 57: cấm người chơi
/// mua bán vật phẩm ảo, đơn vị ảo với nhau và cấm quy đổi ngược ra tiền.
contract CuaHangGoldRush is ERC1155, EIP712, Ownable, Multicall {
    uint256 public constant VANG = 0;

    /// Phiếu vàng — PHẢI khớp từng ký tự với `PHIEU` trong gold_rush_ai/core/trong_tai.py.
    struct PhieuVang {
        address nguoiChoi; // ví được nhận — phiếu không dùng được cho ví khác
        uint256 man; // id màn chơi (khớp assets/tiles/man_choi.json)
        uint256 ve; // số vé của màn có cọc; 0 với màn luyện tập
        uint256 soVang; // xu nhặt được + thưởng hoàn thành (CHƯA gồm cọc hoàn lại)
        bytes32 maVan; // keccak256 của mã ván — mỗi ván chỉ đổi một lần
        uint256 hanChot; // giây Unix; quá hạn thì phiếu vô hiệu
    }

    bytes32 public constant PHIEU_TYPEHASH = keccak256(
        "PhieuVang(address nguoiChoi,uint256 man,uint256 ve,uint256 soVang,bytes32 maVan,uint256 hanChot)"
    );

    struct ManChoi {
        uint256 coc; // vàng đốt khi vào màn; 0 = luyện tập
        uint256 thuongToiDa; // trần `soVang` của một phiếu màn này (số xu + thưởng); 0 = màn chưa mở
    }

    struct Ve {
        uint256 man;
        uint256 so; // 0 = không có vé đang mở
        uint256 coc; // cọc đã đốt — hoàn lại đúng số này, kể cả khi chủ hợp đồng đổi giá cọc sau đó
    }

    address public trongTai;
    mapping(bytes32 => bool) public daDoi;
    mapping(uint256 => uint256) public gia;
    mapping(uint256 => ManChoi) public manChoi;

    /// Vé đang mở của mỗi ví — tối đa MỘT. Vào màn mới khi vé cũ chưa dùng thì vé cũ bị bỏ (mất cọc).
    mapping(address => Ve) public ve;
    mapping(address => uint256) public soVeDaMua;

    event DaNhanVang(address indexed nguoiChoi, bytes32 indexed maVan, uint256 man, uint256 soVang, uint256 hoanCoc);
    event DaVaoMan(address indexed nguoiChoi, uint256 indexed man, uint256 so, uint256 coc);
    event MatCoc(address indexed nguoiChoi, uint256 indexed man, uint256 so, uint256 coc);
    event DaMua(address indexed nguoiChoi, uint256 indexed nhanVat, uint256 gia);
    event DoiGia(uint256 indexed nhanVat, uint256 gia);
    event DoiMan(uint256 indexed man, uint256 coc, uint256 thuongToiDa);
    event DoiTrongTai(address trongTaiMoi);

    error KhongChuyenNhuong();
    error SaiNguoiNhan();
    error PhieuHetHan();
    error PhieuDaDung();
    error SoVangKhongHopLe();
    error ChuKySai();
    error KhongBan(uint256 nhanVat);
    error DaCo(uint256 nhanVat);
    error DiaChiRong();
    error ManKhongTonTai(uint256 man);
    error ManMienPhi(uint256 man);
    error SaiVe();

    constructor(address trongTai_, string memory uri_)
        ERC1155(uri_)
        EIP712("GoldRush", "2")
        Ownable(msg.sender)
    {
        if (trongTai_ == address(0)) revert DiaChiRong();
        trongTai = trongTai_;
    }

    // ------------------------------------------------------------------
    // Màn chơi
    // ------------------------------------------------------------------

    /// Vào một màn có cọc: đốt cọc, cấp vé mới. Thiếu vàng → ERC1155InsufficientBalance.
    function vaoMan(uint256 man) external {
        ManChoi memory m = manChoi[man];
        if (m.thuongToiDa == 0) revert ManKhongTonTai(man);
        if (m.coc == 0) revert ManMienPhi(man);

        Ve memory cu = ve[msg.sender];
        if (cu.so != 0) emit MatCoc(msg.sender, cu.man, cu.so, cu.coc);

        uint256 so = ++soVeDaMua[msg.sender];
        ve[msg.sender] = Ve(man, so, m.coc);
        _burn(msg.sender, VANG, m.coc);
        emit DaVaoMan(msg.sender, man, so, m.coc);
    }

    function datMan(uint256 man, uint256 coc, uint256 thuongToiDa) external onlyOwner {
        manChoi[man] = ManChoi(coc, thuongToiDa);
        emit DoiMan(man, coc, thuongToiDa);
    }

    // ------------------------------------------------------------------
    // Vàng
    // ------------------------------------------------------------------

    function bamPhieu(PhieuVang calldata p) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(PHIEU_TYPEHASH, p.nguoiChoi, p.man, p.ve, p.soVang, p.maVan, p.hanChot))
        );
    }

    /// Nộp phiếu. Màn có cọc: phiếu phải ghi đúng vé đang mở → hoàn cọc + xu + thưởng, đóng vé.
    function nhanVang(PhieuVang calldata p, bytes calldata chuKy) external {
        if (p.nguoiChoi != msg.sender) revert SaiNguoiNhan();
        if (block.timestamp > p.hanChot) revert PhieuHetHan();
        ManChoi memory m = manChoi[p.man];
        if (m.thuongToiDa == 0) revert ManKhongTonTai(p.man);
        if (p.soVang == 0 || p.soVang > m.thuongToiDa) revert SoVangKhongHopLe();
        if (daDoi[p.maVan]) revert PhieuDaDung();

        uint256 hoanCoc;
        if (m.coc == 0) {
            if (p.ve != 0) revert SaiVe();
        } else {
            Ve memory v = ve[msg.sender];
            if (p.ve == 0 || v.so != p.ve || v.man != p.man) revert SaiVe();
            hoanCoc = v.coc;
        }
        if (ECDSA.recoverCalldata(bamPhieu(p), chuKy) != trongTai) revert ChuKySai();

        // checks-effects-interactions: ghi trạng thái TRƯỚC khi đúc
        daDoi[p.maVan] = true;
        if (hoanCoc != 0) delete ve[msg.sender];
        _mint(msg.sender, VANG, p.soVang + hoanCoc, "");
        emit DaNhanVang(msg.sender, p.maVan, p.man, p.soVang, hoanCoc);
    }

    // ------------------------------------------------------------------
    // Nhân vật
    // ------------------------------------------------------------------

    function mua(uint256 nhanVat) external {
        uint256 g = gia[nhanVat];
        if (nhanVat == VANG || g == 0) revert KhongBan(nhanVat);
        if (balanceOf(msg.sender, nhanVat) > 0) revert DaCo(nhanVat);

        _burn(msg.sender, VANG, g);
        _mint(msg.sender, nhanVat, 1, "");
        emit DaMua(msg.sender, nhanVat, g);
    }

    function datGia(uint256 nhanVat, uint256 giaMoi) external onlyOwner {
        if (nhanVat == VANG) revert KhongBan(nhanVat);
        gia[nhanVat] = giaMoi;
        emit DoiGia(nhanVat, giaMoi);
    }

    /// Đổi khoá trọng tài khi khoá cũ lộ. Phiếu cũ (ký bằng khoá cũ) lập tức vô hiệu.
    function doiTrongTai(address moi) external onlyOwner {
        if (moi == address(0)) revert DiaChiRong();
        trongTai = moi;
        emit DoiTrongTai(moi);
    }

    // ------------------------------------------------------------------
    // Không chuyển nhượng
    // ------------------------------------------------------------------

    /// Mọi chuyển động số dư ERC-1155 đi qua `_update`: chỉ cho đúc (from = 0) và đốt (to = 0).
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override
    {
        if (from != address(0) && to != address(0)) revert KhongChuyenNhuong();
        super._update(from, to, ids, values);
    }

    function setApprovalForAll(address, bool) public pure override {
        revert KhongChuyenNhuong();
    }
}
