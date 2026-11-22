// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/dong_xu.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/lich_su/lich_su_man_choi.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'ho_tro_lich_su.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<GoldRushGame> game(AuthLichSu auth, {int gioiHan = 0}) async {
    final g = await gameLichSu(auth, gioiHan: gioiHan);
    addTearDown(g.danhSachVatPham.dispose);
    addTearDown(g.ketQuaVan.dispose);
    addTearDown(g.phienVi!.dispose);
    return g;
  }

  test(
    'win persists once after login, duration excludes pauses and preview',
    () async {
      final auth = AuthLichSu();
      final g = await game(auth);
      expect(await g.docLichSuManChoi(), isEmpty);
      await g.batDauVanMoi(maVan: 'win-1');
      g.update(3.5);
      g.tamDung();
      g.update(90);
      g.tiepTuc();
      g.update(2);
      g.george!.onCollisionStart(
        {},
        g.theGioi.children.whereType<DongXu>().single,
      );
      expect(g.trangThai, TrangThaiChoi.thang);
      final saved = await g.docLichSuManChoi();
      expect(saved, hasLength(1));
      expect(saved.single.thang, isTrue);
      expect(saved.single.giay, 5.5);
      expect(saved.single.manId, 7);
      expect(saved.single.tenMan, 'Rừng thưa');
      expect(
        DateTime.now().toUtc().difference(saved.single.ketThuc).inSeconds,
        lessThan(5),
      );
      g.veMenu();
      final next = await game(AuthLichSu());
      expect((await next.docLichSuManChoi()).single.maVan, 'win-1');
      await next.batDauVanMoi(maVan: 'loss-2');
      next.update(1);
      next.george!.nhanSatThuong(CauHinh.mauToiDa);
      final both = await next.docLichSuManChoi();
      expect(both, hasLength(2));
      expect(both.first.thang, isFalse);
    },
  );

  test(
    'timeout saves defeat, while an abandoned match is not defeat',
    () async {
      final g = await game(AuthLichSu(), gioiHan: 5);
      await g.batDauVanMoi(maVan: 'abort');
      g.update(2);
      g.veMenu();
      expect(await g.docLichSuManChoi(), isEmpty);
      await g.batDauVanMoi(maVan: 'timeout');
      g.update(4);
      g.update(1.1);
      expect(g.trangThai, TrangThaiChoi.thua);
      final saved = await g.docLichSuManChoi();
      expect(saved.single.thang, isFalse);
      expect(saved.single.maVan, 'timeout');
      expect(saved.single.giay, 5);
    },
  );

  test(
    'logout or wallet switch cannot assign the previous match to a new owner',
    () async {
      final auth = AuthLichSu();
      final oldWallet = auth.wallet;
      final g = await game(auth);
      await g.batDauVanMoi(maVan: 'old-wallet');
      auth.wallet = '0x${'b' * 40}';
      g.george!.nhanSatThuong(CauHinh.mauToiDa);
      expect(await g.docLichSuManChoi(), isEmpty);
      expect(
        await LuuLichSuManChoi(wallet: oldWallet, chainId: 31337).doc(),
        isEmpty,
      );
      await g.batDauVanMoi(maVan: 'logged-out');
      auth.allowed = false;
      g.george!.nhanSatThuong(CauHinh.mauToiDa);
      expect(await g.docLichSuManChoi(), isEmpty);
    },
  );

  test('a match completed during passive session check saves only after the same owner returns', () async {
    for (final sameOwner in [true, false]) {
      final auth = AuthLichSu();
      final original = auth.wallet;
      final g = await game(auth);
      await g.batDauVanMoi(maVan: 'session-$sameOwner');
      g.update(2);
      auth.allowed = false;
      auth.phase = AuthStatus.checkingSession;
      auth.thayDoi();
      g.george!.nhanSatThuong(CauHinh.mauToiDa);
      expect(await g.docLichSuManChoi(), isEmpty);
      if (!sameOwner) auth.wallet = '0x${'b' * 40}';
      auth.allowed = true;
      auth.phase = AuthStatus.authenticated;
      auth.thayDoi();
      final saved = await g.docLichSuManChoi();
      if (sameOwner) {
        expect(saved.single.maVan, 'session-true');
        expect(saved.single.giay, 2);
        expect(saved.single.thang, isFalse);
        auth.thayDoi();
        expect(await g.docLichSuManChoi(), hasLength(1));
      } else {
        expect(saved, isEmpty);
        expect(
          (await LuuLichSuManChoi(
            wallet: original,
            chainId: 31337,
          ).doc()).any((v) => v.maVan == 'session-false'),
          isFalse,
        );
      }
    }
  });

  test('pending history is discarded on real logout or game removal', () async {
    for (final remove in [false, true]) {
      final auth = AuthLichSu();
      final g = await game(auth);
      await g.batDauVanMoi(maVan: 'discard-$remove');
      auth.allowed = false;
      auth.phase = AuthStatus.checkingSession;
      g.george!.nhanSatThuong(CauHinh.mauToiDa);
      if (remove) {
        g.onRemove();
      } else {
        auth.pendingLogout = true;
        auth.phase = AuthStatus.loggingOut;
        auth.thayDoi();
      }
      auth.pendingLogout = false;
      auth.allowed = true;
      auth.phase = AuthStatus.authenticated;
      auth.thayDoi();
      expect(
        await LuuLichSuManChoi(wallet: auth.wallet, chainId: auth.chain).doc(),
        isEmpty,
      );
    }
  });
}
