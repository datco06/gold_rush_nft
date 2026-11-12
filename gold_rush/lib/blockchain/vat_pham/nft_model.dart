/// Phân loại metadata để hiển thị; hợp đồng ERC-1155 không lưu category.
enum LoaiVatPhamNFT { vuKhi, giap, khien }

/// Chỉ đặt daKiemTra sau khi đọc balanceOf cho đúng ví/mạng/hợp đồng/tokenId.
enum TrangThaiSoDuNFT { chuaKiemTra, daKiemTra }

/// Một loại vật phẩm ERC-1155 và ảnh chụp số dư của MỘT ví.
///
/// Model thuần Dart, không gọi RPC/API, ký phiếu hay gửi giao dịch. Metadata
/// không chứng minh sở hữu; kết quả giao dịch cũng không tự xác nhận số dư.
/// Lớp gọi phải đọc lại Blockchain sau mint/chuyển và khi đổi phiên ví.
/// Trạng thái trang bị/sức mạnh do Gameplay/Backend quản lý, không nằm ở đây.
class VatPhamNFT {
  /// ID của loại ERC-1155, không phải số sê-ri của từng bản. ID > 0 theo hợp đồng.
  final BigInt tokenId;

  // Metadata hiển thị từ danh mục/Backend/URI, độc lập với balanceOf trên chuỗi.
  final String name;
  final String description;
  final LoaiVatPhamNFT category;

  /// null khi chưa có ảnh; không tự gán asset hoặc đường dẫn ảnh giả.
  final String? imageUrl;

  /// null khi chưa biết URI hoặc loại chưa đăng ký. Không tải URI trong model.
  final String? metadataUri;

  /// Giới hạn toàn loại, không phải số dư ví hay tổng đã mint.
  /// null khi chưa biết; service sau này cần đọc maxSupply(tokenId) từ hợp đồng.
  final BigInt? maxSupply;

  /// Ngữ cảnh định danh token; tạo model mới khi đổi hợp đồng/mạng/tokenId.
  final String contractAddress;

  /// Dùng int như PhienVi/CauHinhSBT; giới hạn số nguyên an toàn cho Flutter Web.
  final int chainId;

  /// Ví của ảnh chụp số dư; null khi chỉ có metadata danh mục.
  final String? walletAddress;

  /// null là chưa có dữ liệu, khác với balanceOf trả về 0.
  /// Khi balanceStatus = chuaKiemTra, giá trị này chỉ là cache chưa xác minh lại.
  final BigInt? balance;
  final TrangThaiSoDuNFT balanceStatus;

  VatPhamNFT({
    required this.tokenId,
    required this.name,
    required this.description,
    required this.category,
    required this.contractAddress,
    required this.chainId,
    this.imageUrl,
    this.metadataUri,
    this.maxSupply,
    this.walletAddress,
    this.balance,
    this.balanceStatus = TrangThaiSoDuNFT.chuaKiemTra,
  }) {
    _kiemUint256(tokenId, 'tokenId', duong: true);
    if (balance != null) _kiemUint256(balance!, 'balance');
    if (maxSupply != null) _kiemUint256(maxSupply!, 'maxSupply', duong: true);
    if (chainId <= 0 || chainId > _soNguyenJsonAnToan) {
      throw ArgumentError.value(
        chainId,
        'chainId',
        'Phải là số nguyên dương <= 2^53−1',
      );
    }
    _kiemDiaChi(contractAddress, 'contractAddress');
    if (walletAddress != null) _kiemDiaChi(walletAddress!, 'walletAddress');
    if (metadataUri != null && metadataUri!.isEmpty) {
      throw ArgumentError.value(
        metadataUri,
        'metadataUri',
        'URI không được rỗng',
      );
    }
    if (balanceStatus == TrangThaiSoDuNFT.daKiemTra &&
        (balance == null || walletAddress == null)) {
      throw ArgumentError('Số dư đã kiểm tra cần có balance và walletAddress');
    }
  }

  /// Chỉ true khi lớp gọi đã xác minh balanceOf cho ngữ cảnh của model.
  bool get owned => verifiedBalance != null && verifiedBalance! > BigInt.zero;

  /// Dùng cho UI cần số dư đã xác minh; null nghĩa là cần tải lại Blockchain.
  /// Kết quả 0 là đã kiểm tra và ví không có bản nào của loại này.
  BigInt? get verifiedBalance =>
      balanceStatus == TrangThaiSoDuNFT.daKiemTra ? balance : null;

  /// Đọc JSON của model/cache ứng dụng, không phải parser metadata ERC-1155 thô.
  ///
  /// Giữ balance để hiển thị cache khi cần nhưng LUÔN bỏ trạng thái xác minh.
  /// Không tin balanceStatus/owned/equipped do JSON cung cấp. Service phải đọc
  /// balanceOf(walletAddress, tokenId) trên đúng contractAddress/chainId trước
  /// khi đặt balanceStatus = daKiemTra; không dựa vào metadata hay receipt.
  factory VatPhamNFT.fromJson(Map<String, dynamic> json) {
    try {
      final chain = _docUint256(json['chainId'], 'chainId', duong: true);
      if (chain > BigInt.from(_soNguyenJsonAnToan)) {
        throw const FormatException('chainId vượt giới hạn int an toàn 2^53−1');
      }
      return VatPhamNFT(
        tokenId: _docUint256(json['tokenId'], 'tokenId', duong: true),
        name: _docChuoi(json['name'], 'name'),
        description: _docChuoi(json['description'], 'description'),
        category: _docLoai(json['category']),
        imageUrl: _docChuoiTuyChon(json['imageUrl'], 'imageUrl'),
        metadataUri: _docChuoiTuyChon(json['metadataUri'], 'metadataUri'),
        maxSupply: json['maxSupply'] == null
            ? null
            : _docUint256(json['maxSupply'], 'maxSupply', duong: true),
        contractAddress: _docChuoi(json['contractAddress'], 'contractAddress'),
        chainId: chain.toInt(),
        walletAddress: _docChuoiTuyChon(json['walletAddress'], 'walletAddress'),
        balance: json['balance'] == null
            ? null
            : _docUint256(json['balance'], 'balance'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Dữ liệu NFT không hợp lệ: ${error.message}');
    }
  }

  /// uint256 luôn ghi thành chuỗi thập phân, không làm tròn qua JSON number.
  /// balanceStatus chỉ là ảnh chụp để quan sát, không được khôi phục như bằng chứng.
  Map<String, dynamic> toJson() => {
    'tokenId': tokenId.toString(),
    'name': name,
    'description': description,
    'category': category.name,
    'imageUrl': imageUrl,
    'balance': balance?.toString(),
    'maxSupply': maxSupply?.toString(),
    'metadataUri': metadataUri,
    'contractAddress': contractAddress,
    'chainId': chainId,
    'walletAddress': walletAddress,
    'balanceStatus': balanceStatus.name,
  };

  /// tokenId/contractAddress/chainId cố định; tạo model mới cho ngữ cảnh khác.
  /// null nghĩa là giữ; các cờ clear ưu tiên xóa trường nullable.
  /// Đổi ví hoặc số dư sẽ bỏ xác minh, trừ khi lớp gọi truyền rõ daKiemTra
  /// cùng dữ liệu đã đọc từ Blockchain. Xóa ví/số dư luôn bỏ xác minh.
  VatPhamNFT copyWith({
    String? name,
    String? description,
    LoaiVatPhamNFT? category,
    String? imageUrl,
    bool clearImageUrl = false,
    String? metadataUri,
    bool clearMetadataUri = false,
    BigInt? maxSupply,
    bool clearMaxSupply = false,
    String? walletAddress,
    bool clearWalletAddress = false,
    BigInt? balance,
    bool clearBalance = false,
    TrangThaiSoDuNFT? balanceStatus,
  }) {
    final viMoi = clearWalletAddress
        ? null
        : walletAddress ?? this.walletAddress;
    final doiVi = viMoi?.toLowerCase() != this.walletAddress?.toLowerCase();
    final soDuMoi = clearBalance
        ? null
        : balance ?? (doiVi ? null : this.balance);
    final doiSoDu = soDuMoi != this.balance;
    final trangThaiMoi = clearBalance || clearWalletAddress
        ? TrangThaiSoDuNFT.chuaKiemTra
        : balanceStatus ??
              (doiVi || doiSoDu
                  ? TrangThaiSoDuNFT.chuaKiemTra
                  : this.balanceStatus);
    return VatPhamNFT(
      tokenId: tokenId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      imageUrl: clearImageUrl ? null : imageUrl ?? this.imageUrl,
      metadataUri: clearMetadataUri ? null : metadataUri ?? this.metadataUri,
      maxSupply: clearMaxSupply ? null : maxSupply ?? this.maxSupply,
      contractAddress: contractAddress,
      chainId: chainId,
      walletAddress: viMoi,
      balance: soDuMoi,
      balanceStatus: trangThaiMoi,
    );
  }
}

const int _soNguyenJsonAnToan = 9007199254740991;

void _kiemUint256(BigInt value, String field, {bool duong = false}) {
  if (value < BigInt.zero ||
      value.bitLength > 256 ||
      (duong && value == BigInt.zero)) {
    throw ArgumentError.value(
      value,
      field,
      'Phải là uint256${duong ? ' lớn hơn 0' : ''}',
    );
  }
}

BigInt _docUint256(Object? value, String field, {bool duong = false}) {
  final BigInt n;
  if (value is int && value >= 0 && value <= _soNguyenJsonAnToan) {
    n = BigInt.from(value);
  } else if (value is String && RegExp(r'^[0-9]+$').hasMatch(value)) {
    n = BigInt.parse(value);
  } else {
    throw FormatException(
      '$field phải là số nguyên JSON an toàn hoặc chuỗi thập phân',
    );
  }
  _kiemUint256(n, field, duong: duong);
  return n;
}

String _docChuoi(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field phải là String');
}

String? _docChuoiTuyChon(Object? value, String field) =>
    value == null ? null : _docChuoi(value, field);

LoaiVatPhamNFT _docLoai(Object? value) {
  for (final loai in LoaiVatPhamNFT.values) {
    if (loai.name == value) return loai;
  }
  throw FormatException('category phải là vuKhi, giap hoặc khien: $value');
}

void _kiemDiaChi(String value, String field) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value) ||
      RegExp(r'^0x0{40}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      field,
      'Địa chỉ EVM phải có 20 byte và khác zero',
    );
  }
}
