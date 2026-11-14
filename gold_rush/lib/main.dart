import 'dart:async';

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

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
import 'man_hinh/chon_man.dart';
import 'man_hinh/anh_nhan_vat.dart';
import 'man_hinh/cua_hang.dart';
import 'man_hinh/kho_do.dart';
import 'man_hinh/lop_phu.dart';
import 'components/ui/gold_rush_top_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Toàn màn hình và hướng ngang cho nền tảng hỗ trợ.
  if (!kIsWeb) {
    try {
      await Flame.device.fullScreen();
      await Flame.device.setLandscape();
    } catch (_) {
      // Máy tính để bàn: cửa sổ tự co giãn.
    }
  }

  runApp(const UngDungGoldRush());
}

class UngDungGoldRush extends StatefulWidget {
  const UngDungGoldRush({super.key});

  @override
  State<UngDungGoldRush> createState() => _UngDungGoldRushState();
}

class _UngDungGoldRushState extends State<UngDungGoldRush> {
  late final platform.MetamaskSiweWeb _wallet;
  late final AuthController _auth;

  @override
  void initState() {
    super.initState();
    _wallet = platform.MetamaskSiweWeb();
    _auth = AuthController.web(
      wallet: _wallet,
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
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: AuthGate(
        controller: _auth,
        retainGameDuringSessionCheck: true,
        authenticatedBuilder: (_) => ManHinhGame(auth: _auth, wallet: _wallet),
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
  bool _resumeAfterCheck = false;

  @override
  void initState() {
    super.initState();
    _wallet = platform.createGameWallet(widget.wallet);
    _game = GoldRushGame(vi: _wallet.vi, auth: widget.auth);
    widget.auth.addListener(_lockImmediately);
  }

  void _lockImmediately() {
    if (!widget.auth.canEnterGame) {
      _resumeAfterCheck =
          _resumeAfterCheck ||
          (!_game.paused && widget.auth.status == AuthStatus.checkingSession);
      _game.pauseEngine();
      unawaited(AmThanh.tamDungNhac());
    } else if (_resumeAfterCheck) {
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
    unawaited(AmThanh.dungNhacNen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget<GoldRushGame>(
        game: _game,
        autofocus: true,
        overlayBuilderMap: {
          LopPhu.menu: (_, game) => ManHinhMenu(game: game),
          LopPhu.caiDat: (_, game) => ManHinhCaiDat(game: game),
          LopPhu.tamDung: (_, game) => ManHinhTamDung(game: game),
          LopPhu.ketThuc: (_, game) => ManHinhKetThuc(game: game),
          LopPhu.huyHieu: (_, game) => ManHinhHuyHieu(game: game),
          LopPhu.cuaHang: (_, game) => ManHinhCuaHang(game: game),
          LopPhu.chonMan: (_, game) => ListenableBuilder(
            listenable: game.tienTrinhWorldMap,
            builder: (context, _) => ManHinhChonMan(
              game: game,
              tienTrinh: game.tienTrinhWorldMap.tienTrinh,
              loiLuuTienTrinh: game.tienTrinhWorldMap.loi,
            ),
          ),
          LopPhu.khoDo: (_, game) => _KhoDoTrongGame(game: game),
        },
        loadingBuilder: (_) => const ColoredBox(
          color: CauHinh.mauNen,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: CauHinh.mauChinh),
                SizedBox(height: 16),
                Text(
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
              child: Text(
                'Không nạp được game.\n\n$loi\n\n'
                'Kiểm tra lại phần assets trong pubspec.yaml '
                'và các tệp trong thư mục assets/.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13),
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
  @override
  Widget build(BuildContext context) {
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

    return ManHinhKhoDo(
      khiDong: game.dongKhoDo,
      thanhTren: GoldRushTopBar(
        activeItem: GoldRushTopBarItem.khoDo,
        onSanhCho: game.dongKhoDo,
        onCuaHang: () {
          game.dongKhoDo();
          game.moCuaHang();
        },
        onKhoDo: game.moKhoDo,
        onXuongAi: () {
          game.dongKhoDo();
          unawaited(_moXuongAi());
        },
        onClose: game.dongKhoDo,
      ),
      trangThaiTrangBi: TrangThaiKhoDo.daTai,
      danhSachVatPham: game.danhSachVatPham.value,
      khiTrangBi: game.trangBiVatPham,
      khiThao: game.thaoVatPham,
      trangThaiNhanVat: TrangThaiKhoDo.daTai,
      phienVi: game.phienVi,
      authController: game.auth,
      tepNhanVatDangDung: game.nhanVatDangDung,
      khiChonNhanVat: _chonNhanVat,
      khiMoTaoNhanVat: _moXuongAi,
    );
  }

  Future<void> _moXuongAi() async {
    final game = widget.game;
    final api = MayChuNhanVat();
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ManHinhAnhNhanVat(
            mayChu: api,
            authController: game.auth,
            vi: game.phienVi?.vi,
            tienTrinhController: game.tienTrinh,
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
    setState(() {
      game.nhanVatDangDung = nvDaChon.tepAnh;
    });

    pv?.veLai();
  }
}
