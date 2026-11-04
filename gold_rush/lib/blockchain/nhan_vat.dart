/// Danh mục nhân vật bán trong cửa hàng.
///
/// id và giá PHẢI khớp `ignition/modules/CuaHangGoldRush.ts` (lệnh `datGia`). Giá thật luôn
/// đọc lại từ hợp đồng (`gia(id)`) trước khi mua — bảng này chỉ để hiển thị khi chưa kết nối.
///
/// Nhân vật chỉ đổi NGOẠI HÌNH, không đổi sức mạnh: mua bằng vàng không được biến thành
/// "trả tiền để thắng". Đây là quyết định thiết kế, xem tài liệu đề xuất.
class NhanVatBan {
  final int id;
  final String ten;
  final String moTa;
  final int giaGoiY;

  /// Ảnh sprite sheet 4 hướng × 4 khung trong assets/images/.
  final String tepAnh;

  const NhanVatBan({
    required this.id,
    required this.ten,
    required this.moTa,
    required this.giaGoiY,
    required this.tepAnh,
  });
}

/// George gốc: miễn phí, ai cũng có, không nằm trên chuỗi.
const NhanVatBan georgeGoc = NhanVatBan(
  id: 0,
  ten: 'George',
  moTa: 'Nhà tìm vàng nguyên bản.',
  giaGoiY: 0,
  tepAnh: 'george.png',
);

const List<NhanVatBan> bangNhanVat = [
  NhanVatBan(
    id: 1,
    ten: 'Thợ mỏ',
    moTa: 'Mũ bảo hộ vàng, áo xanh công nhân.',
    giaGoiY: 10,
    tepAnh: 'george_tho_mo.png',
  ),
  NhanVatBan(
    id: 2,
    ten: 'Cao bồi',
    moTa: 'Áo da nâu, khăn đỏ.',
    giaGoiY: 30,
    tepAnh: 'george_cao_boi.png',
  ),
  NhanVatBan(
    id: 3,
    ten: 'Hiệp sĩ vàng',
    moTa: 'Giáp ánh kim — dành cho người nhặt chăm nhất.',
    giaGoiY: 60,
    tepAnh: 'george_hiep_si.png',
  ),
];
