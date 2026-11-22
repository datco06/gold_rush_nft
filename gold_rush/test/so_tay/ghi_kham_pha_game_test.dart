// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/components/ke_dich.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/kho_do/danh_sach_trang_bi.dart';
import 'package:gold_rush/kho_do/vat_pham_hien_thi.dart';
import 'package:gold_rush/so_tay/so_tay_kham_pha.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'ho_tro_so_tay.dart';
import '../blockchain/vi_gia.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  void cleanup(GoldRushGame g) {
    addTearDown(g.onRemove);
    addTearDown(g.danhSachVatPham.dispose);
    addTearDown(g.phienVi!.dispose);
  }

  test('preview and failed start unlock nothing; actual start discovers location, enemies and Boss', () async {
    final auth = AuthLichSu();
    final g = await gameSoTay(auth, boss: true, quai: ['zombie', 'skeleton']);
    cleanup(g);
    g.veMenu();
    expect((await g.docSoTayKhamPha()).daMo, isEmpty);
    g.tienTrinhWorldMap.khoiTaoChoKiemThu([7], hoanThanh: {});
    await g.batDauVanMoi(maVan: 'real');
    expect((await g.docSoTayKhamPha()).daMo, {
      'dia_diem:7',
      'quai:zombie',
      'quai:skeleton',
      'quai:boss',
    });
    g.veMenu();
    final next = await gameSoTay(AuthLichSu());
    cleanup(next);
    expect((await next.docSoTayKhamPha()).daMo, contains('quai:boss'));
    final denied = await gameSoTay(AuthLichSu()..wallet = '0x${'b' * 40}');
    cleanup(denied);
    denied.tienTrinhWorldMap.khoiTaoChoKiemThu([1, 7], hoanThanh: {});
    await denied.batDauVanMoi(maVan: 'denied');
    expect((await denied.docSoTayKhamPha()).daMo, isEmpty);
  });

  test('additional enemies during a session check wait for the same authenticated owner', () async {
    final auth = AuthLichSu();
    final g = await gameSoTay(auth, manId: 16);
    cleanup(g);
    await g.batDauVanMoi(maVan: 'spawn');
    expect((await g.docSoTayKhamPha()).daMo, isNot(contains('quai:giap')));
    auth.allowed = false;
    auth.phase = AuthStatus.checkingSession;
    auth.thayDoi();
    g.nhatKy.giay = 70;
    g.update(2);
    expect(
      g.theGioi.children.whereType<KeDich>().any((q) => q.maxHp == 100),
      isTrue,
    );
    expect((await g.docSoTayKhamPha()).daMo, isEmpty);
    auth.allowed = true;
    auth.phase = AuthStatus.authenticated;
    auth.thayDoi();
    expect((await g.docSoTayKhamPha()).daMo, contains('quai:giap'));
  });

  test('only confirmed catalog inventory is discovered; notebook never creates owned items', () async {
    final auth = AuthLichSu();
    final g = await gameSoTay(auth);
    cleanup(g);
    final item = danhSachTrangBiCuaHang().first;
    g.themVatPhamVaoKho(
      VatPhamHienThi(
        id: 'sung_cap_2',
        ten: 'Demo',
        loai: LoaiVatPham.vuKhi,
        doHiem: DoHiemVatPham.thuong,
        nguon: NguonVatPham.game,
        laDuLieuMau: true,
      ),
    );
    expect((await g.docSoTayKhamPha()).daMo, isEmpty);
    g.dongBoSoLuongVatPham(item, 0);
    expect((await g.docSoTayKhamPha()).daMo, isEmpty);
    g.themVatPhamVaoKho(item);
    expect((await g.docSoTayKhamPha()).daMo, {'trang_bi:${item.id}'});
    final count = g.danhSachVatPham.value.length;
    await LuuSoTayKhamPha(
      wallet: auth.wallet,
      chainId: auth.chain,
    ).ghi({'trang_bi:sung_hiem_1'});
    await g.docSoTayKhamPha();
    expect(g.danhSachVatPham.value.length, count);
    auth.wallet = '0x${'b' * 40}';
    g.dongBoSoLuongVatPham(danhSachTrangBiCuaHang()[2], 1);
    expect((await g.docSoTayKhamPha()).daMo, isEmpty);
  });

  test('logout and game removal discard pending discoveries', () async {
    for (final remove in [false, true]) {
      final auth = AuthLichSu()..wallet = '0x${(remove ? 'c' : 'd') * 40}';
      final g = await gameSoTay(auth, manId: 16);
      cleanup(g);
      await g.batDauVanMoi(maVan: 'logout');
      auth.allowed = false;
      auth.phase = AuthStatus.checkingSession;
      g.nhatKy.giay = 70;
      g.update(2);
      if (remove) {
        g.onRemove();
      } else {
        auth.pendingLogout = true;
        auth.phase = AuthStatus.loggingOut;
        auth.thayDoi();
      }
      auth.allowed = true;
      auth.pendingLogout = false;
      auth.phase = AuthStatus.authenticated;
      auth.thayDoi();
      expect(
        (await LuuSoTayKhamPha(
          wallet: auth.wallet,
          chainId: auth.chain,
        ).doc()).daMo,
        isNot(contains('quai:giap')),
      );
    }
  });

  test('a confirmed NFT balance discovers only owned equipment without sending a transaction', () async {
    final fixture = jsonDecode(
      File('test/blockchain/vat_pham/nft_abi_mau.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final auth = AuthLichSu()..wallet = fixture['player'] as String;
    final g = await gameSoTay(auth);
    cleanup(g);
    final pv = g.phienVi!;
    pv.cauHinh = CauHinhChuoi(
      chainId: auth.chain,
      hopDong: hopDongThu,
      hopDongVatPham: fixture['contract'] as String,
      trongTai: viThu,
    );
    final vi = pv.vi as ViGia;
    for (final key in ['typehash', 'domain', 'supports']) {
      vi.ketQuaGoi[fixture['calls'][key] as String] =
          fixture['results'][key] as String;
    }
    final n = danhSachTrangBiCuaHang().length;
    String word(int value) => value.toRadixString(16).padLeft(64, '0');
    final data =
        '0x4e1273f4${word(64)}${word(96 + n * 32)}${word(n)}'
        '${List.filled(n, auth.wallet.substring(2).padLeft(64, '0')).join()}'
        '${word(n)}${List.generate(n, (i) => word(i + 1)).join()}';
    vi.ketQuaGoi[data] =
        '0x${word(32)}${word(n)}${List.generate(n, (i) => word(i == 0 ? 1 : 0)).join()}';
    await g.dongBoNFTKhoDo();
    expect((await g.docSoTayKhamPha()).daMo, {
      'trang_bi:${danhSachTrangBiCuaHang().first.id}',
    });
    expect(vi.daGui, isEmpty);
    expect(g.danhSachVatPham.value, hasLength(1));
  });
}
