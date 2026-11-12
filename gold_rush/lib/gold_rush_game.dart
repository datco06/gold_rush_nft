import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'ai/dieu_chinh_do_kho.dart';
import 'ai/gui_nhat_ky.dart';
import 'ai/may_chu_tien_trinh.dart';
import 'ai/mo_hinh_do_kho.dart';
import 'ai/nhat_ky_choi.dart';
import 'ai/tien_trinh_controller.dart';
import 'ai/tim_duong.dart';
import 'am_thanh/am_thanh.dart';
import 'auth/auth_controller.dart';
import 'blockchain/may_chu_phieu.dart';
import 'blockchain/nhan_vat.dart';
import 'blockchain/phien_vi.dart';
import 'blockchain/vi.dart';
import 'cau_hinh.dart';
import 'components/ban_do.dart';
import 'components/boss.dart';
import 'components/dan_ban.dart';
import 'components/dong_xu.dart';
import 'components/george.dart';
import 'components/hieu_ung.dart';
import 'components/hud.dart';
import 'components/ke_dich.dart';
import 'components/vat_pham_roi.dart';
import 'dieu_khien/nut_tam_dung.dart';
import 'man_choi.dart';
import 'tai_nguyen.dart';
import 'the_gioi.dart';
import 'world_map/luu_tien_trinh.dart';

/// Tên các lớp phủ giao diện.
class LopPhu {
  LopPhu._();

  static const menu = 'menu';
  static const caiDat = 'caiDat';
  static const tamDung = 'tamDung';
  static const ketThuc = 'ketThuc';
  static const cuaHang = 'cuaHang';
  static const chonMan = 'chonMan';
  static const khoDo = 'khoDo';
}

/// Kết quả ván vừa xong.
class KetQuaVan {
  final ManChoi man;
  final String maVan;
  final bool thang;
  final int xu;
  /// Thống kê chiến đấu chuẩn hóa cho Progress/Backend (`stage_id`, `won`, `boss_defeated`, v.v.).
  final Map<String, Object> thongKe;

  /// Trạng thái phiếu vàng của ván (đang xin / đã có / không có) — cập nhật khi máy chủ trả lời.
  final String? phieu;

  const KetQuaVan({
    required this.man,
    required this.thang,
    required this.xu,
    this.maVan = '',
    this.thongKe = const {},
    this.phieu,
  });

  int get stageId => man.id;

  bool get matCoc => !man.mienPhi && !thang;

  KetQuaVan voiPhieu(String p) => KetQuaVan(
        man: man,
        maVan: maVan,
        thang: thang,
        xu: xu,
        thongKe: thongKe,
        phieu: p,
      );
}

class GoldRushGame extends FlameGame
    with HasCollisionDetection, HasKeyboardHandlerComponents {
  GoldRushGame._(this.theGioi, this._vi, [this.auth, TienTrinhController? tienTrinh, bool? batBoss])
      : _tienTrinhController = tienTrinh,
        coBoss = batBoss ?? CauHinh.batBoss,
        super(world: theGioi);

  factory GoldRushGame({
    Vi? vi,
    AuthController? auth,
    TienTrinhController? tienTrinh,
    bool? batBoss,
  }) =>
      GoldRushGame._(TheGioi(), vi, auth, tienTrinh, batBoss);

  final Vi? _vi;
  final AuthController? auth;
  final TienTrinhController? _tienTrinhController;

  late final TienTrinhController tienTrinh = _tienTrinhController ??
      TienTrinhController(
        mayChu: MayChuTienTrinh(mayChu: GuiNhatKy.mayChu),
        authController: auth,
      );

  final TheGioi theGioi;

  /// Cho phép bật/tắt Boss cho phiên chơi hoặc kiểm thử (mặc định theo `CauHinh.batBoss`).
  bool coBoss;
  final TaiNguyen taiNguyen = TaiNguyen();
  final BoTienTrinhWorldMap tienTrinhWorldMap = BoTienTrinhWorldMap();

  late BanDo banDo;

  List<ManChoi> danhSachMan = const [ManChoi.macDinh];
  ManChoi manHienTai = ManChoi.macDinh;

  int veDangChoi = 0;
  double? giayConLai;
  DateTime? batDauThat;

  final List<Component> _thanhPhanVan = [];
  final Map<String, BanDo> _boNhoBanDo = {};

  static const String phienBanApp = '1.3.0';

  static const String tepMoHinhDoKho = 'assets/models/do_kho_v1.json';

  late TimDuong timDuong;

  final DieuChinhDoKho doKho = DieuChinhDoKho();
  final NhatKyChoi nhatKy = NhatKyChoi();

  bool _vanDangDienRa = false;

  /// Ngoại hình dùng khi dựng ván tiếp theo.
  String nhanVatDangDung = georgeGoc.tepAnh;

  /// Phiên ví dùng chung, không tạo riêng cho từng màn hình.
  late final PhienVi? phienVi = GuiNhatKy.daCauHinh
      ? PhienVi(
          vi: _vi ?? taoViMacDinh(),
          mayChu: MayChuPhieu(
            mayChu: GuiNhatKy.mayChu,
            layCsrfToken: () => auth?.csrfToken,
          ),
        )
      : null;

  final ValueNotifier<KetQuaVan?> ketQuaVan = ValueNotifier(null);

  int _mauTruoc = CauHinh.mauToiDa;
  int _diemTruoc = 0;

  George? george;
  JoystickComponent? joystick;
  Hud? hud;

  /// Boss của ván hiện tại. null = không có Boss (mặc định; chỉ bật bằng
  /// `--dart-define=GOLD_RUSH_BOSS=true`).
  Boss? _boss;

  TrangThaiChoi trangThai = TrangThaiChoi.tamDung;

  int tongSoXu = 0;
  int soXuDaNhat = 0;

  /// Điểm cao nhất trong phiên hiện tại.
  int diemCaoNhat = 0;

  @override
  Color backgroundColor() => CauHinh.mauNen;

  // ------------------------------------------------------------------
  // Nạp tài nguyên
  // ------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    await taiNguyen.nap();
    await AmThanh.napTruoc();

    await _napDanhSachMan();
    await tienTrinhWorldMap.nap(danhSachMan);

    banDo = await _layBanDo(manHienTai.tep);
    theGioi.add(banDo.thanhPhan);

    timDuong = _dungTimDuong();

    await _napMoHinhDoKho();

    theGioi.khiChamVaoBanDo = (viTri) {
      george?.viTriDich = viTri;
    };

    _capNhatZoom();

    hud = Hud(
      layMau: () => george?.mau ?? 0,
      layDiem: () => george?.diem ?? 0,
      layXuConLai: () => tongSoXu - soXuDaNhat,
      layGiayConLai: () => giayConLai,
    );

    camera.viewport.add(hud!);

    joystick = JoystickComponent(
      knob: SpriteComponent(
        sprite: taiNguyen.joystickNum,
        size: Vector2.all(30),
      ),
      background: SpriteComponent(
        sprite: taiNguyen.joystickNen,
        size: Vector2.all(72),
      ),
      margin: const EdgeInsets.only(left: 26, bottom: 26),
      priority: 100,
    );

    camera.viewport.add(joystick!);
    camera.viewport.add(NutTamDung(khiBam: tamDung));

    // Dựng cảnh phía sau Menu.
    _dungVan();
    _anTatCaLopPhu();
    overlays.add(LopPhu.menu);

    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);
  }

  TimDuong _dungTimDuong() => TimDuong(
    soCot: banDo.soCot,
    soHang: banDo.soHang,
    biChan: banDo.luoi.biChanO,
  );
  /// Khởi tạo bộ nhớ bản đồ và trạng thái ván cho kiểm thử đơn vị mà không cần nạp `.tmx` hay âm thanh.
  @visibleForTesting
  void khoiTaoChoKiemThu({
    required BanDo banDoDau,
    Map<String, BanDo>? cacBanDoKhac,
    List<ManChoi>? danhSachMan,
  }) {
    for (final ten in [
      LopPhu.menu,
      LopPhu.caiDat,
      LopPhu.tamDung,
      LopPhu.ketThuc,
      LopPhu.cuaHang,
      LopPhu.chonMan,
    ]) {
      overlays.addEntry(ten, (_, _) => const SizedBox.shrink());
    }
    _boNhoBanDo.clear();
    _boNhoBanDo[banDoDau.tep] = banDoDau;
    if (cacBanDoKhac != null) _boNhoBanDo.addAll(cacBanDoKhac);
    if (danhSachMan != null && danhSachMan.isNotEmpty) {
      this.danhSachMan = danhSachMan;
      manHienTai = danhSachMan.first;
    }
    banDo = banDoDau;
    theGioi.add(banDo.thanhPhan);
    timDuong = _dungTimDuong();
    final ids = (danhSachMan != null && danhSachMan.isNotEmpty)
        ? danhSachMan.map((m) => m.id).toList()
        : [1, 2, 3, 4, 5, 6];
    tienTrinhWorldMap.khoiTaoChoKiemThu(ids);
  }

  Future<void> _napDanhSachMan() async {
    try {
      danhSachMan = ManChoi.docBoManChoi(
        await rootBundle.loadString('assets/tiles/man_choi.json'),
        await rootBundle.loadString('assets/tiles/man_mo_rong.json'),
      );
      manHienTai = danhSachMan.first;
    } catch (e) {
      debugPrint(
        'Không nạp được man_choi.json ($e) '
        '— chỉ có màn mặc định.',
      );
    }
  }

  Future<BanDo> _layBanDo(String tep) async =>
      _boNhoBanDo[tep] ??= await BanDo.nap(tep);

  /// Kiểm tra bản đồ trước khi đặt cọc.
  Future<bool> napTruocBanDo(ManChoi m) async {
    try {
      await _layBanDo(m.tep);
      return true;
    } catch (e) {
      debugPrint('Không nạp được ${m.tep}: $e');
      return false;
    }
  }

  Future<void> _doiBanDo(ManChoi m) async {
    if (banDo.tep == m.tep) return;

    final moi = await _layBanDo(m.tep);

    banDo.thanhPhan.removeFromParent();
    banDo = moi;

    theGioi.add(banDo.thanhPhan);
    timDuong = _dungTimDuong();
  }

  Future<void> _napMoHinhDoKho() async {
    try {
      final chuoi = await rootBundle.loadString(tepMoHinhDoKho);
      doKho.moHinh = MoHinhDoKho.tuJson(
        jsonDecode(chuoi) as Map<String, dynamic>,
      );
      debugPrint('Đã nạp mô hình độ khó ${doKho.moHinh!.phienBan}');
    } catch (e) {
      debugPrint(
        'Không nạp được mô hình độ khó ($e) '
        '— dùng độ khó cố định.',
      );
    }
  }

  @override
  void onMount() {
    super.onMount();
    pauseEngine();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _capNhatZoom();
  }

  void _capNhatZoom() {
    if (size.x <= 0) return;

    final z = size.x / (CauHinh.soONhinThayNgang * CauHinh.kichThuocO);
    camera.viewfinder.zoom = z
        .clamp(CauHinh.zoomToiThieu, CauHinh.zoomToiDa)
        .toDouble();
  }

  // ==================================================================
  // Dựng ván chơi
  // ==================================================================
  Boss? get boss => _boss;

  void _dungVan({String? maVan}) {
    for (final c in _thanhPhanVan) {
      c.removeFromParent();
    }
    _thanhPhanVan.clear();
    // Dọn dẹp mọi đạn, vật phẩm rơi hoặc hiệu ứng nổ động còn sót trong theGioi từ ván trước.
    for (final c in theGioi.children.toList()) {
      if (c is DanBan || c is VatPhamRoi || c is HieuUngNoKeDich || c is HieuUngNhatXu) {
        c.removeFromParent();
      }
    }
    _boss = null;

    soXuDaNhat = 0;
    tongSoXu = 0;

    final diemGeorge = banDo.diemXuatHien.firstWhere(
      (d) => d.ten == 'george',
      orElse: () => DiemXuatHien('george', banDo.kichThuoc / 2),
    );

    george = George(
      banDo: banDo,
      hoatAnh: taiNguyen.georgeTheoTep[nhanVatDangDung] ?? taiNguyen.george,
      viTri: diemGeorge.viTri.clone(),
      khiChiSoDoi: _khiChiSoDoi,
      khiChet: _khiGeorgeChet,
    );

    _them(george!);

    // Đếm số mục tiêu George hạ được (quái và Boss) cho thống kê chiến đấu.
    george!.khiHaMucTieu = (_) => nhatKy.ghiHaKeDich();

    Vector2 viTriNguoiChoi() => george?.position ?? Vector2.zero();

    double heSoTocDo() => doKho.heSoTocDo * manHienTai.heSoKeDich;

    for (final d in banDo.diemXuatHien) {
      switch (d.ten) {
        case 'coin':
          tongSoXu++;
          _them(DongXu(hoatAnh: taiNguyen.dongXu, viTri: d.viTri.clone()));
          break;

        case 'zombie':
          _them(
            KeDich.zombie(
              banDo: banDo,
              hoatAnh: taiNguyen.zombie,
              viTri: d.viTri.clone(),
              viTriNguoiChoi: viTriNguoiChoi,
              timDuong: timDuong,
              heSoTocDo: heSoTocDo,
            ),
          );
          break;

        case 'skeleton':
          _them(
            KeDich.skeleton(
              banDo: banDo,
              hoatAnh: taiNguyen.skeleton,
              viTri: d.viTri.clone(),
              viTriNguoiChoi: viTriNguoiChoi,
              timDuong: timDuong,
              heSoTocDo: heSoTocDo,
            ),
          );
          break;
      }
    }

    // Boss xuất hiện khi bật `coBoss` (mặc định theo --dart-define=GOLD_RUSH_BOSS=true),
    // nên sáu màn gốc không thay đổi. Chưa có điểm 'boss' trong .tmx thì
    // dùng tạm điểm skeleton đầu tiên (chắc chắn đi được), hoặc tâm bản đồ.
    if (coBoss) {
      final diemBoss = banDo.diemXuatHien.firstWhere(
        (d) => d.ten == 'boss',
        orElse: () => banDo.diemXuatHien.firstWhere(
          (d) => d.ten == 'skeleton',
          orElse: () => DiemXuatHien('boss', banDo.kichThuoc / 2),
        ),
      );
      _boss = Boss(
        banDo: banDo,
        hoatAnh: taiNguyen.skeleton,
        viTri: diemBoss.viTri.clone(),
        viTriNguoiChoi: viTriNguoiChoi,
        gayDame: (l) => george?.nhanSatThuong(l),
        khiChet: _khiBossChet,
      );
      _them(_boss!);
    }

    camera.follow(george!, snap: true);

    nhatKy.batDau(tongSoXu, maVanCoSan: maVan);
    giayConLai = manHienTai.gioiHanGiay > 0
        ? manHienTai.gioiHanGiay.toDouble()
        : null;
    doKho.datLai();
    _mauTruoc = george!.mau;
    _diemTruoc = 0;
  }

  void _them(Component c) {
    _thanhPhanVan.add(c);
    theGioi.add(c);
  }

  void _khiChiSoDoi() {
    final g = george;
    if (g == null) return;

    // Ghi nhật ký: điểm tăng = vừa nhặt xu, máu giảm = vừa trúng đòn.
    if (g.diem > _diemTruoc) nhatKy.ghiNhatXu(g.position.x, g.position.y);
    if (g.mau < _mauTruoc) {
      nhatKy.ghiTrungDon(g.position.x, g.position.y);
      nhatKy.satThuongNhan += _mauTruoc - g.mau;
    }
    _diemTruoc = g.diem;
    _mauTruoc = g.mau;

    final nhat = g.diem ~/ CauHinh.diemMoiDongXu;

    if (nhat != soXuDaNhat) {
      soXuDaNhat = nhat;
      _kiemTraThang();
    }
  }

  bool get _bossConSong => _boss != null && _boss!.sucKhoe.conSong;

  /// Thắng khi đủ xu VÀ không còn Boss. Không có Boss thì y hệt luồng cũ.
  void _kiemTraThang() {
    if (trangThai != TrangThaiChoi.dangChoi) return;
    if (tongSoXu > 0 && soXuDaNhat >= tongSoXu && !_bossConSong) {
      _khiThangCuoc();
    }
  }

  void _khiBossChet(Boss b) {
    nhatKy.bossDaHa = true;
    _kiemTraThang();
  }

  void _khiGeorgeChet() {
    trangThai = TrangThaiChoi.thua;
    _ketThucVan();
  }

  void _khiThangCuoc() {
    if (_vanDangDienRa) {
      unawaited(tienTrinhWorldMap.ghiNhanThang(manHienTai.id));
    }
    trangThai = TrangThaiChoi.thang;
    _ketThucVan();
  }

  void _khiHetGio() {
    giayConLai = 0;
    trangThai = TrangThaiChoi.thua;
    _ketThucVan();
  }

  void _ketThucVan() {
    _guiNhatKy(trangThai == TrangThaiChoi.thang ? 'thang' : 'thua');

    diemCaoNhat = max(diemCaoNhat, george?.diem ?? 0);

    _datDieuKhien(false);
    AmThanh.dungNhacNen();
    overlays.add(LopPhu.ketThuc);
    pauseEngine();
  }

  // ------------------------------------------------------------------
  // Vòng lặp
  // ------------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);

    if (trangThai != TrangThaiChoi.dangChoi) return;

    _docJoystick();
    _ghimCameraTrongBanDo();

    final con = giayConLai;

    if (con != null) {
      giayConLai = con - dt;

      if (giayConLai! <= 0) {
        _khiHetGio();
        return;
      }
    }

    final g = george;

    if (g != null && nhatKy.troiThoiGian(dt)) {
      doKho.capNhat(nhatKy.chup(g.mau, CauHinh.mauToiDa));
    }
  }

  void _guiNhatKy(String ketQua) {
    if (!_vanDangDienRa) return;

    _vanDangDienRa = false;

    final g = george;
    if (g != null) nhatKy.chup(g.mau, CauHinh.mauToiDa);

    // Thống kê chiến đấu: chỉ ghi log cục bộ, CHƯA gửi lên máy chủ
    if (g != null) nhatKy.trangBi = g.trangBi.idDangTrang;
    final thangVan = ketQua == 'thang';
    final thongKe = nhatKy.thongKeChienDau(
      stageId: manHienTai.id,
      won: thangVan,
    );
    debugPrint('Chiến đấu: $thongKe');

    final nk = nhatKy.thanhJson(
      ketQua: ketQua,
      diem: g?.diem ?? 0,
      phienBanApp: phienBanApp,
      doKhoThichUng: doKho.batThichUng && doKho.moHinh != null,
      banDo: banDo.tep,
      man: manHienTai.id,
    );
    debugPrint(
      'Ván ${nk['ma_van']}: $ketQua, ${nk['giay']} giây, '
      '${nhatKy.anhChup.length} ảnh chụp, ${nhatKy.suKien.length} sự kiện',
    );
    final maVan = nhatKy.maVan;
    final man = manHienTai;
    final thang = ketQua == 'thang';
    var kq = KetQuaVan(
      man: man,
      maVan: maVan,
      thang: thang,
      xu: nhatKy.soXu,
      thongKe: thongKe,
    );
    final coPhieu =
        !man.chiChoiLocal && (man.mienPhi ? nhatKy.soXu > 0 : thang);
    if (coPhieu && phienVi != null) {
      kq = kq.voiPhieu('Đang gửi ván lên máy chủ trọng tài…');
    }
    ketQuaVan.value = kq;

    if (man.chiChoiLocal || !GuiNhatKy.daCauHinh) return;

    unawaited(_guiVaXinPhieu(nk, maVan, kq, coPhieu));
  }

  Future<void> _guiVaXinPhieu(
    Map<String, Object> nk,
    String maVan,
    KetQuaVan kq,
    bool coPhieu,
  ) async {
    final daGui = await GuiNhatKy.gui(nk);
    final pv = phienVi;

    if (!coPhieu || pv == null) return;

    void datTrangThai(String p) {
      if (!identical(ketQuaVan.value, kq)) return;
      kq = kq.voiPhieu(p);
      ketQuaVan.value = kq;
    }

    if (!daGui) {
      datTrangThai(
        'Không gửi được ván lên máy chủ '
        '— ván này không đổi được thành vàng.',
      );
      return;
    }

    if (!pv.daKetNoi) {
      if (auth?.canEnterGame == true) {
        await pv.ketNoi();
      }
    }
    if (!pv.daKetNoi) {
      await pv.xinPhieuChoVan(maVan); // ghi nhớ, xin khi kết nối ví
      datTrangThai(
        'Kết nối MetaMask (Cửa hàng) '
        'để nhận vàng của ván này.',
      );
      return;
    }

    final soVang = await pv.xinPhieuChoVan(maVan);
    datTrangThai(
      soVang == null
          ? 'Máy chủ không cấp phiếu: ${pv.thongBao ?? ''}'
          : 'Đã có phiếu +$soVang vàng'
                '${kq.man.mienPhi ? '' : ' (+${kq.man.coc} cọc hoàn lại)'} '
                '— nhận ở Cửa hàng hoặc tự gộp vào '
                'giao dịch vào màn tiếp theo.',
    );

    // Ghi nhận tiến trình khi thắng màn:
    if (soVang != null && kq.thang && kq.man.id >= 1 && kq.man.id <= 6) {
      unawaited(
        tienTrinh.xacNhanHoanThanhMan(
          stageId: kq.man.id,
          evidenceType: 'referee_log',
          evidence: maVan,
        ).catchError((Object e, StackTrace s) {
          debugPrint('Lỗi đồng bộ tiến trình màn ${kq.man.id}: $e');
          return false;
        }),
      );
    }
  }

  void _docJoystick() {
    final j = joystick;
    final g = george;

    if (j == null || g == null) return;

    if (j.direction == JoystickDirection.idle) {
      g.huongJoystick.setZero();
    } else {
      g.huongJoystick.setFrom(j.relativeDelta);
    }
  }

  void _ghimCameraTrongBanDo() {
    if (!hasLayout) return;
    final zoom = camera.viewfinder.zoom;
    if (zoom <= 0) return;

    final nuaW = size.x / (2 * zoom);
    final nuaH = size.y / (2 * zoom);
    final bd = banDo.kichThuoc;
    final vf = camera.viewfinder;

    if (bd.x <= nuaW * 2) {
      vf.position.x = bd.x / 2;
    } else {
      vf.position.x = vf.position.x.clamp(nuaW, bd.x - nuaW);
    }

    if (bd.y <= nuaH * 2) {
      vf.position.y = bd.y / 2;
    } else {
      vf.position.y = vf.position.y.clamp(nuaH, bd.y - nuaH);
    }
  }

  // ------------------------------------------------------------------
  // Điều hướng
  // ------------------------------------------------------------------

  void _datDieuKhien(bool bat) {
    theGioi.nhanCham = bat;
    george?.dieuKhienDuoc = bat;

    if (!bat) george?.viTriDich = null;
  }

  void _anTatCaLopPhu() {
    overlays.remove(LopPhu.menu);
    overlays.remove(LopPhu.caiDat);
    overlays.remove(LopPhu.tamDung);
    overlays.remove(LopPhu.ketThuc);
    overlays.remove(LopPhu.cuaHang);
    overlays.remove(LopPhu.chonMan);
    overlays.remove(LopPhu.khoDo);
  }

  /// Chơi màn [m]. Màn có cọc: [maVan] và [ve] đã đăng ký với máy chủ (PhienVi.chuanBiMan).
  /// false = không nạp được bản đồ hoặc màn chưa được mở khóa (màn đang chơi giữ nguyên).
  Future<bool> choiMan(
    ManChoi m, {
    String? maVan,
    int ve = 0,
    DateTime? batDauThat,
  }) async {
    if (!tienTrinhWorldMap.duocChoi(m.id)) return false;
    try {
      await _doiBanDo(
        m,
      ); // đổi bản đồ TRƯỚC, rồi mới đổi màn — hai thứ luôn khớp nhau
    } catch (e) {
      debugPrint('Không đổi được bản đồ ${m.tep}: $e');
      return false;
    }

    manHienTai = m;
    veDangChoi = ve;

    this.batDauThat = maVan == null ? null : (batDauThat ?? DateTime.now());

    batDauVanMoi(maVan: maVan);
    return true;
  }

  void batDauVanMoi({String? maVan}) {
    if (!tienTrinhWorldMap.duocChoi(manHienTai.id)) {
      moChonMan();
      return;
    }
    if (!manHienTai.mienPhi && maVan == null) {
      moChonMan();
      return;
    }

    ketQuaVan.value = null;

    _dungVan(maVan: maVan);
    _vanDangDienRa = true;

    _anTatCaLopPhu();

    trangThai = TrangThaiChoi.dangChoi;
    _datDieuKhien(true);

    resumeEngine();
    AmThanh.batNhacNen();
  }

  void tamDung() {
    if (trangThai != TrangThaiChoi.dangChoi) return;

    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);

    george?.huongJoystick.setZero();

    AmThanh.tamDungNhac();
    overlays.add(LopPhu.tamDung);
    pauseEngine();
  }

  void tiepTuc() {
    if (trangThai != TrangThaiChoi.tamDung) return;

    overlays.remove(LopPhu.tamDung);
    trangThai = TrangThaiChoi.dangChoi;

    _datDieuKhien(true);
    AmThanh.tiepTucNhac();
    resumeEngine();
  }

  void veMenu() {
    _guiNhatKy('bo');

    _anTatCaLopPhu();
    overlays.add(LopPhu.menu);

    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);

    AmThanh.dungNhacNen();
    _dungVan();
    pauseEngine();
  }

  void moCuaHang() => overlays.add(LopPhu.cuaHang);

  void dongCuaHang() => overlays.remove(LopPhu.cuaHang);

  void moChonMan() => overlays.add(LopPhu.chonMan);

  void dongChonMan() => overlays.remove(LopPhu.chonMan);

  void moCaiDat() => overlays.add(LopPhu.caiDat);

  void dongCaiDat() => overlays.remove(LopPhu.caiDat);

  /// Kho đồ chỉ mở từ Menu, không mở giữa ván.
  void moKhoDo() {
    if (trangThai != TrangThaiChoi.tamDung || !overlays.isActive(LopPhu.menu)) {
      return;
    }

    overlays.add(LopPhu.khoDo);
  }

  /// Menu ở bên dưới nên đóng Kho đồ sẽ trở lại Menu.
  void dongKhoDo() {
    overlays.remove(LopPhu.khoDo);
  }
}