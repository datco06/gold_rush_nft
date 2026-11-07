import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'blockchain/nhan_vat.dart';
import 'cau_hinh.dart';
import 'gold_rush_game.dart';
import 'man_hinh/chon_man.dart';
import 'man_hinh/cua_hang.dart';
import 'man_hinh/kho_do.dart';
import 'man_hinh/lop_phu.dart';

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

class UngDungGoldRush extends StatelessWidget {
  const UngDungGoldRush({super.key});

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
      home: const ManHinhGame(),
    );
  }
}

class ManHinhGame extends StatefulWidget {
  const ManHinhGame({super.key});

  @override
  State<ManHinhGame> createState() => _ManHinhGameState();
}

class _ManHinhGameState extends State<ManHinhGame> {
  // Tạo game một lần, không tạo lại trong build.
  late final GoldRushGame _game = GoldRushGame();

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
          LopPhu.cuaHang: (_, game) => ManHinhCuaHang(game: game),
          LopPhu.chonMan: (_, game) => ManHinhChonMan(game: game),
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
    final pv = widget.game.phienVi;

    if (pv == null) return _noiDung();

    return ListenableBuilder(
      listenable: pv,
      builder: (context, _) => _noiDung(),
    );
  }

  Widget _noiDung() {
    final game = widget.game;

    return ManHinhKhoDo(
      khiDong: game.dongKhoDo,

      // Chưa có dữ liệu vật phẩm thật.
      // Không giả rằng người chơi có hoặc không có vật phẩm.
      trangThaiTrangBi: TrangThaiKhoDo.loi,
      loiTrangBi:
          'Chưa kết nối dữ liệu vật phẩm từ '
          'Gameplay và Backend. '
          'Chức năng Trang bị/Tháo hiện được kiểm tra '
          'trong demo riêng.',

      // George luôn có; nhân vật cửa hàng phụ thuộc phiên ví.
      trangThaiNhanVat: TrangThaiKhoDo.daTai,
      phienVi: game.phienVi,
      tepNhanVatDangDung: game.nhanVatDangDung,
      khiChonNhanVat: _chonNhanVat,
    );
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
