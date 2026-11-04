import 'dart:async';

import 'package:flutter/foundation.dart';

import '../man_choi.dart';
import 'abi.dart';
import 'cua_hang.dart';
import 'giao_dich.dart';
import 'may_chu_phieu.dart';
import 'nhan_vat.dart';
import 'vi.dart';

/// PHIÊN VÍ — một trạng thái duy nhất cho cả màn hình chọn màn, cửa hàng và màn hình kết thúc.
///
/// Trước bản 1.3 mỗi màn hình tự kết nối ví → hai màn hình có thể giữ hai trạng thái khác nhau,
/// và đóng cửa hàng là mất kết nối. Gom về đây thì:
///   * kết nối một lần, mọi lớp phủ cùng thấy (ListenableBuilder);
///   * mọi thao tác chạy qua [_lam]: khoá nút, hiện tiến độ, đổi lỗi thành câu tiếng Việt;
///   * phiếu chờ nhận luôn được đồng bộ từ máy chủ → tải lại trang không mất vàng đã kiếm.
class PhienVi extends ChangeNotifier {
  final Vi vi;
  final MayChuPhieu mayChu;

  PhienVi({required this.vi, required this.mayChu});

  CauHinhChuoi? cauHinh;
  String? diaChi;
  CuaHangChuoi? cuaHang;
  StreamSubscription<SuKienVi>? _ngheVi;

  BigInt vang = BigInt.zero;
  VeVaoMan ve = VeVaoMan.khong;
  final Map<int, BigInt> gia = {};
  final Set<int> daCo = {};

  /// Phiếu đã ký, chưa nộp (đã lọc: còn dùng được).
  List<PhieuCho> phieuCho = const [];

  /// Ván đã chơi xong lúc CHƯA kết nối ví — kết nối xong sẽ xin phiếu.
  final List<String> _vanChuaXinPhieu = [];

  String? thongBao;
  bool thongBaoLaLoi = false;
  bool dangXuLy = false;

  bool get daKetNoi => diaChi != null && cuaHang != null;

  BigInt get vangChoNhan {
    var t = BigInt.zero;
    for (final p in phieuCho) {
      t += p.phieu.soVang + (p.coCoc ? ve.coc : BigInt.zero);
    }
    return t;
  }

  /// Phiếu HOÀN THÀNH của đúng vé đang mở → vé đó đã "xong", vào màn mới không mất cọc.
  bool get veDangMoDaCoPhieu =>
      ve.dangMo && phieuCho.any((p) => p.coCoc && p.phieu.ve == BigInt.from(ve.so));

  void _bao(String s, {bool loi = false}) {
    thongBao = s;
    thongBaoLaLoi = loi;
    notifyListeners();
  }

  /// Chạy một thao tác: khoá nút, hiện tiến độ, đổi mọi lỗi thành dòng thông báo. null = lỗi.
  Future<T?> _lam<T extends Object>(String dangLam, Future<T> Function() viec, {String? xong}) async {
    if (dangXuLy) {
      _bao('Đang xử lý việc trước — đợi một chút.');
      return null;
    }
    dangXuLy = true;
    _bao(dangLam);
    try {
      final kq = await viec();
      dangXuLy = false;
      _bao(xong ?? '');
      return kq;
    } on LoiVi catch (e) {
      dangXuLy = false;
      _bao(e.thongBao, loi: !e.nguoiDungTuChoi);
      if (e.loai == LoaiLoiVi.doiTaiKhoan) _ngatKetNoi();
      return null;
    } catch (e) {
      dangXuLy = false;
      _bao('Lỗi không mong đợi: $e', loi: true);
      return null;
    }
  }

  /// Như [_lam] cho việc không trả giá trị. true = xong.
  Future<bool> _lamViec(String dangLam, Future<void> Function() viec, {String? xong}) async =>
      await _lam<bool>(dangLam, () async {
        await viec();
        return true;
      }, xong: xong) ??
      false;

  // ------------------------------------------------------------------
  // Kết nối
  // ------------------------------------------------------------------
  Future<bool> ketNoi() => _lamViec('Đang kết nối ${vi.ten}…', () async {
        if (!vi.coSan) {
          throw const LoiVi('Chưa thấy MetaMask. Cài tiện ích MetaMask cho trình duyệt rồi tải lại trang.');
        }
        final ch = await mayChu.cauHinh();
        final dc = await vi.ketNoi();
        final bo = BoGiaoDich.choMang(vi: vi, chainId: ch.chainId, hopDong: ch.hopDong);
        await bo.damBaoMang();
        await bo.kiemHopDong();
        cauHinh = ch;
        diaChi = dc;
        cuaHang = CuaHangChuoi(vi: vi, hopDong: ch.hopDong, bo: bo);
        _ngheVi ??= vi.suKien.listen(_khiViDoi);
        await _taiLaiNoi(); // gồm cả xin phiếu cho các ván chơi lúc chưa kết nối
      }, xong: 'Đã kết nối.');

  /// Xin phiếu cho các ván còn treo. Chỉ bỏ ván khỏi danh sách khi xong hoặc bị từ chối DỨT KHOÁT
  /// (409 đã cấp ví khác, 422 không hợp lệ); lỗi mạng, 404 (nhật ký chưa tới), 429 → giữ lại, thử sau.
  /// Thử lại thưa (≥ 30 s một lần) và bỏ ván sau 3 lần máy chủ trả lỗi để máy chủ mất kết nối không làm
  /// mọi thao tác chậm theo.
  Future<void> _xinCacPhieuCon(String dc) async {
    final bayGio = DateTime.now();
    if (_vanChuaXinPhieu.isEmpty ||
        (_lanThuCuoi != null && bayGio.difference(_lanThuCuoi!) < const Duration(seconds: 30))) {
      return;
    }
    _lanThuCuoi = bayGio;
    for (final maVan in List.of(_vanChuaXinPhieu)) {
      try {
        await mayChu.xinPhieu(maVan: maVan, vi: dc);
        _vanChuaXinPhieu.remove(maVan);
        _soLanHong.remove(maVan);
      } on LoiVi catch (e) {
        final lan = (_soLanHong[maVan] ?? 0) + 1;
        _soLanHong[maVan] = lan;
        // Lỗi mạng (ma == null) không tính vào 3 lần: máy chủ tạm sập không được làm mất vàng.
        if (e.ma == 409 || e.ma == 422 || (e.ma != null && lan >= 3)) {
          _vanChuaXinPhieu.remove(maVan);
          _soLanHong.remove(maVan);
        }
      }
    }
  }

  DateTime? _lanThuCuoi;
  final Map<String, int> _soLanHong = {};

  /// Khoá ngắn trong lúc màn hình chọn màn kiểm tra trước và hỏi xác nhận — chặn bấm hai lần
  /// mở hai hộp thoại (lần thứ hai sẽ đốt cọc của ván đang chơi). true = giữ được khoá.
  bool dangHoi = false;

  bool giuCho() {
    if (dangXuLy || dangHoi) return false;
    dangHoi = true;
    notifyListeners();
    return true;
  }

  void thaCho() {
    dangHoi = false;
    notifyListeners();
  }

  void _khiViDoi(SuKienVi s) {
    switch (s) {
      case DoiTaiKhoan(:final taiKhoan):
        if (diaChi != null &&
            (taiKhoan.isEmpty || taiKhoan.first.toLowerCase() != diaChi!.toLowerCase())) {
          _ngatKetNoi();
          _bao('Tài khoản trong ví đã đổi — bấm "Kết nối MetaMask" để tải ví mới.');
        }
      case DoiMang(:final chainId):
        if (cauHinh != null && chainId != cauHinh!.chainId) {
          _bao('Ví vừa chuyển sang mạng $chainId. Game sẽ xin chuyển lại mạng ${cauHinh!.chainId} '
              'ở giao dịch tiếp theo.', loi: true);
        } else if (daKetNoi && !dangXuLy) {
          unawaited(lamMoi());
        }
    }
  }

  /// Yêu cầu các màn hình đang nghe vẽ lại (ví dụ sau khi đổi nhân vật đang dùng).
  void veLai() => notifyListeners();

  void _ngatKetNoi() {
    diaChi = null;
    cuaHang = null;
    phieuCho = const [];
    ve = VeVaoMan.khong;
    vang = BigInt.zero;
    daCo.clear();
    notifyListeners();
  }

  Future<bool> lamMoi() => _lamViec('Đang đọc dữ liệu trên chuỗi…', _taiLaiNoi);

  Future<void> _taiLaiNoi() async {
    final ch = cuaHang!;
    final dc = diaChi!;
    await ch.bo.damBaoMang(); // đọc sai mạng thì mọi con số đều về 0 — xin chuyển mạng trước
    await _xinCacPhieuCon(dc);
    vang = await ch.soVang(dc);
    ve = await ch.veCua(dc);
    for (final nv in bangNhanVat) {
      gia[nv.id] = await ch.gia(nv.id);
      if (await ch.coNhanVat(dc, nv.id)) {
        daCo.add(nv.id);
      } else {
        daCo.remove(nv.id);
      }
    }
    phieuCho = await ch.locPhieuDungDuoc(dc, await mayChu.phieuChoNhan(dc), ve);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Sau mỗi ván
  // ------------------------------------------------------------------
  /// Game gọi khi nhật ký ván đã lên máy chủ. Trả về số vàng của phiếu (null = chưa có phiếu).
  Future<BigInt?> xinPhieuChoVan(String maVan) async {
    final dc = diaChi;
    if (dc == null) {
      if (!_vanChuaXinPhieu.contains(maVan)) _vanChuaXinPhieu.add(maVan);
      notifyListeners();
      return null;
    }
    try {
      final p = await mayChu.xinPhieu(maVan: maVan, vi: dc);
      if (cuaHang != null) {
        // Phiếu MỚI đứng trước: bộ lọc giữ bản đầu tiên của mỗi mã ván → giữ bản hạn mới nhất.
        phieuCho = await cuaHang!.locPhieuDungDuoc(dc, [p, ...phieuCho], ve);
      }
      notifyListeners();
      return p.phieu.soVang;
    } on LoiVi catch (e) {
      // Lỗi tạm thời → nhớ lại, "Làm mới" hoặc lần đọc chuỗi sau sẽ xin tiếp.
      if (e.ma != 409 && e.ma != 422 && !_vanChuaXinPhieu.contains(maVan)) _vanChuaXinPhieu.add(maVan);
      _bao(e.thongBao, loi: true);
      return null;
    } catch (e) {
      if (!_vanChuaXinPhieu.contains(maVan)) _vanChuaXinPhieu.add(maVan);
      _bao('Lỗi khi xin phiếu: $e', loi: true);
      return null;
    }
  }

  /// Hiện một dòng lỗi từ bên ngoài (ví dụ không nạp được bản đồ).
  void baoLoi(String s) => _bao(s, loi: true);

  /// Có vé cùng màn đang mở mà máy chủ chưa ghi nhận ván nào → vào lại màn KHÔNG trừ thêm cọc.
  Future<bool> coTheDungLaiVe(ManChoi m) async {
    if (diaChi == null || !ve.dangMo || ve.man != m.id || veDangMoDaCoPhieu) return false;
    try {
      return !await mayChu.veDaDung(vi: diaChi!, ve: ve.so);
    } catch (_) {
      return false;
    }
  }

  int get soVanChuaXinPhieu => _vanChuaXinPhieu.length;

  // ------------------------------------------------------------------
  // Giao dịch
  // ------------------------------------------------------------------
  Future<bool> nhanTatCa() => _lamViec('Chuẩn bị nhận vàng…', () async {
        await _taiLaiNoi(); // phiếu mới ký lại, hạn mới
        await cuaHang!.thucHien(diaChi: diaChi!, phieu: phieuCho, baoTienDo: _bao);
        await _taiLaiNoi();
      }, xong: 'Đã nhận vàng.');

  Future<bool> mua(NhanVatBan nv) => _lamViec('Chuẩn bị mua ${nv.ten}…', () async {
        await _taiLaiNoi();
        await cuaHang!.thucHien(
          diaChi: diaChi!,
          phieu: phieuCho,
          muaNhanVat: nv.id,
          baoTienDo: _bao,
        );
        await _taiLaiNoi();
      }, xong: 'Đã mua ${nv.ten}.');

  /// Chuẩn bị một màn có cọc: có vé dùng được thì dùng lại, không thì (nhận phiếu chờ +) mua vé
  /// trong MỘT giao dịch, rồi đăng ký bắt đầu với máy chủ. Trả về số vé và giờ THẬT ngay trước khi
  /// đăng ký (máy chủ tính hạn nộp từ lúc nhận yêu cầu); null = chưa vào được.
  Future<({int ve, DateTime luc})?> chuanBiMan(ManChoi m, String maVan) =>
      _lam<({int ve, DateTime luc})>('Chuẩn bị màn ${m.ten}…', () async {
        await _taiLaiNoi();
        final dc = diaChi!;
        if (ve.dangMo && ve.man == m.id && !veDangMoDaCoPhieu) {
          // Vé cùng màn còn mở (ví dụ lần trước mua xong nhưng mất mạng trước khi vào chơi)
          try {
            final luc = DateTime.now();
            await mayChu.batDauMan(maVan: maVan, vi: dc, man: m.id, ve: ve.so);
            return (ve: ve.so, luc: luc);
          } on LoiVi catch (e) {
            if (e.ma != 409) rethrow; // 409: vé đã dùng cho một ván → mua vé mới
          }
        }
        await cuaHang!.thucHien(diaChi: dc, phieu: phieuCho, vaoMan: m.id, baoTienDo: _bao);
        await _taiLaiNoi();
        if (!(ve.dangMo && ve.man == m.id)) {
          throw LoiVi('Chưa thấy vé màn ${m.id} trên chuỗi — bấm "Làm mới" rồi thử lại.');
        }
        _bao('Đăng ký bắt đầu với máy chủ…');
        final luc = DateTime.now();
        await mayChu.batDauMan(maVan: maVan, vi: dc, man: m.id, ve: ve.so);
        return (ve: ve.so, luc: luc);
      });

  @override
  void dispose() {
    _ngheVi?.cancel();
    super.dispose();
  }
}
