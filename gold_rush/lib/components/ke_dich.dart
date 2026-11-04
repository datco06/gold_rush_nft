import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Color;

import '../ai/tim_duong.dart';
import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import 'ban_do.dart';
import 'hieu_ung.dart';
import 'nhan_vat.dart';

/// Ba trạng thái của kẻ địch.
///
/// `timKiem` là trạng thái mới của phiên bản có AI tìm đường: mất dấu người
/// chơi thì đi tới CHỖ THẤY LẦN CUỐI (tối đa `CauHinh.thoiGianTimKiem` giây),
/// thay vì lập tức quay về đi lang thang như thể chưa từng thấy ai.
enum TrangThaiKeDich { tuanTra, duoiTheo, timKiem }

/// Zombie và skeleton. Khác nhau ở tốc độ, tầm nhìn và màu vụn nổ.
///
/// Phần trí tuệ nhân tạo ở đây cố tình giữ thật đơn giản để đọc là hiểu, đúng
/// tinh thần Chương 10 của sách. Ba ý chính:
///
///   1. **Máy trạng thái.** Chỉ hai trạng thái: tuần tra và đuổi theo. Gần như
///      mọi AI trong game thương mại đều bắt đầu từ khuôn mẫu này.
///   2. **Đường ngắm.** Không phải cứ ở gần là thấy. Có tường chắn giữa hai
///      bên thì kẻ địch vẫn tuần tra như thường — nhờ vậy người chơi có thể
///      nấp, và trò chơi có chiều sâu.
///   3. **Ngưỡng trễ.** Vòng thôi đuổi rộng hơn vòng phát hiện. Không có
///      khoảng trễ này thì đứng đúng mép vòng tròn, kẻ địch sẽ nhấp nháy
///      đuổi–thôi liên tục mỗi khung hình.
///
/// Phiên bản AI (thư mục `lib/ai/`) thêm hai thứ, đều TUỲ CHỌN:
///   4. **Tìm đường A\*.** Truyền [timDuong] thì kẻ địch đi theo đường ngắn
///      nhất trên lưới ô, vòng qua cả dãy tường. Không truyền thì dùng lại
///      cách "đi thẳng, bị chặn thì trượt" của bản gốc.
///   5. **Hệ số tốc độ.** [heSoTocDo] do bộ điều chỉnh độ khó cung cấp.
class KeDich extends NhanVat {
  /// Trả về vị trí người chơi. Truyền hàm thay vì truyền thẳng đối tượng
  /// George để tệp này không phụ thuộc vào tệp george.dart.
  final Vector2 Function() viTriNguoiChoi;

  final double tocDo;
  final double tamNhin;
  final Color mauVunNo;

  /// Bộ tìm đường dùng chung cho mọi kẻ địch. null = không dùng A*.
  final TimDuong? timDuong;

  /// Hệ số nhân tốc độ (1.0 = gốc), đọc mỗi khung hình.
  final double Function() heSoTocDo;

  TrangThaiKeDich trangThai = TrangThaiKeDich.tuanTra;

  /// Đường đi hiện tại (các ô phía trước) và đồng hồ tính lại đường.
  List<O> _duongDi = const [];
  double _demTinhDuong = 0;

  Vector2? _viTriThayCuoi;
  double _conLaiTimKiem = 0;

  final Random _rnd = Random();

  /// Hướng đang tuần tra và thời gian còn lại trước khi đổi hướng.
  Vector2 _huongTuanTra = Vector2.zero();
  double _conLaiTuanTra = 0;

  bool _daNo = false;

  KeDich({
    required super.banDo,
    required super.hoatAnh,
    required super.viTri,
    required this.viTriNguoiChoi,
    required this.tocDo,
    required this.tamNhin,
    required this.mauVunNo,
    this.timDuong,
    double Function()? heSoTocDo,
  }) : heSoTocDo = heSoTocDo ?? _mot;

  static double _mot() => 1.0;

  /// Zombie: chậm, tầm nhìn ngắn, vụn nổ xanh.
  factory KeDich.zombie({
    required BanDo banDo,
    required Map<HuongDi, SpriteAnimation> hoatAnh,
    required Vector2 viTri,
    required Vector2 Function() viTriNguoiChoi,
    TimDuong? timDuong,
    double Function()? heSoTocDo,
  }) {
    return KeDich(
      banDo: banDo,
      hoatAnh: hoatAnh,
      viTri: viTri,
      viTriNguoiChoi: viTriNguoiChoi,
      timDuong: timDuong,
      heSoTocDo: heSoTocDo,
      tocDo: CauHinh.tocDoZombie,
      tamNhin: CauHinh.tamNhinZombie,
      mauVunNo: const Color(0xFF7EB86C),
    );
  }

  /// Skeleton: nhanh hơn, nhìn xa hơn, vụn nổ trắng ngà.
  factory KeDich.skeleton({
    required BanDo banDo,
    required Map<HuongDi, SpriteAnimation> hoatAnh,
    required Vector2 viTri,
    required Vector2 Function() viTriNguoiChoi,
    TimDuong? timDuong,
    double Function()? heSoTocDo,
  }) {
    return KeDich(
      banDo: banDo,
      hoatAnh: hoatAnh,
      viTri: viTri,
      viTriNguoiChoi: viTriNguoiChoi,
      timDuong: timDuong,
      heSoTocDo: heSoTocDo,
      tocDo: CauHinh.tocDoSkeleton,
      tamNhin: CauHinh.tamNhinSkeleton,
      mauVunNo: const Color(0xFFE8E6D8),
    );
  }

  @override
  Future<void> onLoad() async {
    add(hopVaCham());
    _doiHuongTuanTra();
    // Lệch pha đồng hồ tính đường để 9 kẻ địch không cùng chạy A* một khung hình.
    _demTinhDuong = _rnd.nextDouble() * CauHinh.chuKyTinhDuong;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_daNo) return;

    _capNhatTrangThai(dt);

    var huong = Vector2.zero();
    switch (trangThai) {
      case TrangThaiKeDich.duoiTheo:
        huong = _huongTheoDuong(dt, viTriNguoiChoi()) ?? _huongDuoiTheo();
      case TrangThaiKeDich.timKiem:
        final h = _huongTheoDuong(dt, _viTriThayCuoi ?? position);
        if (h == null) {
          // Đã tới chỗ thấy lần cuối mà không gặp ai: thôi, quay về tuần tra.
          _veTuanTra();
          huong = _huongTuanTraHienTai(dt);
        } else {
          huong = h;
        }
      case TrangThaiKeDich.tuanTra:
        huong = _huongTuanTraHienTai(dt);
    }

    if (huong.x == 0 && huong.y == 0) {
      datDangDi(false);
      return;
    }

    huong.normalize();
    capNhatHuong(huong);

    final coDi = thuDiChuyen(huong * (tocDo * heSoTocDo()) * dt);
    datDangDi(coDi);

    if (!coDi) {
      if (trangThai == TrangThaiKeDich.tuanTra) {
        // Tuần tra mà đâm vào tường thì đổi hướng ngay, không đứng ịn vào tường.
        _doiHuongTuanTra();
      } else {
        // Kẹt khi đang đi theo đường: tính lại đường ngay khung hình sau.
        _demTinhDuong = 0;
      }
    }
  }

  // ------------------------------------------------------------------
  // Máy trạng thái
  // ------------------------------------------------------------------
  void _capNhatTrangThai(double dt) {
    final nguoiChoi = viTriNguoiChoi();
    final khoangCach = position.distanceTo(nguoiChoi);

    switch (trangThai) {
      case TrangThaiKeDich.tuanTra:
      case TrangThaiKeDich.timKiem:
        if (khoangCach <= tamNhin && banDo.nhinThay(position, nguoiChoi)) {
          trangThai = TrangThaiKeDich.duoiTheo;
          _viTriThayCuoi = nguoiChoi.clone();
          _demTinhDuong = 0; // tính đường ngay
        } else if (trangThai == TrangThaiKeDich.timKiem) {
          _conLaiTimKiem -= dt;
          if (_conLaiTimKiem <= 0) _veTuanTra();
        }
      case TrangThaiKeDich.duoiTheo:
        // Mất dấu khi người chơi chạy ra xa HOẶC khuất sau vật cản.
        if (khoangCach > tamNhin * CauHinh.heSoMatDau ||
            !banDo.nhinThay(position, nguoiChoi)) {
          if (timDuong != null && _viTriThayCuoi != null) {
            trangThai = TrangThaiKeDich.timKiem;
            _conLaiTimKiem = CauHinh.thoiGianTimKiem;
            _demTinhDuong = 0;
          } else {
            _veTuanTra();
          }
        } else {
          _viTriThayCuoi = nguoiChoi.clone();
        }
    }
  }

  void _veTuanTra() {
    trangThai = TrangThaiKeDich.tuanTra;
    _duongDi = const [];
    _viTriThayCuoi = null;
    _doiHuongTuanTra();
  }

  // ------------------------------------------------------------------
  // Đi theo đường A*
  // ------------------------------------------------------------------

  /// Ô chứa một điểm thế giới.
  static O _oTai(Vector2 p) => (
        cot: (p.x / CauHinh.kichThuocO).floor(),
        hang: (p.y / CauHinh.kichThuocO).floor(),
      );

  /// Tâm của một ô, tính bằng pixel thế giới.
  static Vector2 _tamO(O o) => Vector2(
        (o.cot + 0.5) * CauHinh.kichThuocO,
        (o.hang + 0.5) * CauHinh.kichThuocO,
      );

  /// Hướng đi tới [dich] theo đường A*, hoặc null nếu không có A*, không có
  /// đường, hay đã ở cùng ô với đích (khi đó người gọi tự xử lý chặng cuối).
  ///
  /// Mọi phép tính dùng TÂM CHÂN (`tamChan`), vì va chạm với địa hình tính
  /// bằng hộp chân — dùng tâm sprite thì đường đi lệch nửa ô.
  Vector2? _huongTheoDuong(double dt, Vector2 dich) {
    final td = timDuong;
    if (td == null) return null;

    final chan = tamChan;
    _demTinhDuong -= dt;
    if (_demTinhDuong <= 0) {
      _demTinhDuong = CauHinh.chuKyTinhDuong;
      final dichChan = Vector2(dich.x, dich.y + 4);
      _duongDi = td.tim(_oTai(chan), _oTai(dichChan)) ?? const [];
    }

    // Bỏ các ô đã đi tới.
    final i = _duongDi.indexOf(_oTai(chan));
    if (i >= 0) _duongDi = _duongDi.sublist(i + 1);
    if (_duongDi.isEmpty) return null;

    // Nhắm ô XA NHẤT (trong vài ô tới) mà đi thẳng tới được — "cắt góc" để
    // không đi hình bậc thang từng ô một.
    var nham = _tamO(_duongDi.first);
    for (var k = min(_duongDi.length, CauHinh.soONhamTruoc) - 1; k > 0; k--) {
      final ungVien = _tamO(_duongDi[k]);
      if (_diThangDuoc(chan, ungVien)) {
        nham = ungVien;
        break;
      }
    }
    final den = nham - chan;
    return den.length < 0.5 ? null : den;
  }

  /// Hộp chân trượt thẳng từ [tu] tới [den] có chạm vật cản không.
  /// Lấy mẫu mỗi 4 pixel — nhỏ hơn bề rộng hộp chân nên không lọt ô nào.
  bool _diThangDuoc(Vector2 tu, Vector2 den) {
    final doDai = tu.distanceTo(den);
    final soBuoc = max(1, (doDai / 4).ceil());
    final buoc = (den - tu) / soBuoc.toDouble();
    final p = tu.clone();
    for (var i = 0; i < soBuoc; i++) {
      p.add(buoc);
      if (!banDo.diDuoc(p, NhanVat.hopChan)) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------
  // Hành vi
  // ------------------------------------------------------------------

  /// Đuổi theo có né vật cản ở mức đơn giản.
  ///
  /// Đi thẳng tới người chơi trước. Nếu hướng đó bị chặn thì thử trượt theo
  /// trục còn tự do. Đây chưa phải tìm đường A*, nhưng đủ để kẻ địch vòng qua
  /// góc tường thay vì dí mặt vào tường — và quan trọng là đọc hiểu được ngay.
  Vector2 _huongDuoiTheo() {
    final den = viTriNguoiChoi() - position;
    if (den.length < 0.001) return Vector2.zero();

    final chuan = den.normalized();
    final thuTruoc = Vector2(position.x + chuan.x * 6, position.y + chuan.y * 6 + 4);

    if (banDo.diDuoc(thuTruoc, NhanVat.hopChan)) {
      return chuan;
    }

    // Bị chặn: ưu tiên trục có khoảng cách lớn hơn, nếu vẫn chặn thì đi trục kia.
    final thuNgang = Vector2(position.x + chuan.x.sign * 6, position.y + 4);
    final thuDoc = Vector2(position.x, position.y + chuan.y.sign * 6 + 4);

    final ngangDuoc = chuan.x != 0 && banDo.diDuoc(thuNgang, NhanVat.hopChan);
    final docDuoc = chuan.y != 0 && banDo.diDuoc(thuDoc, NhanVat.hopChan);

    if (ngangDuoc && (!docDuoc || den.x.abs() >= den.y.abs())) {
      return Vector2(chuan.x.sign, 0);
    }
    if (docDuoc) {
      return Vector2(0, chuan.y.sign);
    }
    return Vector2.zero();
  }

  Vector2 _huongTuanTraHienTai(double dt) {
    _conLaiTuanTra -= dt;
    if (_conLaiTuanTra <= 0) _doiHuongTuanTra();
    return _huongTuanTra.clone();
  }

  void _doiHuongTuanTra() {
    const cacHuong = [
      [1.0, 0.0],
      [-1.0, 0.0],
      [0.0, 1.0],
      [0.0, -1.0],
    ];
    final h = cacHuong[_rnd.nextInt(cacHuong.length)];
    _huongTuanTra = Vector2(h[0], h[1]);
    _conLaiTuanTra = 0.8 + _rnd.nextDouble() * 1.8;
  }

  // ------------------------------------------------------------------
  /// Kẻ địch lao trúng George thì tự nổ và biến mất.
  void noTung() {
    if (_daNo) return;
    _daNo = true;

    AmThanh.keDichNo();
    parent?.add(HieuUngNoKeDich(position.clone(), mauVunNo));
    removeFromParent();
  }
}
