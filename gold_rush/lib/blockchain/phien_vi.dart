import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  PhienVi({required this.vi, required this.mayChu}) {
    unawaited(napVangDaLuu());
  }

  String get _khoaVang => diaChi != null && diaChi!.isNotEmpty
      ? 'gold_rush_vang_${diaChi!.toLowerCase()}'
      : 'gold_rush_vang';

  /// Nạp số vàng đã lưu từ bộ nhớ máy.
  Future<void> napVangDaLuu() async {
    try {
      // Chốt key trước khi await: lần nạp cache chung lúc khởi động không
      // được phép ghi đè cache của ví sau khi địa chỉ đã được xác định.
      final khoa = _khoaVang;
      final s = await SharedPreferencesAsync().getString(khoa);
      if (khoa != _khoaVang) return;
      if (s != null) {
        final v = BigInt.tryParse(s);
        if (v != null && v != vang) {
          vang = v;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// Lưu số vàng hiện tại vào bộ nhớ máy.
  Future<void> _luuVang() async {
    try {
      final s = vang.toString();
      await SharedPreferencesAsync().setString(_khoaVang, s);
    } catch (_) {}
  }

  /// Cộng vàng vào ví sau trận đấu, lưu lại và cập nhật toàn bộ giao diện (TopBar).
  Future<void> congVang(BigInt soVangMoi) async {
    if (soVangMoi <= BigInt.zero) return;
    vang += soVangMoi;
    notifyListeners();
    await _luuVang();
  }

  /// Trừ vàng trong ví (ví dụ khi đặt cọc vào màn), lưu lại và thông báo cập nhật TopBar.
  Future<bool> truVang(BigInt soVangTru) async {
    if (soVangTru <= BigInt.zero) return true;
    if (vang < soVangTru) return false;
    vang -= soVangTru;
    notifyListeners();
    await _luuVang();
    return true;
  }

  /// Chuỗi hiển thị số vàng có phân cách hàng nghìn.
  String get vangDinhDang {
    return _dinhDangVang(vang);
  }

  /// Số vàng người chơi có thể dùng ngay trong giao dịch kế tiếp.
  ///
  /// Phiếu thưởng đã ký nhưng chưa claim vẫn được CuaHangChuoi gộp atomically
  /// vào giao dịch mua/nhận/vào màn. Hiển thị riêng [vang] khiến TopBar tạm
  /// nhảy về 0 sau khi thắng dù phần thưởng vẫn còn chờ claim hợp lệ.
  BigInt get vangKhaDung => vang + vangChoNhan;

  String get vangKhaDungDinhDang => _dinhDangVang(vangKhaDung);

  String _dinhDangVang(BigInt soVang) {
    final s = soVang.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buf.write('.');
      }
      buf.write(s[i]);
    }
    return buf.toString();
  }

  CauHinhChuoi? cauHinh;
  String? diaChi;
  CuaHangChuoi? cuaHang;
  StreamSubscription<SuKienVi>? _ngheVi;
  bool _daDong = false;
  bool get daDong => _daDong;

  BigInt vang = BigInt.zero;
  VeVaoMan ve = VeVaoMan.khong;
  final Map<int, BigInt> gia = {};

  /// Giá vật phẩm đọc trực tiếp từ hợp đồng cửa hàng.
  final Map<int, BigInt> giaVatPham = {};
  final Set<int> daCo = {};

  /// Phiếu đã ký, chưa nộp (đã lọc: còn dùng được).
  List<PhieuCho> phieuCho = const [];

  /// Ván đã chơi xong lúc CHƯA kết nối ví — kết nối xong sẽ xin phiếu.
  final List<String> _vanChuaXinPhieu = [];

  String? thongBao;
  bool thongBaoLaLoi = false;
  bool dangXuLy = false;
  Future<bool>? _ketNoiDangChay;
  Future<void>? _napEthNenDangChay;
  String? _diaChiNapEthNenDangChay;
  String? _diaChiDaNapEthNen;
  DateTime? _thoiDiemNapEthNen;

  static final BigInt _nguongNapEthNen = BigInt.from(1000000000000000);

  bool get daKetNoi => diaChi != null && cuaHang != null;

  /// Xin ETH Sepolia sớm khi bắt đầu ván, không chặn giao diện/gameplay.
  ///
  /// Đây chỉ là tối ưu trải nghiệm. Nếu request nền lỗi hoặc chưa kịp mine,
  /// [capEthNeuCan] vẫn giữ nguyên vai trò fallback trước giao dịch.
  Future<void> amThamNapEth() async {
    final dc = diaChi;
    final ch = cauHinh;
    if (_daDong || dc == null || ch == null || ch.chainId != 11155111) {
      return;
    }

    final dcChuanHoa = dc.toLowerCase();
    final dangChay = _napEthNenDangChay;
    if (dangChay != null && _diaChiNapEthNenDangChay == dcChuanHoa) {
      await dangChay;
      return;
    }

    final future = _thucHienNapEthNen(dc);
    _napEthNenDangChay = future;
    _diaChiNapEthNenDangChay = dcChuanHoa;
    try {
      await future;
    } finally {
      if (identical(_napEthNenDangChay, future)) {
        _napEthNenDangChay = null;
        _diaChiNapEthNenDangChay = null;
      }
    }
  }

  Future<void> _thucHienNapEthNen(String dc) async {
    try {
      final daNapGanDay =
          _diaChiDaNapEthNen == dc.toLowerCase() &&
          _thoiDiemNapEthNen != null &&
          DateTime.now().difference(_thoiDiemNapEthNen!) <
              const Duration(minutes: 5);
      if (daNapGanDay || await vi.soDu(dc) >= _nguongNapEthNen) return;

      await mayChu.nhanEthSepolia();
      _diaChiDaNapEthNen = dc.toLowerCase();
      _thoiDiemNapEthNen = DateTime.now();
    } catch (_) {
      // Warm-up là best-effort; không được làm gián đoạn việc bắt đầu ván.
    }
  }

  BigInt get vangChoNhan {
    var t = BigInt.zero;
    for (final p in phieuCho) {
      t += p.phieu.soVang + (p.coCoc ? ve.coc : BigInt.zero);
    }
    return t;
  }

  /// Phiếu HOÀN THÀNH của đúng vé đang mở → vé đó đã "xong", vào màn mới không mất cọc.
  bool get veDangMoDaCoPhieu =>
      ve.dangMo &&
      phieuCho.any((p) => p.coCoc && p.phieu.ve == BigInt.from(ve.so));

  void _bao(String s, {bool loi = false}) {
    if (_daDong) return;
    thongBao = s;
    thongBaoLaLoi = loi;
    notifyListeners();
  }

  /// Chạy một thao tác: khoá nút, hiện tiến độ, đổi mọi lỗi thành dòng thông báo. null = lỗi.
  Future<T?> _lam<T extends Object>(
    String dangLam,
    Future<T> Function() viec, {
    String? xong,
  }) async {
    if (_daDong) return null;
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
      if (!_daDong && e.loai == LoaiLoiVi.doiTaiKhoan) _ngatKetNoi();
      return null;
    } catch (e) {
      dangXuLy = false;
      _bao('Lỗi không mong đợi: $e', loi: true);
      return null;
    }
  }

  /// Như [_lam] cho việc không trả giá trị. true = xong.
  Future<bool> _lamViec(
    String dangLam,
    Future<void> Function() viec, {
    String? xong,
  }) async =>
      await _lam<bool>(dangLam, () async {
        await viec();
        return true;
      }, xong: xong) ??
      false;

  // ------------------------------------------------------------------
  // Kết nối
  // ------------------------------------------------------------------
  Future<bool> _ketNoiMotLan(Future<bool> Function() thaoTac) {
    final dangChay = _ketNoiDangChay;
    if (dangChay != null) return dangChay;
    final future = thaoTac();
    _ketNoiDangChay = future;
    return future.whenComplete(() {
      if (identical(_ketNoiDangChay, future)) _ketNoiDangChay = null;
    });
  }

  Future<bool> ketNoi() => _ketNoiMotLan(
    () => _lamViec('Đang kết nối ${vi.ten}…', () async {
      if (!vi.coSan) {
        throw const LoiVi(
          'Chưa thấy MetaMask. Cài tiện ích MetaMask cho trình duyệt rồi tải lại trang.',
        );
      }
      final ch = await mayChu.cauHinh();
      final dc = await vi.ketNoi();
      final bo = BoGiaoDich.choMang(
        vi: vi,
        chainId: ch.chainId,
        hopDong: ch.hopDong,
        capEthNeuCan: capEthNeuCan,
      );
      await bo.damBaoMang();
      await bo.kiemHopDong();
      cauHinh = ch;
      diaChi = dc;
      await napVangDaLuu();
      cuaHang = CuaHangChuoi(
        vi: vi,
        hopDong: ch.hopDong,
        hopDongVatPham: ch.hopDongVatPham,
        bo: bo,
      );
      if (_daDong) return;
      _ngheVi ??= vi.suKien.listen(_khiViDoi);
      await _taiLaiNoi(); // gồm cả xin phiếu cho các ván chơi lúc chưa kết nối
    }, xong: 'Đã kết nối.'),
  );

  /// Đồng bộ với ví đã được AuthGate kết nối, không gọi eth_requestAccounts
  /// và không mở thêm hộp thoại kết nối trong game.
  Future<bool> ketNoiDaXacThuc(String diaChiAuth) => _ketNoiMotLan(
    () => _lamViec('Đang đồng bộ ví đăng nhập…', () async {
      final ds = await vi.taiKhoan();
      if (ds.isEmpty || ds.first.toLowerCase() != diaChiAuth.toLowerCase()) {
        throw const LoiVi('Ví đăng nhập không còn được cấp quyền cho trang.');
      }
      final ch = await mayChu.cauHinh();
      final bo = BoGiaoDich.choMang(
        vi: vi,
        chainId: ch.chainId,
        hopDong: ch.hopDong,
        capEthNeuCan: capEthNeuCan,
      );
      await bo.damBaoMang();
      await bo.kiemHopDong();
      cauHinh = ch;
      diaChi = ds.first;
      await napVangDaLuu();
      cuaHang = CuaHangChuoi(
        vi: vi,
        hopDong: ch.hopDong,
        hopDongVatPham: ch.hopDongVatPham,
        bo: bo,
      );
      _ngheVi ??= vi.suKien.listen(_khiViDoi);
      await _taiLaiNoi();
    }),
  );

  /// Xin phiếu cho các ván còn treo. Chỉ bỏ ván khỏi danh sách khi xong hoặc bị từ chối DỨT KHOÁT
  /// (409 đã cấp ví khác, 422 không hợp lệ); lỗi mạng, 404 (nhật ký chưa tới), 429 → giữ lại, thử sau.
  /// Thử lại thưa (≥ 30 s một lần) và bỏ ván sau 3 lần máy chủ trả lỗi để máy chủ mất kết nối không làm
  /// mọi thao tác chậm theo.
  Future<void> _xinCacPhieuCon(String dc) async {
    final bayGio = DateTime.now();
    if (_vanChuaXinPhieu.isEmpty ||
        (_lanThuCuoi != null &&
            bayGio.difference(_lanThuCuoi!) < const Duration(seconds: 30))) {
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
        if (e.ma == 409 ||
            e.ma == 422 ||
            (e.ma != null && e.ma != 404 && e.ma != 429 && lan >= 3)) {
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
            (taiKhoan.isEmpty ||
                taiKhoan.first.toLowerCase() != diaChi!.toLowerCase())) {
          _ngatKetNoi();
          _bao(
            'Tài khoản trong ví đã đổi — bấm "Kết nối MetaMask" để tải ví mới.',
          );
        }
      case DoiMang(:final chainId):
        if (cauHinh != null && chainId != cauHinh!.chainId) {
          _bao(
            'Ví vừa chuyển sang mạng $chainId. Game sẽ xin chuyển lại mạng ${cauHinh!.chainId} '
            'ở giao dịch tiếp theo.',
            loi: true,
          );
        } else if (daKetNoi && !dangXuLy) {
          unawaited(lamMoi());
        }
    }
  }

  /// Yêu cầu các màn hình đang nghe vẽ lại (ví dụ sau khi đổi nhân vật đang dùng).
  void veLai() {
    if (!_daDong) notifyListeners();
  }

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
    final vangOnChain = await ch.soVang(dc);
    final veMoi = await ch.veCua(dc);
    final phieuDangCho = phieuCho;
    final phieuMoi = await ch.locPhieuDungDuoc(dc, [
      ...phieuDangCho,
      ...await mayChu.phieuChoNhan(dc),
    ], veMoi);

    // Topbar chỉ hiển thị số dư ERC-1155 đã ghi thật trên hợp đồng. Phiếu
    // thưởng vẫn được giữ riêng để giao dịch nhận vàng/mua vật phẩm có thể
    // gộp vào cùng một transaction, nhưng không được cộng tạm vào topbar.
    ve = veMoi;
    phieuCho = phieuMoi;
    if (vangOnChain != vang) {
      vang = vangOnChain;
      await _luuVang();
      notifyListeners();
    }
    for (final nv in bangNhanVat) {
      gia[nv.id] = await ch.gia(nv.id);
      if (await ch.coNhanVat(dc, nv.id)) {
        daCo.add(nv.id);
      } else {
        daCo.remove(nv.id);
      }
    }
    try {
      final giaVatPhamMoi = await Future.wait(
        List.generate(27, (index) async {
          final tokenId = index + 1;
          return (tokenId: tokenId, gia: await ch.giaVatPham(tokenId));
        }),
      );
      giaVatPham
        ..clear()
        ..addEntries(
          giaVatPhamMoi.map((item) => MapEntry(item.tokenId, item.gia)),
        );
    } catch (_) {
      // Giá tĩnh của FE vẫn là fallback nếu contract cũ chưa hỗ trợ đọc giá.
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Sau mỗi ván
  // ------------------------------------------------------------------
  /// Game gọi khi nhật ký ván đã lên máy chủ. Trả về số vàng của phiếu (null = chưa có phiếu).
  Future<BigInt?> xinPhieuChoVan(String maVan) async {
    if (_daDong) return null;
    final dc = diaChi;
    if (dc == null) {
      if (!_vanChuaXinPhieu.contains(maVan)) _vanChuaXinPhieu.add(maVan);
      _bao(
        'Chưa kết nối ví xác thực; không thể xin phiếu blockchain cho ván này.',
        loi: true,
      );
      return null;
    }
    try {
      final p = await mayChu.xinPhieu(maVan: maVan, vi: dc);
      if (_daDong || diaChi != dc) return null;
      final ch = cuaHang;
      if (ch != null) {
        // Phiếu MỚI đứng trước: bộ lọc giữ bản đầu tiên của mỗi mã ván → giữ bản hạn mới nhất.
        final phieuMoi = await ch.locPhieuDungDuoc(dc, [p, ...phieuCho], ve);
        if (_daDong || diaChi != dc || !identical(cuaHang, ch)) return null;
        phieuCho = phieuMoi;
      }
      notifyListeners();
      return p.phieu.soVang;
    } on LoiVi catch (e) {
      // Lỗi tạm thời → nhớ lại, "Làm mới" hoặc lần đọc chuỗi sau sẽ xin tiếp.
      if (e.ma != 409 && e.ma != 422 && !_vanChuaXinPhieu.contains(maVan)) {
        _vanChuaXinPhieu.add(maVan);
      }
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
    if (diaChi == null || !ve.dangMo || ve.man != m.id || veDangMoDaCoPhieu) {
      return false;
    }
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
  Future<void> _capEthTestNeuCan() async {
    // Hardhat local mô phỏng Paymaster: giao dịch mua/nhận đều có thể cần gas
    // ngay cả khi không còn phiếu chờ (ví dụ mua bằng vàng đã có on-chain).
    // Không phụ thuộc vào phieuCho vì danh sách này có thể đang được đồng bộ
    // lại ở thời điểm nút mua được bấm.
    final dc = diaChi;
    if (dc == null) return;

    // Cấu hình có thể đã được nạp từ trước khi backend bật faucet (hoặc sau
    // hot-reload). Đọc lại ngay trước mutation để không bỏ qua bước cấp ETH.
    final ch = await mayChu.cauHinh();
    cauHinh = ch;
    if (!ch.localFaucet) return;
    await mayChu.nhanEthTest(vi: dc);
    final nguong = BigInt.from(
      1000000000000000,
    ); // 0.001 ETH, lớn hơn phí gas (~0.0001 ETH)
    for (var i = 0; i < 30 && !_daDong; i++) {
      try {
        if (await vi.soDu(dc) >= nguong) return;
      } catch (_) {}
      if (i == 0) _bao('Đang chờ ví nhận ETH test…');
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// Cấp ETH chỉ sau khi BoGiaoDich đã đo được phí và xác nhận số dư thiếu.
  Future<void> capEthNeuCan(String diaChi, BigInt phi) async {
    final ch = cauHinh ?? await mayChu.cauHinh();
    cauHinh = ch;
    if (ch.chainId == 31337) {
      if (!ch.localFaucet) {
        throw const LoiVi(
          'Faucet Hardhat local đang tắt.',
          loai: LoaiLoiVi.thieuEth,
        );
      }
      await mayChu.nhanEthTest(vi: diaChi);
    } else if (ch.chainId == 11155111) {
      final dcChuanHoa = diaChi.toLowerCase();
      final dangChay = _napEthNenDangChay;
      if (dangChay != null && _diaChiNapEthNenDangChay == dcChuanHoa) {
        await dangChay;
      }

      final daNapGanDay =
          _diaChiDaNapEthNen == dcChuanHoa &&
          _thoiDiemNapEthNen != null &&
          DateTime.now().difference(_thoiDiemNapEthNen!) <
              const Duration(minutes: 5);
      if (!daNapGanDay) {
        await mayChu.nhanEthSepolia();
        _diaChiDaNapEthNen = dcChuanHoa;
        _thoiDiemNapEthNen = DateTime.now();
      }
    } else {
      throw const LoiVi(
        'Ví không đủ ETH và mạng hiện tại không có Faucet.',
        loai: LoaiLoiVi.thieuEth,
      );
    }

    // RPC của ví có thể thấy số dư chậm hơn receipt của Backend; chỉ chờ ở
    // nhánh thực sự thiếu ETH, không thêm độ trễ cho ví đã đủ tiền.
    for (var i = 0; i < 30 && !_daDong; i++) {
      if (await vi.soDu(diaChi) >= phi) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw const LoiVi(
      'ETH Faucet đã xác nhận nhưng ví chưa cập nhật số dư.',
      loai: LoaiLoiVi.thieuEth,
    );
  }

  /// Cấp ETH giả của Hardhat trước một giao dịch do dịch vụ khác trong app gửi.
  /// Trên Sepolia/mainnet, backend trả `localFaucet: false` nên đây là no-op.
  Future<void> capEthTest() => _capEthTestNeuCan();

  Future<bool> nhanTatCa() => _lamViec('Chuẩn bị nhận vàng…', () async {
    await _taiLaiNoi(); // phiếu mới ký lại, hạn mới
    final ch = cuaHang!;
    final dc = diaChi!;
    void kiemTraPhien() {
      if (_daDong || !identical(cuaHang, ch) || diaChi != dc) {
        throw const LoiVi(
          'Phiên ví đã kết thúc. Hãy kiểm tra giao dịch trong MetaMask.',
        );
      }
    }

    kiemTraPhien();
    await ch.thucHien(diaChi: dc, phieu: phieuCho, baoTienDo: _bao);
    kiemTraPhien();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await _taiLaiNoi();
      return;
    }

    // Sau khi MetaMask trả về, đọc trạng thái nhận thưởng trên mạng của
    // giao dịch. Để lần mở Cửa hàng tiếp theo tải lại giá và danh mục.
    if (await vi.chainId() != ch.bo.chainId) {
      throw const LoiVi(
        'Đã gửi giao dịch. Hãy trở về đúng mạng để đồng bộ vàng.',
      );
    }
    final soVang = await ch.soVang(dc);
    final veMoi = await ch.veCua(dc);
    final phieuCon = await ch.locPhieuDungDuoc(dc, phieuCho, veMoi);
    kiemTraPhien();
    vang = soVang;
    ve = veMoi;
    phieuCho = phieuCon;
    await _luuVang();
  }, xong: 'Đã nhận vàng.');

  Future<bool> mua(NhanVatBan nv) =>
      _lamViec('Chuẩn bị mua ${nv.ten}…', () async {
        await _taiLaiNoi();
        await cuaHang!.thucHien(
          diaChi: diaChi!,
          phieu: phieuCho,
          muaNhanVat: nv.id,
          baoTienDo: _bao,
        );
        await _taiLaiNoi();
      }, xong: 'Đã mua ${nv.ten}.');

  /// Mua vật phẩm nhiều lần được; mỗi lần thành công NFT ERC-1155 tăng số lượng.
  Future<bool> muaVatPham({
    required int tokenId,
    required String ten,
    int soLuong = 1,
  }) => _lamViec('Chuẩn bị mua $ten ×$soLuong…', () async {
    if (!daKetNoi) {
      throw const LoiVi('Cần kết nối MetaMask để mua vật phẩm.');
    }
    await _taiLaiNoi();
    await cuaHang!.muaVatPham(
      diaChi: diaChi!,
      tokenId: tokenId,
      soLuong: soLuong,
      phieu: phieuCho,
      baoTienDo: _bao,
    );
    await _taiLaiNoi();
    final vangThuc = await cuaHang!.soVang(diaChi!);
    if (vangThuc != vang) {
      vang = vangThuc;
      await _luuVang();
      notifyListeners();
    }
  }, xong: 'Đã mua $ten ×$soLuong.');

  Future<KetQuaMoRuong?> moRuong() => _lam<KetQuaMoRuong>(
    'Đang chuẩn bị mở rương…',
    () async {
      if (!daKetNoi) {
        throw const LoiVi('Cần kết nối MetaMask để mở rương.');
      }
      final vangThuc = await cuaHang!.soVang(diaChi!);
      if (vangThuc < BigInt.from(100)) {
        throw LoiVi('Số dư không đủ: cần 100 vàng, có $vangThuc.');
      }
      final kq = await mayChu.moRuong(vi: diaChi!);
      await cuaHang!.moRuong(diaChi: diaChi!, phieu: kq.phieu, baoTienDo: _bao);
      await _taiLaiNoi();
      return kq;
    },
    xong: 'Mở rương thành công.',
  );

  /// Chuẩn bị một màn có cọc: có vé dùng được thì dùng lại, không thì (nhận phiếu chờ +) mua vé
  /// trong MỘT giao dịch, rồi đăng ký bắt đầu với máy chủ. Trả về số vé và giờ THẬT ngay trước khi
  /// đăng ký (máy chủ tính hạn nộp từ lúc nhận yêu cầu); null = chưa vào được.
  Future<({int ve, DateTime luc})?> chuanBiMan(ManChoi m, String maVan) =>
      _lam<({int ve, DateTime luc})>('Chuẩn bị màn ${m.ten}…', () async {
        if (!daKetNoi) {
          final coc = BigInt.from(m.coc);
          if (vang < coc) {
            throw const LoiVi('Chưa đủ vàng để đặt cọc.');
          }
          await truVang(coc);
          final luc = DateTime.now();
          final dc = diaChi;
          if (dc != null) {
            try {
              await mayChu.batDauMan(maVan: maVan, vi: dc, man: m.id, ve: 0);
            } catch (_) {}
          }
          return (ve: 0, luc: luc);
        }
        await _taiLaiNoi();
        final dc = diaChi!;
        if (ve.dangMo && ve.man == m.id && !veDangMoDaCoPhieu) {
          // Vé cùng màn còn mở (ví dụ lần trước mua xong nhưng mất mạng trước khi vào chơi)
          try {
            final luc = DateTime.now();
            await mayChu.batDauMan(maVan: maVan, vi: dc, man: m.id, ve: ve.so);
            return (ve: ve.so, luc: luc);
          } on LoiVi catch (e) {
            if (e.ma != 409) {
              rethrow; // 409: vé đã dùng cho một ván → mua vé mới
            }
          }
        }
        await cuaHang!.thucHien(
          diaChi: dc,
          phieu: phieuCho,
          vaoMan: m.id,
          baoTienDo: _bao,
        );
        await _taiLaiNoi();
        if (!(ve.dangMo && ve.man == m.id)) {
          throw const LoiVi(
            'Chưa thấy vé màn trên chuỗi — bấm "Làm mới" rồi thử lại.',
          );
        }
        _bao('Đăng ký bắt đầu với máy chủ…');
        final luc = DateTime.now();
        await mayChu.batDauMan(maVan: maVan, vi: dc, man: m.id, ve: ve.so);
        return (ve: ve.so, luc: luc);
      });

  @override
  void dispose() {
    if (_daDong) return;
    _daDong = true;
    _ngheVi?.cancel();
    super.dispose();
  }
}
