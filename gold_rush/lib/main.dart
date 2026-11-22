import 'dart:async';
import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'ngon_ngu/ngon_ngu.dart';

import 'package:flutter/services.dart';

import 'am_thanh/am_thanh.dart';
import 'ai/may_chu_nhan_vat.dart';
import 'auth/app_platform_stub.dart'
    if (dart.library.js_interop) 'auth/app_platform_web.dart'
    as platform;
import 'auth/auth_api_client.dart';
import 'auth/auth_controller.dart';
import 'auth/ui/auth_gate.dart';
import 'blockchain/nhan_vat.dart';
import 'blockchain/vi.dart';
import 'cau_hinh.dart';
import 'gold_rush_game.dart';
import 'dieu_khien/nut_ban.dart';
import 'man_hinh/chon_man.dart';
import 'man_hinh/anh_nhan_vat.dart';
import 'man_hinh/cua_hang.dart';
import 'man_hinh/kho_do.dart';
import 'man_hinh/rung_ruong.dart';
import 'man_hinh/trung_tam_qua_tang.dart';
import 'man_hinh/ho_so_nhan_vat.dart';
import 'man_hinh/lop_phu.dart';
import 'components/ui/gold_rush_top_bar.dart';
import 'world_map/canh_quan_world_map.dart';

class _LopPhuFadeIn extends StatelessWidget {
  const _LopPhuFadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    tween: Tween(begin: 0, end: 1),
    builder: (context, opacity, child) =>
        Opacity(opacity: opacity, child: child),
    child: child,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NgonNgu.chung.chuanBi();

  // Toàn màn hình và hướng ngang cho nền tảng hỗ trợ.
  if (!kIsWeb) {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await Flame.device.fullScreen();
      await Flame.device.setLandscape();
    } catch (_) {
      // Máy tính để bàn: cửa sổ tự co giãn.
    }
  }

  runApp(const UngDungGoldRush());
}

class UngDungGoldRush extends StatefulWidget {
  const UngDungGoldRush({super.key, this.ngonNgu});

  final NgonNgu? ngonNgu;

  @override
  State<UngDungGoldRush> createState() => _UngDungGoldRushState();
}

class _UngDungGoldRushState extends State<UngDungGoldRush> {
  platform.MetamaskSiweWeb? _wallet;
  AuthController? _auth;
  late final NgonNgu _ngonNgu;

  @override
  void initState() {
    super.initState();
    _ngonNgu = widget.ngonNgu ?? NgonNgu.chung;
    unawaited(_ngonNgu.nap());
  }

  /// Reown opens its modal with showDialog and needs a context that can reach
  /// the root Navigator. The State context sits above MaterialApp, so create
  /// the wallet/auth from a Builder under MaterialApp instead.
  void _ensureAuth(BuildContext context) {
    if (_auth != null) return;
    final wallet = platform.createWallet(
      context: context,
      projectId: const String.fromEnvironment('REOWN_PROJECT_ID'),
    );
    _wallet = wallet;
    _auth = AuthController.web(
      wallet: wallet,
      api: AuthApiClient(
        baseUrl: const String.fromEnvironment(
          'GOLD_RUSH_API',
          defaultValue: 'http://localhost:8000',
        ),
      ),
      disposeDependencies: true,
    );
  }

  @override
  void dispose() {
    _auth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PhamViNgonNgu(
      ngonNgu: _ngonNgu,
      child: MaterialApp(
        title: 'Gold Rush',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: CauHinh.mauChinh,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: CauHinh.mauNen,
        ),
        builder: (context, child) => _LandscapeGate(
          child: _KhungTyLeCoDinh(child: child ?? const SizedBox.shrink()),
        ),
        home: Builder(
          builder: (context) {
            _ensureAuth(context);
            final auth = _auth!;
            final wallet = _wallet!;
            return AuthGate(
              controller: auth,
              recheckOnResume: false,
              retainGameDuringSessionCheck: true,
              authenticatedBuilder: (_) =>
                  ManHinhGame(auth: auth, wallet: wallet),
            );
          },
        ),
      ),
    );
  }
}

/// Dựng toàn bộ giao diện trên cùng một khung thiết kế ngang rồi thu phóng
/// đồng nhất theo kích thước thiết bị.
///
/// Các màn hình hiện có vẫn giữ nguyên widget và bố cục bên trong; khung này
/// chỉ ngăn mỗi màn hình tự đổi hình học theo một ngưỡng responsive khác nhau.
/// BoxFit.contain bảo đảm không cắt nội dung khi tỉ lệ màn hình thay đổi.
class _KhungTyLeCoDinh extends StatelessWidget {
  const _KhungTyLeCoDinh({required this.child});

  static const Size _kichThuocThietKe = Size(1280, 720);
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return child;
        }

        // Giữ chiều cao thiết kế làm chuẩn. Với màn hình ngang rộng hơn 16:9,
        // khung logic được nới thêm theo chiều ngang để FittedBox phủ kín
        // toàn màn hình mà không kéo méo hoặc cắt nội dung.
        final scale = math.min(
          width / _kichThuocThietKe.width,
          height / _kichThuocThietKe.height,
        );
        final kichThuocKhung = Size(width / scale, height / scale);
        final mediaQuery = MediaQuery.of(context);
        final safePadding = EdgeInsets.fromLTRB(
          mediaQuery.padding.left / scale,
          mediaQuery.padding.top / scale,
          mediaQuery.padding.right / scale,
          mediaQuery.padding.bottom / scale,
        );

        return ColoredBox(
          color: CauHinh.mauNen,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: SizedBox(
                width: kichThuocKhung.width,
                height: kichThuocKhung.height,
                child: MediaQuery(
                  data: mediaQuery.copyWith(
                    size: kichThuocKhung,
                    padding: safePadding,
                    viewPadding: safePadding,
                    viewInsets: EdgeInsets.fromLTRB(
                      mediaQuery.viewInsets.left / scale,
                      mediaQuery.viewInsets.top / scale,
                      mediaQuery.viewInsets.right / scale,
                      mediaQuery.viewInsets.bottom / scale,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LandscapeGate extends StatelessWidget {
  const _LandscapeGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.shortestSide < 600;
    final isPortrait = size.height > size.width;

    if (!isPhone || !isPortrait) return child;

    return const ColoredBox(
      color: Color(0xFF07121D),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.screen_rotation_alt_rounded,
                  color: Color(0xFFFFD67A),
                  size: 58,
                ),
                SizedBox(height: 16),
                ChuGame(
                  'Vui lòng xoay ngang thiết bị',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFEAF2F8),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                ChuGame(
                  'Gold Rush được tối ưu cho màn hình ngang.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9BB0C0), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ManHinhGame extends StatefulWidget {
  const ManHinhGame({super.key, required this.auth, required this.wallet});

  final AuthController auth;
  final platform.MetamaskSiweWeb wallet;

  @override
  State<ManHinhGame> createState() => _ManHinhGameState();
}

class _ManHinhGameState extends State<ManHinhGame> {
  /// Tạo game MỘT LẦN và giữ trong State.
  ///
  /// Tạo ngay trong build là lỗi kinh điển: mỗi lần widget vẽ lại, một bản
  /// game mới ra đời, toàn bộ tài nguyên nạp lại và ván chơi bị đặt lại từ đầu.
  late final ({Vi vi, void Function() dispose}) _wallet;
  late final GoldRushGame _game;
  late final FocusNode _gameFocusNode;
  bool _resumeAfterCheck = false;

  @override
  void initState() {
    super.initState();
    _wallet = platform.createGameWallet(widget.wallet);
    _game = GoldRushGame(vi: _wallet.vi, auth: widget.auth);
    // Khởi động nạp ảnh World Map ngay khi game tạo, để lúc mở bản đồ
    // phần nền thường đã nằm trong bộ nhớ dùng chung.
    unawaited(TaiNguyenWorldMap.nap().then<void>((_) {}, onError: (_, _) {}));
    _gameFocusNode = FocusNode(debugLabel: 'gold-rush-game');
    widget.auth.addListener(_lockImmediately);
  }

  void _lockImmediately() {
    // Kiểm tra phiên định kỳ là thụ động; không dừng ván đang chạy trong
    // khoảng thời gian chờ /me. Nếu phiên thật sự mất, AuthGate vẫn gỡ game.
    if (widget.auth.status == AuthStatus.checkingSession &&
        _game.trangThai == TrangThaiChoi.dangChoi) {
      return;
    }
    if (!widget.auth.canEnterGame) {
      _resumeAfterCheck =
          _resumeAfterCheck ||
          (!_game.paused && widget.auth.status == AuthStatus.checkingSession);
      _game.pauseEngine();
      unawaited(AmThanh.tamDungNhac());
    } else if (_resumeAfterCheck || _game.trangThai == TrangThaiChoi.dangChoi) {
      _resumeAfterCheck = false;
      _game.resumeEngine();
      unawaited(AmThanh.tiepTucNhac());
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_lockImmediately);
    _game.pauseEngine();
    _game.tienTrinh.dispose();
    _game.huyHieuDaNhan.dispose();
    _game.danhSachVatPham.dispose();
    _game.phienVi?.dispose();
    _wallet.dispose();
    _gameFocusNode.dispose();
    unawaited(AmThanh.dungNhacNen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        onPointerDown: (_) => _gameFocusNode.requestFocus(),
        child: GameWidget<GoldRushGame>(
          game: _game,
          focusNode: _gameFocusNode,
          autofocus: true,
          overlayBuilderMap: {
            LopPhu.menu: (_, game) =>
                _LopPhuFadeIn(child: ManHinhMenu(game: game)),
            LopPhu.caiDat: (_, game) => ManHinhCaiDat(game: game),
            LopPhu.tamDung: (_, game) => ManHinhTamDung(game: game),
            LopPhu.ketThuc: (_, game) => ManHinhKetThuc(game: game),
            LopPhu.huyHieu: (_, game) => ManHinhHuyHieu(game: game),
            LopPhu.cuaHang: (_, game) =>
                _LopPhuFadeIn(child: ManHinhCuaHang(game: game)),
            LopPhu.rungRuong: (_, game) =>
                _LopPhuFadeIn(child: ManHinhRungRuong(game: game)),
            LopPhu.quaTang: (_, game) =>
                _LopPhuFadeIn(child: ManHinhTrungTamQuaTang(game: game)),
            LopPhu.chonMan: (_, game) => ListenableBuilder(
              listenable: game.tienTrinhWorldMap,
              builder: (context, _) => ManHinhChonMan(
                game: game,
                tienTrinh: game.tienTrinhWorldMap.tienTrinh,
                loiLuuTienTrinh: game.tienTrinhWorldMap.loi,
                dangTaiTienTrinh: !game.tienTrinhWorldMap.daTai,
              ),
            ),
            LopPhu.khoDo: (_, game) =>
                _LopPhuFadeIn(child: _KhoDoTrongGame(game: game)),
            LopPhu.nutBan: (_, game) => NutBan(game: game),
          },
          loadingBuilder: (_) => const ColoredBox(
            color: CauHinh.mauNen,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: CauHinh.mauChinh),
                  SizedBox(height: 16),
                  ChuGame(
                    'Đang nạp Gold Rush...',
                    style: TextStyle(color: CauHinh.mauChu),
                  ),
                ],
              ),
            ),
          ),
          errorBuilder: (_, loi) => ColoredBox(
            color: CauHinh.mauNen,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ChuGame(
                  'Không nạp được game.\n\n$loi\n\n'
                  'Kiểm tra lại phần assets trong pubspec.yaml '
                  'và các tệp trong thư mục assets/.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF8A80),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nối Kho đồ với dữ liệu game thật.
///
/// Không tạo phiên ví mới hoặc chèn vật phẩm mẫu.
class _KhoDoTrongGame extends StatefulWidget {
  final GoldRushGame game;

  const _KhoDoTrongGame({required this.game});

  @override
  State<_KhoDoTrongGame> createState() => _KhoDoTrongGameState();
}

class _KhoDoTrongGameState extends State<_KhoDoTrongGame> {
  String? _diaChiDaDongBo;
  bool _dangDongBoNFT = false;
  String? _loiDongBoNFT;

  @override
  void initState() {
    super.initState();
    _dongBoNFTNeuCan();
  }

  void _dongBoNFTNeuCan() {
    final pv = widget.game.phienVi;
    final diaChi = pv?.diaChi?.toLowerCase();
    if (diaChi == null || pv?.cauHinh?.hopDongVatPham == null) {
      if (diaChi == null) _diaChiDaDongBo = null;
      return;
    }
    if (_dangDongBoNFT || _diaChiDaDongBo == diaChi) return;
    _diaChiDaDongBo = diaChi;
    _dangDongBoNFT = true;
    unawaited(() async {
      try {
        await widget.game.dongBoNFTKhoDo(force: true);
        if (mounted) setState(() => _loiDongBoNFT = null);
      } catch (_) {
        if (mounted) {
          setState(() => _loiDongBoNFT = 'Chưa tải được kho đồ. Hãy thử lại.');
        }
      } finally {
        if (mounted) setState(() => _dangDongBoNFT = false);
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    _dongBoNFTNeuCan();
    final game = widget.game;
    final pv = game.phienVi;
    final listenable = pv == null
        ? game.danhSachVatPham
        : Listenable.merge([pv, game.danhSachVatPham]);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _noiDung(),
    );
  }

  Widget _noiDung() {
    final game = widget.game;
    final pv = game.phienVi;
    final dangChoPhienVi =
        game.auth?.canEnterGame == true && !(pv?.daKetNoi ?? false);

    return ManHinhKhoDo(
      khiDong: game.veMenu,
      thanhTren: GoldRushTopBar(
        activeItem: GoldRushTopBarItem.khoDo,
        gold: pv == null ? '0' : (pv.dangXuLy ? '...' : pv.vangKhaDungDinhDang),
        playerName: game.auth?.user?.username ?? 'datco6',
        onPlayerTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CharacterProfileScreen(game: game),
            ),
          );
        },
        onSanhCho: game.veMenu,
        onCuaHang: () {
          game.dongKhoDo();
          game.moCuaHang();
        },
        onRungRuong: () {
          game.dongKhoDo();
          game.moRungRuong();
        },
        onQuaTang: () {
          game.dongKhoDo();
          game.moQuaTang();
        },
        onKhoDo: game.moKhoDo,
        onXuongAi: () {
          game.dongKhoDo();
          unawaited(_moXuongAi());
        },
        onSettings: game.moCaiDat,
        showClose: false,
        onClose: game.veMenu,
      ),
      trangThaiTrangBi: _dangDongBoNFT || dangChoPhienVi
          ? TrangThaiKhoDo.dangTai
          : (_loiDongBoNFT == null ? TrangThaiKhoDo.daTai : TrangThaiKhoDo.loi),
      danhSachVatPham: game.danhSachVatPham.value,
      loiTrangBi: _loiDongBoNFT,
      khiTrangBi: game.trangBiVatPham,
      khiThao: game.thaoVatPham,
      khiHoanDoiNFT: (vatPham, nguoiNhan, soLuong) async {
        await game.chuyenVatPhamNFT(vatPham, nguoiNhan, soLuong);
      },
      layTokenIdNFT: game.tokenIdVatPham,
      khiLamMoiKhoDo: () => game.dongBoNFTKhoDo(force: true),
      trangThaiNhanVat: TrangThaiKhoDo.daTai,
      phienVi: game.phienVi,
      authController: game.auth,
      tepNhanVatDangDung: game.nhanVatDangDung,
      anhNhanVatDangDung: game.taiNguyen.anhNhanVat(game.nhanVatDangDung),
      tenNhanVatDangDung: game.tenNhanVatDangDung,
      khiChonNhanVat: _chonNhanVat,
      khiTrangBiNhanVatAi: (nhanVat, spriteSheet) async {
        await game.trangBiNhanVatAi(
          characterId: nhanVat.characterId,
          tenNhanVat: nhanVat.name,
          spriteSheet: spriteSheet,
        );
        if (mounted) setState(() {});
      },
      khiMoTaoNhanVat: _moXuongAi,
    );
  }

  Future<void> _moXuongAi() async {
    final game = widget.game;
    final api = MayChuNhanVat();
    try {
      await Navigator.of(context).push<bool>(
        PageRouteBuilder<bool>(
          pageBuilder: (aiContext, _, _) => ManHinhAnhNhanVat(
            mayChu: api,
            authController: game.auth,
            vi: game.phienVi?.vi,
            phienVi: game.phienVi,
            tienTrinhController: game.tienTrinh,
            onPlayerTap: () {
              Navigator.of(aiContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => CharacterProfileScreen(game: game),
                ),
              );
            },
            onSanhCho: () {
              Navigator.of(aiContext).pop();
              game.veMenu();
            },
            onCuaHang: () {
              Navigator.of(aiContext).pop();
              game.moCuaHang();
            },
            onRungRuong: () {
              Navigator.of(aiContext).pop();
              game.moRungRuong();
            },
            onQuaTang: () {
              Navigator.of(aiContext).pop();
              game.moQuaTang();
            },
            onKhoDo: () {
              Navigator.of(aiContext).pop();
              game.moKhoDo();
            },
            onSettings: game.moCaiDat,
          ),
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          ),
        ),
      );
    } finally {
      api.dong();
    }
  }

  Future<void> _chonNhanVat(String characterId) async {
    final game = widget.game;
    final pv = game.phienVi;

    if (!game.overlays.isActive(LopPhu.khoDo) ||
        game.trangThai != TrangThaiChoi.tamDung) {
      throw StateError('Không thể chọn nhân vật lúc này.');
    }

    if ((pv?.dangXuLy ?? false) || (pv?.dangHoi ?? false)) {
      throw StateError('Phiên ví đang xử lý thao tác khác.');
    }

    final id = int.tryParse(characterId);
    NhanVatBan? nhanVat;

    if (id == georgeGoc.id) {
      nhanVat = georgeGoc;
    } else {
      for (final nv in bangNhanVat) {
        if (nv.id == id) {
          nhanVat = nv;
          break;
        }
      }
    }

    if (nhanVat == null) {
      throw StateError('Nhân vật không thuộc danh mục hiện tại.');
    }

    final nvDaChon = nhanVat;

    if (nvDaChon.id != georgeGoc.id &&
        (pv == null || !pv.daKetNoi || !pv.daCo.contains(nvDaChon.id))) {
      throw StateError('Chưa xác nhận quyền sở hữu nhân vật.');
    }

    // Dùng cùng trạng thái với cửa hàng hiện có.
    // Ngoại hình được áp dụng khi game dựng ván tiếp theo.
    await game.luuNhanVatDaChon(nvDaChon);
    if (!mounted) return;
    setState(() {});

    pv?.veLai();
  }
}
