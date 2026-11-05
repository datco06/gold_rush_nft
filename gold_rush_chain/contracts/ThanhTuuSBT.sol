// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Huy hiệu thành tích Gold Rush — không chuyển nhượng, không đốt.
/// @dev Backend xác minh điều kiện trong game trước khi ký phiếu. Hợp đồng
/// chỉ xác minh phiếu và quản lý quyền sở hữu; không xử lý vàng hay hồ sơ UI.
contract ThanhTuuSBT is ERC721, EIP712, Ownable {
    /// @dev Phải khớp tên, kiểu và thứ tự trường khi Backend ký EIP-712.
    struct PhieuSBT {
        address player;
        uint256 achievementId;
        bytes32 nonce;
        uint256 deadline;
    }

    bytes32 public constant PHIEU_SBT_TYPEHASH = keccak256(
        "PhieuSBT(address player,uint256 achievementId,bytes32 nonce,uint256 deadline)"
    );

    /// @dev Các ID hợp lệ trong phiên bản đầu tiên:
    /// 1: Thợ Mỏ Tập Sự; 2: Nhà Thám Hiểm Rừng Xanh; 3: Kẻ Săn Boss;
    /// 4: Chiến Binh Bất Bại; 5: Huyền Thoại Gold Rush.
    uint256 public constant MAX_ACHIEVEMENT_ID = 5;

    address public signer;

    /// @notice Nonce dùng một lần trên toàn hợp đồng, kể cả sau khi đổi signer.
    /// @dev Backend phải cấp nonce duy nhất cho mỗi phiếu, không tái dùng giữa các ví.
    mapping(bytes32 => bool) public usedNonces;

    mapping(address => mapping(uint256 => bool)) private _achievements;
    mapping(uint256 => uint256) private _tokenAchievements;
    uint256 private _nextTokenId = 1;

    event SBTClaimed(
        address indexed player,
        uint256 indexed tokenId,
        uint256 indexed achievementId,
        bytes32 nonce
    );
    event SignerUpdated(address indexed previousSigner, address indexed newSigner);

    error InvalidSigner();
    error WrongPlayer();
    error VoucherExpired();
    error NonceAlreadyUsed(bytes32 nonce);
    error AchievementAlreadyClaimed(address player, uint256 achievementId);
    error InvalidAchievementId(uint256 achievementId);
    error InvalidSignature();
    error Soulbound();

    /// @param initialOwner Chủ hợp đồng, có quyền thay signer.
    /// @param initialSigner Địa chỉ EOA của Backend dùng để ký phiếu.
    /// @dev Ownable kiểm tra initialOwner khác địa chỉ 0.
    constructor(address initialOwner, address initialSigner)
        ERC721("GoldRush Achievement", "GRSBT")
        EIP712("GoldRushSBT", "1")
        Ownable(initialOwner)
    {
        if (initialSigner == address(0)) revert InvalidSigner();
        signer = initialSigner;
        emit SignerUpdated(address(0), initialSigner);
    }

    /// @notice Digest EIP-712 để đối chiếu với Backend và unit test.
    /// @dev Domain tự gắn chainId hiện tại và địa chỉ hợp đồng này.
    function hashVoucher(PhieuSBT calldata p) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(PHIEU_SBT_TYPEHASH, p.player, p.achievementId, p.nonce, p.deadline))
        );
    }

    /// @notice Nhận một huy hiệu bằng phiếu Backend ký; không thu vàng hay ETH.
    /// @dev deadline là giây Unix; phiếu vẫn hợp lệ tại đúng deadline.
    /// Chữ ký ECDSA chuẩn 65 byte. Ghi trạng thái trước callback của _safeMint.
    function claimSBT(PhieuSBT calldata p, bytes calldata signature) external returns (uint256 tokenId) {
        if (p.player != msg.sender) revert WrongPlayer();
        if (block.timestamp > p.deadline) revert VoucherExpired();
        if (p.achievementId == 0 || p.achievementId > MAX_ACHIEVEMENT_ID) {
            revert InvalidAchievementId(p.achievementId);
        }
        if (usedNonces[p.nonce]) revert NonceAlreadyUsed(p.nonce);
        if (_achievements[p.player][p.achievementId]) {
            revert AchievementAlreadyClaimed(p.player, p.achievementId);
        }

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hashVoucher(p), signature);
        if (err != ECDSA.RecoverError.NoError || recovered != signer) revert InvalidSignature();

        usedNonces[p.nonce] = true;
        _achievements[p.player][p.achievementId] = true;
        tokenId = _nextTokenId++;
        _tokenAchievements[tokenId] = p.achievementId;

        _safeMint(p.player, tokenId);
        emit SBTClaimed(p.player, tokenId, p.achievementId, p.nonce);
    }

    /// @notice Kiểm tra ví đã nhận thành tích; ID không hợp lệ trả về false.
    function hasAchievement(address player, uint256 achievementId) external view returns (bool) {
        return _achievements[player][achievementId];
    }

    /// @notice Trả về achievementId; token chưa tồn tại gây ERC721NonexistentToken.
    function achievementOfToken(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenAchievements[tokenId];
    }

    /// @notice Đổi signer; phiếu từ khóa cũ bị từ chối khi khóa đó không còn được ủy quyền.
    function setSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidSigner();
        address previousSigner = signer;
        signer = newSigner;
        emit SignerUpdated(previousSigner, newSigner);
    }

    /// @dev Chặn cấp và thu hồi phê duyệt chuyển nhượng.
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    /// @dev OpenZeppelin 5.x đưa mint, transfer và burn qua _update.
    /// Chỉ cho mint token mới đến địa chỉ khác 0. Cả hai safeTransferFrom
    /// gọi transferFrom rồi đi qua đây; không có đường chuyển hay đốt token.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0) || to == address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}
