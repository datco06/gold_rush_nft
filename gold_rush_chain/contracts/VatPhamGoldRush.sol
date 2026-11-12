// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Gold Rush Equipment — trang bị ERC-1155 nhận bằng phiếu Backend.
/// @dev Độc lập với CuaHangGoldRush và ThanhTuuSBT. Cho chuyển nhượng theo chuẩn
/// ERC-1155; không có mua bán, thu vàng, burn hay logic sức mạnh/trang bị.
contract VatPhamGoldRush is ERC1155, EIP712, Ownable {
    string public constant name = "Gold Rush Equipment";

    // ID danh mục ban đầu; owner phải đăng ký URI và maxSupply trước khi cấp phiếu.
    // Đây là ID trong hợp đồng này, không phải ID vàng/nhân vật hoặc SBT.
    uint256 public constant KIEM_VANG = 1;
    uint256 public constant KHIEN_VE_BINH = 2;
    uint256 public constant TRUONG_BANG = 3;
    uint256 public constant GIAP_HOANG_KIM = 4;

    /// @dev Backend phải dùng đúng tên, kiểu và thứ tự trường khi ký EIP-712.
    struct PhieuVatPham {
        address player;
        uint256 tokenId;
        uint256 amount;
        bytes32 nonce;
        uint256 deadline;
    }

    bytes32 public constant PHIEU_VAT_PHAM_TYPEHASH = keccak256(
        "PhieuVatPham(address player,uint256 tokenId,uint256 amount,bytes32 nonce,uint256 deadline)"
    );

    /// @notice Địa chỉ EOA của Backend được ủy quyền ký phiếu.
    address public signer;

    mapping(uint256 => bool) public registered;
    mapping(uint256 => uint256) public maxSupply;

    /// @notice Tổng số bản đã mint của từng loại, không đổi khi chuyển ví.
    /// @dev Không có hàm burn công khai, nên cũng là tổng cung đang lưu hành.
    mapping(uint256 => uint256) public totalMinted;

    /// @notice Nonce chỉ dùng một lần trên toàn hợp đồng, không chia theo ví/ID.
    /// @dev Backend phải cấp nonce duy nhất cho mỗi phiếu, kể cả sau khi đổi signer.
    mapping(bytes32 => bool) public usedNonces;

    mapping(uint256 => string) private _itemURIs;

    event ItemRegistered(uint256 indexed tokenId, string metadataURI, uint256 maxSupply);
    event MaxSupplyUpdated(uint256 indexed tokenId, uint256 previousMaxSupply, uint256 newMaxSupply);
    event ItemClaimed(address indexed player, uint256 indexed tokenId, uint256 amount, bytes32 indexed nonce);
    event SignerUpdated(address indexed previousSigner, address indexed newSigner);

    error InvalidSigner();
    error InvalidTokenId(uint256 tokenId);
    error ItemAlreadyRegistered(uint256 tokenId);
    error ItemNotRegistered(uint256 tokenId);
    error EmptyURI();
    error InvalidMaxSupply(uint256 maxSupply);
    error SupplyLocked(uint256 tokenId);
    error WrongPlayer();
    error VoucherExpired();
    error NonceAlreadyUsed(bytes32 nonce);
    error InvalidAmount();
    error MaxSupplyExceeded(uint256 tokenId, uint256 requested, uint256 remaining);
    error InvalidSignature();

    /// @param initialOwner Chủ hợp đồng có quyền đăng ký/cấu hình vật phẩm và đổi signer.
    /// @param initialSigner Địa chỉ Backend ký phiếu, phải khác địa chỉ zero.
    /// @dev Ownable kiểm tra initialOwner khác zero. Không tự đăng ký vật phẩm vì
    /// URI và nguồn cung phải do owner cung cấp; ERC-1155 dùng URI riêng từng ID.
    constructor(address initialOwner, address initialSigner)
        ERC1155("")
        EIP712("GoldRushEquipment", "1")
        Ownable(initialOwner)
    {
        if (initialSigner == address(0)) revert InvalidSigner();
        signer = initialSigner;
        emit SignerUpdated(address(0), initialSigner);
    }

    /// @notice Đăng ký loại vật phẩm mới. ID > 0, URI không rỗng, maxSupply > 0.
    /// @dev maxSupply = 1 là độc bản toàn hợp đồng, không phải giới hạn theo ví.
    function registerItem(uint256 tokenId, string calldata metadataURI, uint256 supplyLimit) external onlyOwner {
        if (tokenId == 0) revert InvalidTokenId(tokenId);
        if (registered[tokenId]) revert ItemAlreadyRegistered(tokenId);
        if (bytes(metadataURI).length == 0) revert EmptyURI();
        if (supplyLimit == 0) revert InvalidMaxSupply(supplyLimit);

        registered[tokenId] = true;
        maxSupply[tokenId] = supplyLimit;
        _itemURIs[tokenId] = metadataURI;

        emit ItemRegistered(tokenId, metadataURI, supplyLimit);
        emit URI(metadataURI, tokenId);
    }

    /// @notice Đổi metadata của một loại đã đăng ký, kể cả sau khi mint.
    /// @dev URI là tham chiếu metadata, không chứa logic chiến đấu trên chuỗi.
    function setItemURI(uint256 tokenId, string calldata metadataURI) external onlyOwner {
        _requireRegistered(tokenId);
        if (bytes(metadataURI).length == 0) revert EmptyURI();
        _itemURIs[tokenId] = metadataURI;
        emit URI(metadataURI, tokenId);
    }

    /// @notice Đổi giới hạn CHỈ trước lần mint đầu tiên của loại này.
    /// @dev Khóa cap sau khi mint để không biến vật phẩm độc bản thành nhiều bản.
    function setMaxSupply(uint256 tokenId, uint256 supplyLimit) external onlyOwner {
        _requireRegistered(tokenId);
        if (supplyLimit == 0) revert InvalidMaxSupply(supplyLimit);
        if (totalMinted[tokenId] != 0) revert SupplyLocked(tokenId);
        uint256 previous = maxSupply[tokenId];
        maxSupply[tokenId] = supplyLimit;
        emit MaxSupplyUpdated(tokenId, previous, supplyLimit);
    }

    /// @notice URI của loại vật phẩm; ID chưa đăng ký gây ItemNotRegistered.
    function uri(uint256 tokenId) public view override returns (string memory) {
        _requireRegistered(tokenId);
        return _itemURIs[tokenId];
    }

    /// @notice Digest EIP-712 để Backend, Flutter và test đối chiếu.
    /// @dev Domain bao gồm chainId hiện tại và địa chỉ hợp đồng này.
    function hashVoucher(PhieuVatPham calldata p) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(PHIEU_VAT_PHAM_TYPEHASH, p.player, p.tokenId, p.amount, p.nonce, p.deadline))
        );
    }

    /// @notice Người chơi nhận vật phẩm bằng phiếu Backend đã ký, không trả vàng/ETH.
    /// @dev deadline là giây Unix; còn hợp lệ tại đúng deadline. Chữ ký ECDSA
    /// 65 byte như ThanhTuuSBT. Không giới hạn một vật phẩm mỗi ví: amount và
    /// quyền được nhận do Backend quyết định, giới hạn toàn loại do maxSupply.
    function claimItem(PhieuVatPham calldata p, bytes calldata signature) external {
        if (p.player != msg.sender) revert WrongPlayer();
        if (block.timestamp > p.deadline) revert VoucherExpired();
        if (usedNonces[p.nonce]) revert NonceAlreadyUsed(p.nonce);
        _requireRegistered(p.tokenId);
        if (p.amount == 0) revert InvalidAmount();

        uint256 minted = totalMinted[p.tokenId];
        uint256 remaining = maxSupply[p.tokenId] - minted;
        // So với phần còn lại trước khi cộng để cả amount cực lớn cũng không gây tràn.
        if (p.amount > remaining) revert MaxSupplyExceeded(p.tokenId, p.amount, remaining);

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hashVoucher(p), signature);
        if (err != ECDSA.RecoverError.NoError || recovered != signer) revert InvalidSignature();

        // Checks-effects-interactions: tiêu thụ nonce và nguồn cung TRƯỚC callback
        // onERC1155Received, ngăn nhận lại cùng phiếu hoặc vượt cap khi gọi lại.
        // Nếu receiver từ chối token, toàn bộ trạng thái này cũng được hoàn tác.
        usedNonces[p.nonce] = true;
        totalMinted[p.tokenId] = minted + p.amount;
        _mint(p.player, p.tokenId, p.amount, "");
        emit ItemClaimed(p.player, p.tokenId, p.amount, p.nonce);
    }

    /// @notice Chỉ owner được đổi signer. Phiếu khóa cũ bị từ chối khi khóa đó
    /// không còn là signer; việc đổi signer không xóa nonce đã dùng.
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidSigner();
        address previous = signer;
        signer = newSigner;
        emit SignerUpdated(previous, newSigner);
    }

    function _requireRegistered(uint256 tokenId) private view {
        if (!registered[tokenId]) revert ItemNotRegistered(tokenId);
    }

    // Kế thừa nguyên ERC-1155: balanceOf, balanceOfBatch, setApprovalForAll,
    // isApprovedForAll, safeTransferFrom và safeBatchTransferFrom. OpenZeppelin
    // kiểm tra quyền sở hữu/operator, số dư và khả năng nhận của ví hợp đồng.
}
