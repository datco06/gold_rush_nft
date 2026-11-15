import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/components/ui/gold_rush_top_bar.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../blockchain/vi_gia.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('Cộng vàng vào ví và hiển thị trên TopBar', () {
    test('1. PhienVi congVang cộng đúng số vàng, lưu lại và định dạng phân cách',
        () async {
      final vi = ViGia();
      final mayChu = MayChuPhieu(mayChu: 'http://localhost:8000');
      final pv = PhienVi(vi: vi, mayChu: mayChu);

      expect(pv.vang, BigInt.zero);
      expect(pv.vangDinhDang, '0');

      var daNotify = 0;
      pv.addListener(() => daNotify++);

      // Cộng 24 vàng (ví dụ hoàn thành màn 1 gom 24 xu)
      await pv.congVang(BigInt.from(24));
      expect(pv.vang, BigInt.from(24));
      expect(pv.vangDinhDang, '24');
      expect(daNotify, 1);

      // Cộng tiếp 1500 vàng
      await pv.congVang(BigInt.from(1500));
      expect(pv.vang, BigInt.from(1524));
      expect(pv.vangDinhDang, '1.524');
      expect(daNotify, 2);

      // Tạo phiên ví mới kiểm tra nạp lại từ bộ nhớ đã lưu
      final pvMoi = PhienVi(vi: vi, mayChu: mayChu);
      await pvMoi.napVangDaLuu();
      expect(pvMoi.vang, BigInt.from(1524));
      expect(pvMoi.vangDinhDang, '1.524');
    });

    testWidgets('2. GoldRushTopBar cập nhật hiển thị vàng tương ứng',
        (tester) async {
      final vi = ViGia();
      final mayChu = MayChuPhieu(mayChu: 'http://localhost:8000');
      final pv = PhienVi(vi: vi, mayChu: mayChu);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: pv,
              builder: (context, _) => GoldRushTopBar(
                activeItem: GoldRushTopBarItem.sanhCho,
                gold: pv.vangDinhDang,
                playerName: 'Player1',
                showClose: false,
              ),
            ),
          ),
        ),
      );

      // Ban đầu: 0 vàng
      expect(find.text('0'), findsOneWidget);

      // Thắng trận cộng 80 vàng
      await pv.congVang(BigInt.from(80));
      await tester.pumpAndSettle();

      // TopBar cập nhật ngay lập tức thành 80
      expect(find.text('80'), findsOneWidget);
    });

    test(
        '3. Luồng kết thúc ván thắng gọi _guiVaXinPhieu đúng một lần và cộng vàng vào phienVi',
        () async {
      final game = GoldRushGame();
      final pv = game.phienVi;
      expect(pv, isNotNull);

      final soVangBanDau = pv!.vang;

      // Giả lập kết thúc màn chơi thắng
      const kq = KetQuaVan(
        man: ManChoi(
          id: 1,
          ten: 'Mỏ vàng khởi đầu',
          moTa: 'Màn chơi cơ bản khởi đầu',
          tep: 'assets/tiles/map1.tmx',
          gioiHanGiay: 90,
          heSoKeDich: 1.0,
          coc: 0,
          thuong: 0,
          soXu: 24,
          sao: 1,
        ),
        maVan: 'van-test-001',
        thang: true,
        xu: 24,
      );

      // Gọi _guiVaXinPhieu
      await game.guiVaXinPhieuChoKiemThu(
        nk: {'ma_van': 'van-test-001', 'ket_qua': 'thang'},
        maVan: 'van-test-001',
        kq: kq,
        coPhieu: true,
      );

      // Số vàng phải được cộng thêm 24 xu
      expect(pv.vang, soVangBanDau + BigInt.from(24));
      expect(pv.vangDinhDang, (soVangBanDau + BigInt.from(24)).toString());

      // Đảm bảo cờ bảo vệ đã được bật
      expect(game.daGuiVaXinPhieu, isTrue);
    });
  });
}
