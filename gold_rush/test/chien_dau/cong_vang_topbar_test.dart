// The test uses the platform interface to install an in-memory preferences
// backend; keep it test-only without adding a production dependency.
// ignore_for_file: depend_on_referenced_packages

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
    test(
      '1. PhienVi congVang cộng đúng số vàng, lưu lại và định dạng phân cách',
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
      },
    );

    testWidgets('2. GoldRushTopBar cập nhật hiển thị vàng tương ứng', (
      tester,
    ) async {
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

    test('3. Luồng kết thúc ván thắng không cộng vàng local khi chưa claim on-chain', () async {
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

      // Không có giao dịch claim thành công thì topbar không được cộng vàng.
      expect(pv.vang, soVangBanDau);
      expect(pv.vangDinhDang, soVangBanDau.toString());

      // Đảm bảo cờ bảo vệ đã được bật
      expect(game.daGuiVaXinPhieu, isTrue);
    });

    test(
      '4. Luồng đặt cọc trừ vàng; phần thưởng chỉ hiện sau claim on-chain',
      () async {
        final game = GoldRushGame();
        final pv = game.phienVi!;

        // Cấp sẵn 50 vàng trong ví
        await pv.congVang(BigInt.from(50));
        expect(pv.vang, BigInt.from(50));

        const man2 = ManChoi(
          id: 2,
          ten: 'Khu rừng cạm bẫy',
          moTa: 'Cây cối thưa, ít quái',
          tep: 'assets/tiles/map2.tmx',
          gioiHanGiay: 100,
          heSoKeDich: 1.0,
          coc: 5,
          thuong: 5,
          soXu: 18,
          sao: 1,
        );

        // Đặt cọc 5 vàng để chuẩn bị vào màn 2
        final chuanBi = await pv.chuanBiMan(man2, 'van-coc-001');
        expect(chuanBi, isNotNull);
        // Vàng đã bị trừ 5 (còn 45)
        expect(pv.vang, BigInt.from(45));

        // Thắng màn 2: nhặt 18 xu -> hoàn cọc 5 + 18 xu + 5 thưởng = 28 vàng
        const kqThang = KetQuaVan(
          man: man2,
          maVan: 'van-coc-001',
          thang: true,
          xu: 18,
        );

        await game.guiVaXinPhieuChoKiemThu(
          nk: {'ma_van': 'van-coc-001', 'ket_qua': 'thang'},
          maVan: 'van-coc-001',
          kq: kqThang,
          coPhieu: true,
        );

        // Chưa có giao dịch claim thành công nên vẫn chỉ còn 45 vàng on-chain.
        expect(pv.vang, BigInt.from(45));
      },
    );

    test('5. Thua màn có cọc: không hoàn lại tiền cọc đã trừ', () async {
      final game = GoldRushGame();
      final pv = game.phienVi!;

      await pv.congVang(BigInt.from(20));
      expect(pv.vang, BigInt.from(20));

      const man2 = ManChoi(
        id: 2,
        ten: 'Khu rừng cạm bẫy',
        moTa: 'Cây cối thưa, ít quái',
        tep: 'assets/tiles/map2.tmx',
        gioiHanGiay: 100,
        heSoKeDich: 1.0,
        coc: 5,
        thuong: 5,
        soXu: 18,
        sao: 1,
      );

      // Đặt cọc 5 vàng
      await pv.chuanBiMan(man2, 'van-coc-002');
      expect(pv.vang, BigInt.from(15));

      // Thua ván
      const kqThua = KetQuaVan(
        man: man2,
        maVan: 'van-coc-002',
        thang: false,
        xu: 5,
      );

      await game.guiVaXinPhieuChoKiemThu(
        nk: {'ma_van': 'van-coc-002', 'ket_qua': 'thua'},
        maVan: 'van-coc-002',
        kq: kqThua,
        coPhieu: false,
      );

      // Thua nên không được cộng thưởng / hoàn cọc -> giữ nguyên 15 vàng
      expect(pv.vang, BigInt.from(15));
    });
  });
}
