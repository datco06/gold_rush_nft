/// Loại vật phẩm dùng để hiển thị và phân nhóm.
enum LoaiVatPham { vuKhi, giap, vatPham }

/// Độ hiếm do nguồn dữ liệu cung cấp.
enum DoHiemVatPham { thuong, khongPhoBien, hiem, suThi, huyenThoai }

/// Nguồn vật phẩm, không phải bằng chứng quyền sở hữu.
enum NguonVatPham { game, nft }

/// Ô trang bị đề xuất để thống nhất với module Gameplay.
enum OTrangBi { vuKhiChinh, vuKhiPhu, giap }

/// Biểu tượng dự phòng khi vật phẩm chưa có ảnh.
/// Không quyết định cơ chế gameplay.
enum BieuTuongVatPham { kiem, cung, giap, binhHoiPhuc, macDinh }

/// Dữ liệu phục vụ giao diện.
///
/// Đây là model đề xuất, chưa phải hợp đồng API đã chốt.
/// Không xử lý sát thương, xác minh NFT hoặc lưu trang bị.
class VatPhamHienThi {
  final String id;
  final String ten;
  final String moTa;
  final LoaiVatPham loai;
  final DoHiemVatPham doHiem;
  final NguonVatPham nguon;
  final BieuTuongVatPham bieuTuong;

  /// Đường dẫn ảnh asset.
  /// Null thì giao diện dùng biểu tượng thay thế.
  final String? duongDanAnh;

  /// Thuộc tính hiển thị do module nghiệp vụ cung cấp.
  final Map<String, String> thuocTinh;

  /// Null nếu vật phẩm chưa được trang bị.
  /// UI chờ dữ liệu xác nhận, không tự đổi giá trị này.
  final OTrangBi? oDangTrangBi;

  /// Chỉ bật cho dữ liệu minh họa trong demo/test.
  final bool laDuLieuMau;

  /// Thông tin NFT để hiển thị, không tự xác minh sở hữu.
  final int? chainId;
  final String? diaChiHopDong;
  final String? tokenId;

  VatPhamHienThi({
    required this.id,
    required this.ten,
    required this.loai,
    required this.doHiem,
    required this.nguon,
    this.bieuTuong = BieuTuongVatPham.macDinh,
    this.moTa = '',
    this.duongDanAnh,
    Map<String, String> thuocTinh = const {},
    this.oDangTrangBi,
    this.laDuLieuMau = false,
    this.chainId,
    this.diaChiHopDong,
    this.tokenId,
  }) : thuocTinh = Map<String, String>.unmodifiable(thuocTinh) {
    if (id.trim().isEmpty || ten.trim().isEmpty) {
      throw ArgumentError('Vật phẩm phải có ID và tên.');
    }

    if (nguon == NguonVatPham.nft) {
      if (chainId == null ||
          chainId! <= 0 ||
          diaChiHopDong == null ||
          diaChiHopDong!.trim().isEmpty ||
          tokenId == null ||
          tokenId!.trim().isEmpty) {
        throw ArgumentError(
          'Vật phẩm NFT cần có chain ID, '
          'địa chỉ hợp đồng và token ID.',
        );
      }
    } else if (chainId != null || diaChiHopDong != null || tokenId != null) {
      throw ArgumentError(
        'Thông tin Blockchain chỉ dành cho vật phẩm nguồn NFT.',
      );
    }
  }

  bool get dangTrangBi => oDangTrangBi != null;
}
