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
    giaGoiY: 1,
    tepAnh: 'george_tho_mo.png',
  ),
  NhanVatBan(
    id: 2,
    ten: 'Cao bồi',
    moTa: 'Áo da nâu, khăn đỏ.',
    giaGoiY: 600,
    tepAnh: 'george_cao_boi.png',
  ),
  NhanVatBan(
    id: 3,
    ten: 'Hiệp sĩ vàng',
    moTa: 'Giáp ánh kim — dành cho người nhặt chăm nhất.',
    giaGoiY: 600,
    tepAnh: 'george_hiep_si.png',
  ),
  NhanVatBan(
    id: 4,
    ten: 'Thợ mỏ pixel',
    moTa: 'Nhân vật pixel art bốn hướng, trang bị sẵn để chơi.',
    giaGoiY: 600,
    tepAnh: 'nhan_vat_tho_mo_ai.png',
  ),
  NhanVatBan(
    id: 5,
    ten: 'Mèo máy vàng',
    moTa: 'Nhân vật pixel art bốn hướng với hoạt ảnh riêng.',
    giaGoiY: 600,
    tepAnh: 'nhan_vat_doraemon_ai.png',
  ),
  NhanVatBan(
    id: 6,
    ten: 'Nhà thám hiểm nữ',
    moTa: 'Nhân vật nữ pixel art bốn hướng.',
    giaGoiY: 600,
    tepAnh: 'nhan_vat_nu_ai.png',
  ),
  NhanVatBan(
    id: 7,
    ten: 'Nhà thám hiểm đào vàng',
    moTa: 'Nhà thám hiểm pixel art với đèn mũ và ba lô.',
    giaGoiY: 600,
    tepAnh: 'nhan_vat_tham_hiem_pixel.png',
  ),
  NhanVatBan(
    id: 8,
    ten: 'Nhà thám hiểm cơn sốt vàng',
    moTa: 'Nhà thám hiểm pixel art phong cách cơn sốt vàng.',
    giaGoiY: 600,
    tepAnh: 'nhan_vat_con_sot_vang.png',
  ),
  NhanVatBan(
    id: 9,
    ten: 'Thợ mỏ chibi',
    moTa: 'Thợ mỏ chibi pixel art bốn hướng.',
    giaGoiY: 600,
    tepAnh: 'nhan_vat_tho_mo_chibi.png',
  ),
];
