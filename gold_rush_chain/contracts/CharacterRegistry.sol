// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CharacterRegistry — Hợp đồng đăng ký quyền sở hữu nhân vật AI Gold Rush trên Ethereum/EVM
/// @notice Quản lý nhân vật AI được xác thực thông qua chữ ký số EIP-712 của Backend AI Authorization Signer.
/// @dev Đảm bảo chống replay, chống trùng characterId, chống trùng characterHash (chính sách 1 hash - 1 nhân vật),
/// và phát ra event CharacterRegistered khớp 100% với đặc tả của Backend AI RPC Verifier.
contract CharacterRegistry is EIP712, Ownable {
    /// @notice Bản ghi thông tin nhân vật chính thức đã đăng ký on-chain
    struct CharacterRecord {
        bytes32 characterHash;  // SHA-256 dạng bytes32 của ảnh PNG 128x128
        address owner;          // Địa chỉ ví Ethereum của chủ sở hữu
        uint256 registeredAt;   // Thời điểm Unix timestamp ghi nhận vào block
        string characterId;     // Định dạng chuẩn: char_ + 32 ký tự hex
    }

    /// @notice Phiếu cấp phép đăng ký nhân vật do Backend AI ký qua EIP-712
    struct CharacterVoucher {
        string characterId;     // Định dạng char_ + 32 ký tự hex chữ thường
        bytes32 characterHash;  // 0x + 64 ký tự hex SHA-256 từ Backend
        address owner;          // Ví người chơi đã xác thực SIWE
        bytes32 nonce;          // Nonce duy nhất dùng 1 lần chống replay
        uint256 deadline;       // Thời hạn Unix timestamp
    }

    /// @dev TypeHash theo chuẩn EIP-712.
    /// Lưu ý: string characterId được mã hóa qua keccak256(bytes(characterId)) theo chuẩn EIP-712.
    bytes32 public constant CHARACTER_VOUCHER_TYPEHASH = keccak256(
        "CharacterVoucher(string characterId,bytes32 characterHash,address owner,bytes32 nonce,uint256 deadline)"
    );

    /// @notice Địa chỉ Backend AI có quyền ký cấp phép đăng ký nhân vật
    address public authorizedSigner;

    /// @notice Tổng số lượng nhân vật đã đăng ký thành công trên hợp đồng
    uint256 public totalCharacters;

    /// @dev Lưu trữ metadata nhân vật theo characterId
    mapping(string => CharacterRecord) private _characters;

    /// @dev Ánh xạ từ characterHash sang characterId nhằm bảo đảm 1 hash chỉ thuộc về 1 nhân vật
    mapping(bytes32 => string) private _hashToCharacterId;

    /// @notice Theo dõi các nonce đã sử dụng để chống replay attack
    mapping(bytes32 => bool) public usedNonces;

    // ------------------------------------------------------------------
    // Events (Bắt buộc khớp 100% với Backend AI RPC Verifier)
    // ------------------------------------------------------------------

    /// @notice Sự kiện phát ra khi nhân vật được đăng ký thành công on-chain
    /// @dev Backend AI RPC Verifier đối chiếu các topics:
    ///   Topic 0: keccak256("CharacterRegistered(string,bytes32,address)")
    ///   Topic 1: keccak256(bytes(characterId))
    ///   Topic 2: bytes32 characterHash
    ///   Topic 3: address owner (đệm 12 bytes 0)
    event CharacterRegistered(
        string indexed characterId,
        bytes32 indexed characterHash,
        address indexed owner
    );

    /// @notice Sự kiện cập nhật địa chỉ Backend Authorization Signer
    event SignerUpdated(address indexed previousSigner, address indexed newSigner);

    // ------------------------------------------------------------------
    // Custom Errors
    // ------------------------------------------------------------------

    error InvalidSigner();
    error UnauthorizedCaller();
    error VoucherExpired();
    error NonceAlreadyUsed(bytes32 nonce);
    error CharacterAlreadyRegistered(string characterId);
    error CharacterHashAlreadyRegistered(bytes32 characterHash, string existingCharacterId);
    error InvalidCharacterId();
    error InvalidCharacterHash();
    error InvalidOwner();
    error InvalidSignature();

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @param initialOwner Địa chỉ chủ sở hữu quản trị hợp đồng
    /// @param initialSigner Địa chỉ ví ký cấp phép Backend AI
    constructor(address initialOwner, address initialSigner)
        EIP712("CharacterRegistry", "1")
        Ownable(initialOwner)
    {
        if (initialSigner == address(0)) revert InvalidSigner();
        authorizedSigner = initialSigner;
        emit SignerUpdated(address(0), initialSigner);
    }

    // ------------------------------------------------------------------
    // View Functions & EIP-712 Helpers
    // ------------------------------------------------------------------

    /// @notice Tính mã băm EIP-712 digest của phiếu cấp phép đăng ký nhân vật
    /// @param v Thông tin voucher đăng ký
    /// @return bytes32 Mã băm typed data v4 theo EIP-712
    function hashVoucher(CharacterVoucher calldata v) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CHARACTER_VOUCHER_TYPEHASH,
                    keccak256(bytes(v.characterId)),
                    v.characterHash,
                    v.owner,
                    v.nonce,
                    v.deadline
                )
            )
        );
    }

    /// @notice Kiểm tra định dạng hợp lệ của characterId: char_ + 32 ký tự hex thường (độ dài đúng 37 ký tự)
    function isValidCharacterId(string calldata id) public pure returns (bool) {
        bytes calldata b = bytes(id);
        if (b.length != 37) return false;
        if (b[0] != "c" || b[1] != "h" || b[2] != "a" || b[3] != "r" || b[4] != "_") return false;
        for (uint256 i = 5; i < 37; i++) {
            bytes1 c = b[i];
            bool isHex = (c >= "0" && c <= "9") || (c >= "a" && c <= "f");
            if (!isHex) return false;
        }
        return true;
    }

    /// @notice Kiểm tra characterId đã được đăng ký hay chưa
    function isCharacterRegistered(string calldata characterId) external view returns (bool) {
        return _characters[characterId].owner != address(0);
    }

    /// @notice Kiểm tra characterHash đã được đăng ký bởi bất kỳ nhân vật nào hay chưa
    function isCharacterHashRegistered(bytes32 characterHash) external view returns (bool) {
        return bytes(_hashToCharacterId[characterHash]).length > 0;
    }

    /// @notice Lấy thông tin chi tiết của nhân vật theo characterId
    function getCharacter(string calldata characterId) external view returns (CharacterRecord memory) {
        return _characters[characterId];
    }

    /// @notice Tra cứu characterId tương ứng với một characterHash đã đăng ký
    function getCharacterIdByHash(bytes32 characterHash) external view returns (string memory) {
        return _hashToCharacterId[characterHash];
    }

    /// @notice Kiểm tra đối soát nhanh tính hợp lệ của nhân vật (dành cho client & Backend)
    function verifyCharacter(
        string calldata characterId,
        bytes32 characterHash,
        address owner
    ) external view returns (bool) {
        CharacterRecord memory rec = _characters[characterId];
        return (rec.owner != address(0) && rec.owner == owner && rec.characterHash == characterHash);
    }

    // ------------------------------------------------------------------
    // Core Registration Logic
    // ------------------------------------------------------------------

    /// @notice Đăng ký nhân vật AI on-chain với chữ ký ủy quyền EIP-712 từ Backend AI
    /// @dev Quy trình xác minh:
    ///   1. Người gửi giao dịch (msg.sender) PHẢI là voucher.owner (ngăn front-running & cướp voucher).
    ///   2. Phiếu chưa hết hạn (block.timestamp <= voucher.deadline).
    ///   3. Địa chỉ ví owner khác address(0).
    ///   4. Định dạng characterId đúng chuẩn char_<32_hex_chars>.
    ///   5. characterHash khác bytes32(0).
    ///   6. Nonce chưa từng được sử dụng.
    ///   7. characterId chưa từng được đăng ký.
    ///   8. characterHash chưa từng được sử dụng cho bất kỳ nhân vật nào khác.
    ///   9. Chữ ký ECDSA hợp lệ và được ký bởi authorizedSigner.
    ///   10. Ghi nhận trạng thái và phát ra sự kiện CharacterRegistered.
    /// @param voucher Dữ liệu phiếu cấp phép từ Backend AI
    /// @param signature Chữ ký số ECDSA (65 bytes)
    function registerCharacter(
        CharacterVoucher calldata voucher,
        bytes calldata signature
    ) external returns (bool) {
        // 1. Kiểm tra quyền của người gọi giao dịch
        if (msg.sender != voucher.owner) revert UnauthorizedCaller();

        // 2. Kiểm tra thời hạn
        if (block.timestamp > voucher.deadline) revert VoucherExpired();

        // 3. Kiểm tra địa chỉ ví
        if (voucher.owner == address(0)) revert InvalidOwner();

        // 4. Kiểm tra định dạng ID
        if (!isValidCharacterId(voucher.characterId)) revert InvalidCharacterId();

        // 5. Kiểm tra hash khác 0
        if (voucher.characterHash == bytes32(0)) revert InvalidCharacterHash();

        // 6. Kiểm tra chống replay nonce
        if (usedNonces[voucher.nonce]) revert NonceAlreadyUsed(voucher.nonce);

        // 7. Kiểm tra trùng lặp characterId
        if (_characters[voucher.characterId].owner != address(0)) {
            revert CharacterAlreadyRegistered(voucher.characterId);
        }

        // 8. Kiểm tra chính sách một hash cho một nhân vật
        if (bytes(_hashToCharacterId[voucher.characterHash]).length > 0) {
            revert CharacterHashAlreadyRegistered(
                voucher.characterHash,
                _hashToCharacterId[voucher.characterHash]
            );
        }

        // 9. Xác minh chữ ký EIP-712
        bytes32 digest = hashVoucher(voucher);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || recovered != authorizedSigner) {
            revert InvalidSignature();
        }

        // 10. Ghi nhận trạng thái (State changes)
        usedNonces[voucher.nonce] = true;

        _characters[voucher.characterId] = CharacterRecord({
            characterHash: voucher.characterHash,
            owner: voucher.owner,
            registeredAt: block.timestamp,
            characterId: voucher.characterId
        });

        _hashToCharacterId[voucher.characterHash] = voucher.characterId;
        totalCharacters += 1;

        // 11. Phát event chuẩn cho Backend AI RPC Verifier
        emit CharacterRegistered(voucher.characterId, voucher.characterHash, voucher.owner);

        return true;
    }

    // ------------------------------------------------------------------
    // Admin Functions
    // ------------------------------------------------------------------

    /// @notice Thay đổi địa chỉ ví Backend Authorization Signer (chỉ dành cho Owner)
    /// @param newSigner Địa chỉ ví ký mới
    function updateSigner(address newSigner) external onlyOwner {
        if (newSigner == address(0)) revert InvalidSigner();
        address oldSigner = authorizedSigner;
        authorizedSigner = newSigner;
        emit SignerUpdated(oldSigner, newSigner);
    }
}
