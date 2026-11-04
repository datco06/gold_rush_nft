import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'ai/dieu_chinh_do_kho.dart';
import 'ai/gui_nhat_ky.dart';
import 'ai/mo_hinh_do_kho.dart';
import 'ai/nhat_ky_choi.dart';
import 'ai/tim_duong.dart';
import 'am_thanh/am_thanh.dart';
import 'blockchain/may_chu_phieu.dart';
import 'blockchain/nhan_vat.dart';
import 'blockchain/phien_vi.dart';
import 'blockchain/vi.dart';
import 'cau_hinh.dart';
import 'components/ban_do.dart';
import 'components/dong_xu.dart';
import 'components/george.dart';
import 'components/hud.dart';
import 'components/ke_dich.dart';
import 'dieu_khien/nut_tam_dung.dart';
import 'man_choi.dart';
import 'tai_nguyen.dart';
import 'the_gioi.dart';

/// Tên các lớp phủ giao diện. Dùng hằng số thay vì gõ chuỗi khắp nơi để
/// gõ sai một chữ không biến thành lỗi chạy mới phát hiện được.
class LopPhu {
  LopPhu._();
  static const menu = 'menu';
  static const caiDat = 'caiDat';
  static const tamDung = 'tamDung';
  static const ketThuc = 'ketThuc';
  static const cuaHang = 'cuaHang';
  static const chonMan = 'chonMan';
}

/// Kết quả ván vừa xong — màn hình kết thúc đọc để nói rõ: được bao nhiêu, mất cọc hay không.
class KetQuaVan {
  final ManChoi man;
  final bool thang;
  final int xu;

  /// Trạng thái phiếu vàng của ván (đang xin / đã có / không có) — cập nhật khi máy chủ trả lời.
  final String? phieu;

  const KetQuaVan({required this.man, required this.thang, required this.xu, this.phieu});

  /// Màn có cọc mà không hoàn thành → mất cọc.
  bool get matCoc => !man.mienPhi && !thang;

  KetQuaVan voiPhieu(String p) => KetQuaVan(man: man, thang: thang, xu: xu, phieu: p);
}

class GoldRushGame extends FlameGame
    with HasCollisionDetection, HasKeyboardHandlerComponents {
  GoldRushGame._(this.theGioi) : super(world: theGioi);

  factory GoldRushGame() => GoldRushGame._(TheGioi());

  final TheGioi theGioi;

  final TaiNguyen taiNguyen = TaiNguyen();

  /// Bản đồ của màn đang chơi — đổi khi chọn màn khác (vì vậy không `final`).
  late BanDo banDo;

  // ---------- Màn chơi (assets/tiles/man_choi.json) ----------
  List<ManChoi> danhSachMan = const [ManChoi.macDinh];
  ManChoi manHienTai = ManChoi.macDinh;

  /// Số vé (hợp đồng) của ván màn có cọc đang chơi; 0 = màn luyện tập.
  int veDangChoi = 0;

  /// Đồng hồ đếm ngược; null = màn không giới hạn thời gian.
  double? giayConLai;

  /// Giờ THẬT lúc bắt đầu ván màn có cọc. Máy chủ đối chiếu đồng hồ thật (tính cả lúc tạm dừng):
  /// nhật ký phải tới trong [ManChoi.hanNopNhatKy] kể từ lúc này.
  DateTime? batDauThat;

  /// George, kẻ địch, đồng xu của ván hiện tại. Giữ danh sách riêng thay vì lọc `children`:
  /// component vừa `add` còn nằm trong hàng đợi tới khung hình sau, chưa có trong `children`.
  final List<Component> _thanhPhanVan = [];

  /// Bản đồ đã nạp, theo tên tệp — đổi qua lại giữa các màn không phải đọc lại tệp .tmx.
  final Map<String, BanDo> _boNhoBanDo = {};

  // ---------- Phần AI (thư mục lib/ai/) ----------
  /// Phiên bản app ghi vào nhật ký — khớp `version` trong pubspec.yaml.
  static const String phienBanApp = '1.3.0';

  /// Tệp mô hình độ khó trong assets. Đổi phiên bản mô hình = đổi dòng này
  /// (và khai báo tệp mới trong pubspec nếu đặt ở thư mục khác).
  static const String tepMoHinhDoKho = 'assets/models/do_kho_v1.json';

  /// Bộ tìm đường A* dùng chung cho mọi kẻ địch, dựng lại mỗi khi đổi bản đồ.
  late TimDuong timDuong;

  /// Bộ điều chỉnh độ khó; tự về độ khó cố định nếu không nạp được mô hình.
  final DieuChinhDoKho doKho = DieuChinhDoKho();

  /// Nhật ký ván đang chơi: nguồn đặc trưng cho mô hình và dữ liệu gửi máy chủ.
  final NhatKyChoi nhatKy = NhatKyChoi();

  bool _vanDangDienRa = false;

  // ---------- Cửa hàng nhân vật (lib/blockchain/) ----------
  /// Sprite George đang dùng — đổi trong cửa hàng, áp dụng từ ván sau.
  String nhanVatDangDung = georgeGoc.tepAnh;

  /// Phiên ví dùng chung cho chọn màn, cửa hàng, màn kết thúc. null = chưa cấu hình máy chủ
  /// (`--dart-define=GOLD_RUSH_API=...`) → chỉ chơi được màn luyện tập, như bản gốc.
  late final PhienVi? phienVi = GuiNhatKy.daCauHinh
      ? PhienVi(vi: taoViMacDinh(), mayChu: MayChuPhieu(mayChu: GuiNhatKy.mayChu))
      : null;

  /// Kết quả ván vừa xong. ValueNotifier vì máy chủ trả lời KHÔNG ĐỒNG BỘ: màn kết thúc đang mở
  /// phải tự cập nhật "đã có phiếu +X vàng" khi máy chủ ký xong.
  final ValueNotifier<KetQuaVan?> ketQuaVan = ValueNotifier(null);
  int _mauTruoc = CauHinh.mauToiDa;
  int _diemTruoc = 0;

  George? george;
  JoystickComponent? joystick;
  Hud? hud;

  TrangThaiChoi trangThai = TrangThaiChoi.tamDung;

  int tongSoXu = 0;
  int soXuDaNhat = 0;

  /// Điểm cao nhất trong phiên chạy hiện tại (không lưu xuống đĩa cho gọn;
  /// muốn lưu lâu dài thì dùng shared_preferences như đã học ở Tuần 11).
  int diemCaoNhat = 0;

  @override
  Color backgroundColor() => CauHinh.mauNen;

  // ==================================================================
  // Nạp
  // ==================================================================
  @override
  Future<void> onLoad() async {
    await taiNguyen.nap();
    await AmThanh.napTruoc();

    await _napDanhSachMan();
    banDo = await _layBanDo(manHienTai.tep);
    theGioi.add(banDo.thanhPhan);
    timDuong = _dungTimDuong();
    await _napMoHinhDoKho();

    theGioi.khiChamVaoBanDo = (viTri) {
      george?.viTriDich = viTri;
    };

    _capNhatZoom();

    // HUD và cần điều khiển nằm trong viewport -> không trôi theo bản đồ.
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

    // Dựng sẵn một ván để phía sau lớp phủ menu có cảnh chứ không phải màn đen.
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

  /// Nạp danh sách màn. Hỏng tệp → chỉ còn màn mặc định (bản đồ gốc), game vẫn chạy.
  Future<void> _napDanhSachMan() async {
    try {
      danhSachMan = ManChoi.docDanhSach(await rootBundle.loadString('assets/tiles/man_choi.json'));
      manHienTai = danhSachMan.first;
    } catch (e) {
      debugPrint('Không nạp được man_choi.json ($e) — chỉ có màn mặc định.');
    }
  }

  Future<BanDo> _layBanDo(String tep) async =>
      _boNhoBanDo[tep] ??= await BanDo.nap(tep);

  /// Nạp sẵn bản đồ của màn [m] — gọi TRƯỚC khi đặt cọc: tệp hỏng thì dừng khi chưa mất gì.
  Future<bool> napTruocBanDo(ManChoi m) async {
    try {
      await _layBanDo(m.tep);
      return true;
    } catch (e) {
      debugPrint('Không nạp được ${m.tep}: $e');
      return false;
    }
  }

  /// Đổi sang bản đồ của màn [m] (nếu khác bản đồ đang hiển thị).
  Future<void> _doiBanDo(ManChoi m) async {
    if (banDo.tep == m.tep) return;
    final moi = await _layBanDo(m.tep);
    banDo.thanhPhan.removeFromParent();
    banDo = moi;
    theGioi.add(banDo.thanhPhan);
    timDuong = _dungTimDuong();
  }

  /// Nạp mô hình độ khó từ assets. Thiếu tệp hay tệp sai định dạng thì CHỈ
  /// ghi log và chơi với độ khó cố định — AI hỏng không được làm hỏng game.
  Future<void> _napMoHinhDoKho() async {
    try {
      final chuoi = await rootBundle.loadString(tepMoHinhDoKho);
      doKho.moHinh =
          MoHinhDoKho.tuJson(jsonDecode(chuoi) as Map<String, dynamic>);
      debugPrint('Đã nạp mô hình độ khó ${doKho.moHinh!.phienBan}');
    } catch (e) {
      debugPrint('Không nạp được mô hình độ khó ($e) — dùng độ khó cố định.');
    }
  }

  /// Dừng vòng lặp NGAY SAU khi nạp xong, không dừng ngay trong onLoad.
  ///
  /// onLoad chạy lúc component đang được gắn vào cây; đụng vào trạng thái
  /// chạy/dừng của cả game ngay tại đó là can thiệp vào giữa chừng một quy
  /// trình chưa kết thúc. onMount chạy sau khi mọi thứ đã yên vị.
  @override
  void onMount() {
    super.onMount();
    pauseEngine();
  }

  @override
  void onGameResize(Vector2 kichThuoc) {
    super.onGameResize(kichThuoc);
    if (isLoaded) _capNhatZoom();
  }

  /// Giữ cho người chơi luôn nhìn thấy đúng chừng ấy ô, dù màn hình to hay nhỏ.
  ///
  /// Đây là lời giải cho bài toán của Chương 8: điện thoại, trình duyệt và máy
  /// tính để bàn có độ phân giải rất khác nhau. Nếu vẽ theo pixel màn hình thì
  /// trên máy tính người chơi nhìn thấy nửa bản đồ, còn trên điện thoại thì chỉ
  /// thấy vài ô — hai trải nghiệm hoàn toàn khác nhau.
  void _capNhatZoom() {
    if (size.x <= 0) return;
    final z = size.x / (CauHinh.soONhinThayNgang * CauHinh.kichThuocO);
    camera.viewfinder.zoom =
        z.clamp(CauHinh.zoomToiThieu, CauHinh.zoomToiDa).toDouble();
  }

  // ==================================================================
  // Dựng ván chơi
  // ==================================================================
  void _dungVan({String? maVan}) {
    // Xoá sạch nhân vật của ván trước (kể cả những cái còn trong hàng đợi thêm), giữ lại bản đồ.
    for (final c in _thanhPhanVan) {
      c.removeFromParent();
    }
    _thanhPhanVan.clear();

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

    Vector2 viTriNguoiChoi() => george?.position ?? Vector2.zero();
    // AI độ khó × hệ số của màn (màn càng sau kẻ địch càng nhanh)
    double heSoTocDo() => doKho.heSoTocDo * manHienTai.heSoKeDich;

    for (final d in banDo.diemXuatHien) {
      switch (d.ten) {
        case 'coin':
          tongSoXu++;
          _them(DongXu(
            hoatAnh: taiNguyen.dongXu,
            viTri: d.viTri.clone(),
          ));
          break;
        case 'zombie':
          _them(KeDich.zombie(
            banDo: banDo,
            hoatAnh: taiNguyen.zombie,
            viTri: d.viTri.clone(),
            viTriNguoiChoi: viTriNguoiChoi,
            timDuong: timDuong,
            heSoTocDo: heSoTocDo,
          ));
          break;
        case 'skeleton':
          _them(KeDich.skeleton(
            banDo: banDo,
            hoatAnh: taiNguyen.skeleton,
            viTri: d.viTri.clone(),
            viTriNguoiChoi: viTriNguoiChoi,
            timDuong: timDuong,
            heSoTocDo: heSoTocDo,
          ));
          break;
      }
    }

    camera.follow(george!, snap: true);

    nhatKy.batDau(tongSoXu, maVanCoSan: maVan);
    giayConLai = manHienTai.gioiHanGiay > 0 ? manHienTai.gioiHanGiay.toDouble() : null;
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
    if (g.mau < _mauTruoc) nhatKy.ghiTrungDon(g.position.x, g.position.y);
    _diemTruoc = g.diem;
    _mauTruoc = g.mau;

    final nhat = g.diem ~/ CauHinh.diemMoiDongXu;
    if (nhat != soXuDaNhat) {
      soXuDaNhat = nhat;
      if (soXuDaNhat >= tongSoXu && tongSoXu > 0) {
        _khiThangCuoc();
      }
    }
  }

  void _khiGeorgeChet() {
    trangThai = TrangThaiChoi.thua;
    _ketThucVan();
  }

  void _khiThangCuoc() {
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

  // ==================================================================
  // Vòng lặp
  // ==================================================================
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

    // Mỗi 10 giây: chụp đặc trưng → mô hình dự đoán → chỉnh tốc độ kẻ địch.
    final g = george;
    if (g != null && nhatKy.troiThoiGian(dt)) {
      doKho.capNhat(nhatKy.chup(g.mau, CauHinh.mauToiDa));
    }
  }

  /// Đóng nhật ký ván và gửi về máy chủ (nếu đã cấu hình GOLD_RUSH_API).
  /// Không `await`: gửi chạy nền, màn hình kết thúc hiện ra ngay.
  void _guiNhatKy(String ketQua) {
    if (!_vanDangDienRa) return;
    _vanDangDienRa = false;
    final g = george;
    if (g != null) nhatKy.chup(g.mau, CauHinh.mauToiDa);
    final nk = nhatKy.thanhJson(
      ketQua: ketQua,
      diem: g?.diem ?? 0,
      phienBanApp: phienBanApp,
      doKhoThichUng: doKho.batThichUng && doKho.moHinh != null,
      banDo: banDo.tep, // bản đồ THỰC SỰ đã chơi
      man: manHienTai.id,
    );
    debugPrint('Ván ${nk['ma_van']}: $ketQua, ${nk['giay']} giây, '
        '${nhatKy.anhChup.length} ảnh chụp, ${nhatKy.suKien.length} sự kiện');
    // Chụp lại NGAY: lúc máy chủ trả lời, người chơi có thể đã sang ván mới.
    final maVan = nhatKy.maVan;
    final man = manHienTai;
    final thang = ketQua == 'thang';
    var kq = KetQuaVan(man: man, thang: thang, xu: nhatKy.soXu);
    // Có phiếu khi: màn luyện tập nhặt được xu, hoặc màn có cọc HOÀN THÀNH.
    final coPhieu = man.mienPhi ? nhatKy.soXu > 0 : thang;
    if (coPhieu && phienVi != null) kq = kq.voiPhieu('Đang gửi ván lên máy chủ trọng tài…');
    ketQuaVan.value = kq;
    if (!GuiNhatKy.daCauHinh) return;
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
      if (!identical(ketQuaVan.value, kq)) return; // người chơi đã sang ván khác
      kq = kq.voiPhieu(p);
      ketQuaVan.value = kq;
    }

    if (!daGui) {
      datTrangThai('Không gửi được ván lên máy chủ — ván này không đổi được thành vàng.');
      return;
    }
    if (!pv.daKetNoi) {
      await pv.xinPhieuChoVan(maVan); // ghi nhớ, xin khi kết nối ví
      datTrangThai('Kết nối MetaMask (Cửa hàng) để nhận vàng của ván này.');
      return;
    }
    final soVang = await pv.xinPhieuChoVan(maVan);
    datTrangThai(soVang == null
        ? 'Máy chủ không cấp phiếu: ${pv.thongBao ?? ''}'
        : 'Đã có phiếu +$soVang vàng${kq.man.mienPhi ? '' : ' (+${kq.man.coc} cọc hoàn lại)'} '
            '— nhận ở Cửa hàng hoặc tự gộp vào giao dịch vào màn tiếp theo.');
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

  /// Không cho camera nhìn ra ngoài rìa bản đồ.
  ///
  /// Gọi SAU super.update, vì hành vi `follow` của camera chạy trong lượt cập
  /// nhật của các component con — chặn trước thì bị ghi đè ngay sau đó.
  ///
  /// Bản đồ hẹp hơn màn hình theo trục nào thì canh giữa theo trục đó, nếu
  /// không sẽ thấy viền đen lệch hẳn về một bên.
  void _ghimCameraTrongBanDo() {
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

  // ==================================================================
  // Điều hướng màn hình
  // ==================================================================
  /// Bật/tắt cùng lúc cả hai kênh điều khiển: chạm màn hình và bàn phím.
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
  }

  /// Chơi màn [m]. Màn có cọc: [maVan] và [ve] đã đăng ký với máy chủ (PhienVi.chuanBiMan).
  /// false = không nạp được bản đồ (màn đang chơi giữ nguyên).
  Future<bool> choiMan(ManChoi m, {String? maVan, int ve = 0, DateTime? batDauThat}) async {
    try {
      await _doiBanDo(m); // đổi bản đồ TRƯỚC, rồi mới đổi màn — hai thứ luôn khớp nhau
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

  /// Bắt đầu ván mới (cùng màn). Màn có cọc KHÔNG chơi lại được bằng nút này — phải mua vé mới.
  void batDauVanMoi({String? maVan}) {
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
    // Bật nhạc NGAY SAU thao tác chạm của người dùng — trình duyệt chỉ cho
    // phát âm thanh sau cử chỉ đầu tiên.
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
    _guiNhatKy('bo'); // rời ván giữa chừng (không làm gì nếu ván đã kết thúc)
    _anTatCaLopPhu();
    overlays.add(LopPhu.menu);
    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);
    AmThanh.dungNhacNen();
    _dungVan();
    pauseEngine();
  }

  void moCuaHang() => overlays.add(LopPhu.cuaHang);

  void moChonMan() => overlays.add(LopPhu.chonMan);

  void dongChonMan() => overlays.remove(LopPhu.chonMan);

  void dongCuaHang() => overlays.remove(LopPhu.cuaHang);

  void moCaiDat() {
    overlays.add(LopPhu.caiDat);
  }

  void dongCaiDat() {
    overlays.remove(LopPhu.caiDat);
  }
}
