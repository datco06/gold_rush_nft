import 'dart:async';

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'cau_hinh.dart';
import 'am_thanh/am_thanh.dart';
import 'auth/app_platform_stub.dart'
    if (dart.library.js_interop) 'auth/app_platform_web.dart'
    as platform;
import 'auth/auth_api_client.dart';
import 'auth/auth_controller.dart';
import 'auth/ui/auth_gate.dart';
import 'blockchain/vi.dart';
import 'gold_rush_game.dart';
import 'man_hinh/chon_man.dart';
import 'man_hinh/cua_hang.dart';
import 'man_hinh/lop_phu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Toàn màn hình và khoá hướng ngang chỉ có ý nghĩa trên điện thoại.
  // Gọi trên máy tính hoặc trình duyệt sẽ ném ngoại lệ, nên phải chặn lại —
  // đây là điểm sách năm 2022 chưa xử lý vì khi đó chỉ nhắm tới Android.
  if (!kIsWeb) {
    try {
      await Flame.device.fullScreen();
      await Flame.device.setLandscape();
    } catch (_) {
      // Máy tính để bàn: bỏ qua, cửa sổ tự co giãn là đủ.
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
    _game = GoldRushGame(vi: _wallet.vi);
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
    _game.phienVi?.dispose();
    _wallet.dispose();
    unawaited(AmThanh.dungNhacNen());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: Text(
          widget.auth.user?.username ?? 'Gold Rush',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(widget.auth.logout()),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('ĐĂNG XUẤT'),
          ),
        ],
      ),
      body: GameWidget<GoldRushGame>(
        game: _game,
        // autofocus để nhận sự kiện bàn phím ngay, không phải bấm vào game trước.
        autofocus: true,
        overlayBuilderMap: {
          LopPhu.menu: (_, game) => ManHinhMenu(game: game),
          LopPhu.caiDat: (_, game) => ManHinhCaiDat(game: game),
          LopPhu.tamDung: (_, game) => ManHinhTamDung(game: game),
          LopPhu.ketThuc: (_, game) => ManHinhKetThuc(game: game),
          LopPhu.cuaHang: (_, game) => ManHinhCuaHang(game: game),
          LopPhu.chonMan: (_, game) => ManHinhChonMan(game: game),
        },
        // Màn hình chờ trong lúc nạp ảnh, âm thanh và bản đồ.
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
        // Nếu nạp hỏng (thiếu tệp .tmx, sai tên ảnh...) thì hiện lỗi ra màn hình
        // thay vì để màn hình đen câm lặng.
        errorBuilder: (_, loi) => ColoredBox(
          color: CauHinh.mauNen,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Không nạp được game.\n\n$loi\n\n'
                'Kiểm tra lại phần assets trong pubspec.yaml và các tệp trong '
                'thư mục assets/.',
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
