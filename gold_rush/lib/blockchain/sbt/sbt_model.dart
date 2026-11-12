/// Kết quả kiểm tra điều kiện trong game từ Backend, độc lập với quyền sở hữu.
enum TrangThaiDieuKienSBT { chuaKiemTra, chuaDuDieuKien, duDieuKien }

/// Chỉ đặt [daSoHuu] sau khi đọc Blockchain cho đúng ví, mạng và hợp đồng.
enum TrangThaiSoHuuSBT { chuaKiemTra, chuaSoHuu, daSoHuu }

/// Tiến độ UI của giao dịch nhận; [thanhCong] không tự xác nhận quyền sở hữu.
enum TrangThaiNhanSBT {
  chuaBatDau,
  choXacNhanVi,
  dangGui,
  choXacNhanChuoi,
  thanhCong,
  thatBai,
  daHuy,
}

/// Một huy hiệu và trạng thái của nó đối với MỘT ví/mạng/hợp đồng.
///
/// Lớp gọi chịu trách nhiệm đọc Blockchain và tạo lại trạng thái khi đổi ví/mạng.
/// Đây là model thuần Dart: không gọi RPC, API, ký phiếu hay gửi giao dịch.
/// ID thành tích giới hạn 1–5 theo ThanhTuuSBT.sol; tokenId là uint256 độc lập,
/// không được suy ra tokenId từ achievementId hoặc thứ tự danh mục.
class ThanhTuuSBT {
  final int achievementId;
  final String name;
  final String description;

  /// null khi chưa có ảnh. Chỉ gán đường dẫn asset đã tồn tại và được khai báo.
  final String? imagePath;

  /// Token ID lấy từ SBTClaimed/Blockchain, hoặc bản cache chưa xác minh lại.
  /// Có tokenId không đồng nghĩa đã xác minh quyền sở hữu của ví hiện tại.
  final BigInt? tokenId;
  final TrangThaiDieuKienSBT eligibilityStatus;
  final TrangThaiSoHuuSBT ownershipStatus;
  final TrangThaiNhanSBT claimStatus;

  /// Lựa chọn hồ sơ từ UI/Backend; không phải thuộc tính của hợp đồng SBT.
  /// Giới hạn tối đa ba huy hiệu do lớp quản lý hồ sơ áp dụng cho cả danh sách.
  final bool selectedForDisplay;

  ThanhTuuSBT({
    required this.achievementId,
    required this.name,
    required this.description,
    this.imagePath,
    this.tokenId,
    this.eligibilityStatus = TrangThaiDieuKienSBT.chuaKiemTra,
    this.ownershipStatus = TrangThaiSoHuuSBT.chuaKiemTra,
    this.claimStatus = TrangThaiNhanSBT.chuaBatDau,
    this.selectedForDisplay = false,
  }) {
    if (achievementId < 1 || achievementId > 5) {
      throw RangeError.range(achievementId, 1, 5, 'achievementId');
    }
    if (tokenId != null &&
        (tokenId! <= BigInt.zero || tokenId!.bitLength > 256)) {
      throw ArgumentError.value(
        tokenId,
        'tokenId',
        'Phải là uint256 lớn hơn 0',
      );
    }
  }

  bool get eligible => eligibilityStatus == TrangThaiDieuKienSBT.duDieuKien;
  bool get owned => ownershipStatus == TrangThaiSoHuuSBT.daSoHuu;

  /// Chỉ hiển thị lựa chọn hồ sơ sau khi đã xác minh quyền sở hữu trên chuỗi.
  bool get displayed => owned && selectedForDisplay;

  /// Đọc metadata và trạng thái cache, KHÔNG coi JSON là bằng chứng sở hữu.
  ///
  /// Luôn đặt ownershipStatus = chuaKiemTra, kể cả JSON ghi owned = true hoặc
  /// ownershipStatus = daSoHuu. tokenId và tiến độ giao dịch chỉ là bản cache;
  /// lớp gọi phải đọc hasAchievement(player, achievementId) trước khi đặt
  /// ownershipStatus. Hợp đồng không có tokenOfOwnerByIndex; chỉ hasAchievement
  /// cũng đủ xác minh owned khi chưa biết tokenId cụ thể.
  factory ThanhTuuSBT.fromJson(Map<String, dynamic> json) {
    final rawId = json['achievementId'];
    final id = rawId is int
        ? rawId
        : rawId is String && RegExp(r'^[1-5]$').hasMatch(rawId)
        ? int.parse(rawId)
        : null;
    if (id == null || id < 1 || id > 5) {
      throw const FormatException('achievementId phải là số nguyên từ 1 đến 5');
    }
    return ThanhTuuSBT(
      achievementId: id,
      name: _docChuoi(json['name'], 'name'),
      description: _docChuoi(json['description'], 'description'),
      imagePath: json['imagePath'] == null
          ? null
          : _docChuoi(json['imagePath'], 'imagePath'),
      tokenId: _docTokenId(json['tokenId']),
      eligibilityStatus: _docTrangThai(
        json['eligibilityStatus'],
        TrangThaiDieuKienSBT.values,
        TrangThaiDieuKienSBT.chuaKiemTra,
        'eligibilityStatus',
      ),
      claimStatus: _docTrangThai(
        json['claimStatus'],
        TrangThaiNhanSBT.values,
        TrangThaiNhanSBT.chuaBatDau,
        'claimStatus',
      ),
      selectedForDisplay: switch (json['selectedForDisplay']) {
        null => false,
        bool value => value,
        _ => throw const FormatException('selectedForDisplay phải là bool'),
      },
    );
  }

  /// uint256 được ghi thành chuỗi thập phân để không mất chính xác trên Flutter Web.
  /// owned/ownershipStatus/displayed là ảnh chụp trạng thái, không được tin lại
  /// khi fromJson; cần xác minh lại Blockchain sau khi nạp cache.
  Map<String, dynamic> toJson() => {
    'achievementId': achievementId,
    'name': name,
    'description': description,
    'imagePath': imagePath,
    'tokenId': tokenId?.toString(),
    'eligibilityStatus': eligibilityStatus.name,
    'ownershipStatus': ownershipStatus.name,
    'claimStatus': claimStatus.name,
    'selectedForDisplay': selectedForDisplay,
    'owned': owned,
    'displayed': displayed,
  };

  /// Không suy ra quyền sở hữu từ điều kiện, tokenId hoặc kết quả giao dịch.
  /// clearImagePath/clearTokenId ưu tiên xóa giá trị; nếu không, null nghĩa là giữ.
  ThanhTuuSBT copyWith({
    String? name,
    String? description,
    String? imagePath,
    bool clearImagePath = false,
    BigInt? tokenId,
    bool clearTokenId = false,
    TrangThaiDieuKienSBT? eligibilityStatus,
    TrangThaiSoHuuSBT? ownershipStatus,
    TrangThaiNhanSBT? claimStatus,
    bool? selectedForDisplay,
  }) => ThanhTuuSBT(
    achievementId: achievementId,
    name: name ?? this.name,
    description: description ?? this.description,
    imagePath: clearImagePath ? null : imagePath ?? this.imagePath,
    tokenId: clearTokenId ? null : tokenId ?? this.tokenId,
    eligibilityStatus: eligibilityStatus ?? this.eligibilityStatus,
    ownershipStatus: ownershipStatus ?? this.ownershipStatus,
    claimStatus: claimStatus ?? this.claimStatus,
    selectedForDisplay: selectedForDisplay ?? this.selectedForDisplay,
  );
}

String _docChuoi(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field phải là String');
}

T _docTrangThai<T extends Enum>(
  Object? value,
  List<T> values,
  T macDinh,
  String field,
) {
  if (value == null) return macDinh;
  for (final trangThai in values) {
    if (trangThai.name == value) return trangThai;
  }
  throw FormatException('$field không hợp lệ: $value');
}

BigInt? _docTokenId(Object? value) {
  if (value == null) return null;
  // JSON number lớn hơn 2^53−1 có thể đã mất chính xác trong trình duyệt.
  if (value is int && value > 0 && value <= 9007199254740991) {
    return BigInt.from(value);
  }
  if (value is String && RegExp(r'^[0-9]+$').hasMatch(value)) {
    final tokenId = BigInt.parse(value);
    if (tokenId > BigInt.zero && tokenId.bitLength <= 256) return tokenId;
  }
  throw const FormatException(
    'tokenId phải là uint256 lớn hơn 0; số lớn phải dùng chuỗi thập phân',
  );
}

/// Danh mục hiển thị, KHÔNG phải kết quả kiểm tra quyền sở hữu hay điều kiện.
/// Chưa có asset huy hiệu SBT trong repository nên imagePath đều là null.
final List<ThanhTuuSBT> bangThanhTuuSBT = List<ThanhTuuSBT>.unmodifiable([
  ThanhTuuSBT(
    achievementId: 1,
    name: 'Thợ Mỏ Tập Sự',
    description: 'Hoàn thành màn 1.',
  ),
  ThanhTuuSBT(
    achievementId: 2,
    name: 'Nhà Thám Hiểm Rừng Xanh',
    description: 'Hoàn thành 6 màn.',
  ),
  ThanhTuuSBT(
    achievementId: 3,
    name: 'Kẻ Săn Boss',
    description: 'Đánh bại Boss đầu tiên.',
  ),
  ThanhTuuSBT(
    achievementId: 4,
    name: 'Chiến Binh Bất Bại',
    description: 'Đánh bại Boss không mất máu.',
  ),
  ThanhTuuSBT(
    achievementId: 5,
    name: 'Huyền Thoại Gold Rush',
    description: 'Hoàn thành thử thách đặc biệt.',
  ),
]);
