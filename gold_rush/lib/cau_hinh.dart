import 'package:flutter/material.dart';

/// Toàn bộ con số điều chỉnh gameplay gom về một chỗ.
///
/// Đây là thói quen quan trọng khi làm game: muốn cân bằng độ khó thì sửa ở
/// đây, không phải đi lùng từng tệp. Sinh viên có thể đổi các số này rồi chạy
/// lại để thấy game dễ hay khó đi ngay.
class CauHinh {
  CauHinh._();

  // ---------- Bản đồ ----------
  /// Kích thước một ô của tileset, tính bằng pixel.
  static const double kichThuocO = 16;

  /// Tên các lớp trong tệp .tmx. Đổi tên trong Tiled thì phải đổi ở đây.
  static const String lopNen = 'Nen';
  static const String lopTrangTri = 'TrangTri';
  static const String lopVaCham = 'VaCham';
  static const String lopDoiTuong = 'DoiTuong';

  // ---------- Camera ----------
  /// Số ô chiều ngang mà người chơi luôn nhìn thấy, bất kể màn hình to nhỏ.
  ///
  /// Đây chính là cách giải quyết bài toán của Chương 8 trong sách: thay vì
  /// vẽ theo pixel màn hình, ta cố định "tầm nhìn" theo đơn vị thế giới rồi
  /// để camera tự phóng to thu nhỏ.
  static const double soONhinThayNgang = 22;
  static const double zoomToiThieu = 1.2;
  static const double zoomToiDa = 6.0;

  // ---------- George ----------
  static const double tocDoGeorge = 74; // pixel thế giới mỗi giây
  static const int mauToiDa = 100;
  static const int mauMatMoiLanTrung = 25;

  /// Thời gian bất tử sau khi trúng đòn, tính bằng giây.
  /// Không có khoảng này thì đứng cạnh hai con quái là mất máu tức thì.
  static const double thoiGianBatTu = 1.2;

  // ---------- Kẻ địch ----------
  static const double tocDoZombie = 40;
  static const double tocDoSkeleton = 54;

  /// Bán kính phát hiện người chơi, tính bằng pixel thế giới.
  static const double tamNhinZombie = 96;
  static const double tamNhinSkeleton = 128;

  /// Ra khỏi vòng này thì kẻ địch thôi đuổi (lớn hơn tầm nhìn để tránh
  /// trạng thái nhấp nháy đuổi–thôi liên tục ở đúng mép vòng tròn).
  static const double heSoMatDau = 1.45;

  // ---------- AI kẻ địch (lib/ai/) ----------
  /// Mất dấu người chơi thì đi tới chỗ thấy lần cuối, tối đa chừng này giây.
  static const double thoiGianTimKiem = 4.0;

  /// Bao lâu tính lại đường A* một lần. Người chơi di chuyển liên tục nên
  /// đường cũ nhanh lỗi thời; tính mỗi khung hình thì phí.
  static const double chuKyTinhDuong = 0.4;

  /// Nhìn trước tối đa bấy nhiêu ô trên đường đi để "cắt góc" cho mượt.
  static const int soONhamTruoc = 6;

  // ---------- Đồng xu ----------
  static const int diemMoiDongXu = 20;

  // ---------- Kích thước hộp va chạm ----------
  /// Hộp va chạm với địa hình nhỏ hơn sprite và nằm ở phần chân, để nhân vật
  /// có thể "đi lấn" vào tán cây phía trên mà vẫn trông tự nhiên.
  static const double rongHopChan = 10;
  static const double caoHopChan = 7;

  // ---------- Màu sắc giao diện ----------
  static const Color mauChinh = Color(0xFFE3A008);
  static const Color mauNen = Color(0xFF1B2430);
  static const Color mauNenMo = Color(0xCC121820);
  static const Color mauChu = Color(0xFFF2F4F7);
  static const Color mauMau = Color(0xFFDC4A3D); // màu thanh máu
  static const Color mauMauNen = Color(0x66000000);
}

/// Bốn hướng nhìn của nhân vật, khớp với 4 hàng của sprite sheet.
///
/// Thứ tự phải đúng: hàng 0 = xuống, 1 = trái, 2 = phải, 3 = lên.
/// Xem `cong-cu/sinh_tai_nguyen.py`, hàm `ve_nhan_vat`.
enum HuongDi { xuong, trai, phai, len }

/// Trạng thái tổng của ván chơi.
enum TrangThaiChoi { dangChoi, tamDung, thua, thang }
