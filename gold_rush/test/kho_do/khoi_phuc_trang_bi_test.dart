// Existing in-memory preferences backend used only by tests.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/ai/nhan_vat_ai_models.dart';
import 'package:gold_rush/blockchain/cua_hang.dart';
import 'package:gold_rush/blockchain/giao_dich.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/nhan_vat.dart';
import 'package:gold_rush/blockchain/vi.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/kho_do/danh_sach_trang_bi.dart';
import 'package:gold_rush/kho_do/luu_lua_chon.dart';
import 'package:gold_rush/kho_do/vat_pham_hien_thi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../blockchain/vi_gia.dart';

class _Auth extends AuthControllerFake {
  _Auth(this.wallet, {this.chain = 31337});
  String wallet;
  int chain;
  bool allowed = true;
  @override
  bool get canEnterGame => allowed;
  @override
  String get walletAddress => wallet;
  @override
  BigInt get chainId => BigInt.from(chain);
}

class AuthControllerFake implements AuthController {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected auth action: ${invocation.memberName}',
  );
}

class _ViBatch extends ViGia {
  _ViBatch(this.fixture)
    : super(taiKhoan: [fixture['voucher']['player'] as String]);
  final Map<String, dynamic> fixture;
  final owned = <int>{};
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String> goi({
    required String toi,
    required String duLieu,
    String? tu,
  }) async {
    if (duLieu.startsWith('0x4e1273f4')) {
      if (fail) throw const LoiVi('RPC unavailable');
      if (gate != null) await gate!.future;
      final n = int.parse(duLieu.substring(138, 202), radix: 16);
      String word(int value) => value.toRadixString(16).padLeft(64, '0');
      return '0x${word(32)}${word(n)}${List.generate(n, (i) => word(owned.contains(i + 1) ? 1 : 0)).join()}';
    }
    for (final name in ['typehash', 'domain', 'supports']) {
      if (duLieu == fixture['calls'][name]) {
        return fixture['results'][name] as String;
      }
    }
    return super.goi(toi: toi, duLieu: duLieu, tu: tu);
  }
}

class _ApiNhanVat implements MayChuNhanVat {
  final detail = Completer<KetQuaLuuNhanVat>();
  final sprite = Completer<KetQuaPngNhanVat>();
  final spriteRequested = Completer<void>();
  @override
  Future<KetQuaLuuNhanVat> layChiTiet(String characterId) => detail.future;
  @override
  Future<KetQuaPngNhanVat> taiSpriteSheetDaLuu(String characterId) {
    spriteRequested.complete();
    return sprite.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected character API action: ${invocation.memberName}',
  );
}

final class _PrefsCham extends InMemorySharedPreferencesAsync {
  _PrefsCham() : super.empty();
  bool block = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async {
    final value = await super.getString(key, options);
    if (block) {
      block = false;
      started.complete();
      await release.future;
    }
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = danhSachTrangBiCuaHang();
  final armor = catalog.firstWhere((i) => i.loai == LoaiVatPham.giap);
  final boots = catalog.firstWhere((i) => i.loai == LoaiVatPham.giay);
  final gun = catalog.first;

  GoldRushGame game(_Auth auth, {ViGia? wallet, MayChuNhanVat? api}) {
    final vi = wallet ?? ViGia(taiKhoan: [auth.wallet], mang: auth.chain);
    final g = GoldRushGame(auth: auth, vi: vi, mayChuNhanVat: api);
    final pv = g.phienVi!;
    pv.diaChi = auth.wallet;
    pv.cauHinh = CauHinhChuoi(
      chainId: auth.chain,
      hopDong: hopDongThu,
      trongTai: viThu,
    );
    pv.cuaHang = CuaHangChuoi(
      vi: vi,
      hopDong: hopDongThu,
      bo: BoGiaoDich.choMang(vi: vi, chainId: auth.chain, hopDong: hopDongThu),
    );
    addTearDown(pv.dispose);
    addTearDown(g.danhSachVatPham.dispose);
    return g;
  }

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'equipped armor and boots survive a new game after inventory arrives late',
    () async {
      final first = game(_Auth(viThu));
      first.danhSachVatPham.value = [armor, boots];
      await first.trangBiVatPham(armor.id);
      await first.trangBiVatPham(boots.id);
      final next = game(_Auth(viThu.toUpperCase()));
      await next.khoiPhucLuaChonKhoDo();
      expect(next.danhSachVatPham.value, isEmpty);
      next.danhSachVatPham.value = [armor, boots];
      await next.khoiPhucLuaChonKhoDo();
      expect(next.danhSachVatPham.value.every((i) => i.dangTrangBi), isTrue);
      expect(next.danhSachVatPham.value.first.oDangTrangBi, OTrangBi.giap);
      await next.thaoVatPham(boots.id);
      final third = game(_Auth(viThu));
      third.danhSachVatPham.value = [armor, boots];
      await third.khoiPhucLuaChonKhoDo();
      expect(third.danhSachVatPham.value.first.dangTrangBi, isTrue);
      expect(third.danhSachVatPham.value.last.dangTrangBi, isFalse);
    },
  );

  test('another wallet or chain cannot inherit equipped items', () async {
    final first = game(_Auth(viThu));
    first.danhSachVatPham.value = [armor];
    await first.trangBiVatPham(armor.id);
    for (final auth in [
      _Auth('0x${'b' * 40}'),
      _Auth(viThu, chain: 11155111),
    ]) {
      final next = game(auth);
      next.danhSachVatPham.value = [armor];
      await next.khoiPhucLuaChonKhoDo();
      expect(next.danhSachVatPham.value.single.dangTrangBi, isFalse);
    }
  });

  test('missing item stays pending and equipping a different slot does not erase it', () async {
    final store = LuuLuaChonKhoDo(wallet: viThu, chainId: 31337);
    await store.luuOTrangBi('giap', armor.id);
    final next = game(_Auth(viThu));
    next.danhSachVatPham.value = [gun];
    await next.khoiPhucLuaChonKhoDo();
    await next.trangBiVatPham(gun.id);
    next.danhSachVatPham.value = [...next.danhSachVatPham.value, armor];
    await next.khoiPhucLuaChonKhoDo();
    expect(next.danhSachVatPham.value.every((i) => i.dangTrangBi), isTrue);
    expect((await store.doc()).trangBi['giap'], armor.id);
  });

  test(
    'saved IDs never recreate ownership or apply an incompatible slot',
    () async {
      final store = LuuLuaChonKhoDo(wallet: viThu, chainId: 31337);
      await store.luuOTrangBi('giap', gun.id);
      await store.luuOTrangBi('giay', 'missing');
      final next = game(_Auth(viThu));
      next.danhSachVatPham.value = [gun];
      await next.khoiPhucLuaChonKhoDo();
      expect(next.danhSachVatPham.value, hasLength(1));
      expect(next.danhSachVatPham.value.single.dangTrangBi, isFalse);
    },
  );

  test(
    'legacy shared key is not treated as a choice belonging to this wallet',
    () async {
      await SharedPreferencesAsync().setString(
        'gold_rush.equipment.v1',
        jsonEncode({'giap': armor.id}),
      );
      final next = game(_Auth(viThu));
      next.danhSachVatPham.value = [armor];
      await next.khoiPhucLuaChonKhoDo();
      expect(next.danhSachVatPham.value.single.dangTrangBi, isFalse);
    },
  );

  test('NFT sync restores equipped selection and keeps it through a failed refresh', () async {
    final fixture = jsonDecode(
      File('test/blockchain/vat_pham/nft_abi_mau.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final vi = _ViBatch(fixture);
    final auth = _Auth(fixture['voucher']['player'] as String);
    final next = game(auth, wallet: vi);
    next.phienVi!.cauHinh = CauHinhChuoi(
      chainId: 31337,
      hopDong: hopDongThu,
      hopDongVatPham: fixture['contract'] as String,
      trongTai: viThu,
    );
    final token = catalog.indexOf(armor) + 1;
    vi.owned.add(token);
    final store = LuuLuaChonKhoDo(wallet: auth.wallet, chainId: 31337);
    await store.luuOTrangBi('giap', armor.id);
    await next.dongBoNFTKhoDo();
    expect(next.danhSachVatPham.value.single.oDangTrangBi, OTrangBi.giap);
    vi.fail = true;
    await expectLater(next.dongBoNFTKhoDo(force: true), throwsA(isA<LoiVi>()));
    expect((await store.doc()).trangBi['giap'], armor.id);
    vi.fail = false;
    await next.dongBoNFTKhoDo(force: true);
    expect(next.danhSachVatPham.value.single.oDangTrangBi, OTrangBi.giap);
    expect(vi.daGui, isEmpty);
  });

  test('NFT result arriving after logout cannot recreate inventory', () async {
    final fixture = jsonDecode(
      File('test/blockchain/vat_pham/nft_abi_mau.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final vi = _ViBatch(fixture)
      ..owned.add(1)
      ..gate = Completer<void>();
    final auth = _Auth(fixture['voucher']['player'] as String);
    final next = game(auth, wallet: vi);
    next.phienVi!.cauHinh = CauHinhChuoi(
      chainId: 31337,
      hopDong: hopDongThu,
      hopDongVatPham: fixture['contract'] as String,
      trongTai: viThu,
    );
    final pending = next.dongBoNFTKhoDo();
    await Future<void>.delayed(Duration.zero);
    auth.allowed = false;
    vi.gate!.complete();
    await pending;
    expect(next.danhSachVatPham.value, isEmpty);
    expect(vi.daGui, isEmpty);
  });

  test('character skin survives login but restores only after current ownership confirms', () async {
    final first = game(_Auth(viThu));
    first.phienVi!.daCo.add(1);
    await first.luuNhanVatDaChon(bangNhanVat.first);
    final next = game(_Auth(viThu));
    await next.khoiPhucLuaChonKhoDo();
    expect(next.nhanVatDangDung, georgeGoc.tepAnh);
    next.phienVi!.daCo.add(1);
    await next.khoiPhucLuaChonKhoDo();
    expect(next.nhanVatDangDung, bangNhanVat.first.tepAnh);
    expect(next.tenNhanVatDangDung, bangNhanVat.first.ten);
    await next.luuNhanVatDaChon(georgeGoc);
    final third = game(_Auth(viThu));
    third.phienVi!.daCo.add(1);
    await third.khoiPhucLuaChonKhoDo();
    expect(third.nhanVatDangDung, georgeGoc.tepAnh);
  });

  test('signed out game cannot restore saved selections', () async {
    final store = LuuLuaChonKhoDo(wallet: viThu, chainId: 31337);
    await store.luuNhanVat(bangNhanVat.first.tepAnh);
    await store.luuOTrangBi('giap', armor.id);
    final auth = _Auth(viThu)..allowed = false;
    final next = game(auth);
    next.phienVi!.daCo.add(1);
    next.danhSachVatPham.value = [armor];
    await next.khoiPhucLuaChonKhoDo();
    expect(next.nhanVatDangDung, georgeGoc.tepAnh);
    expect(next.danhSachVatPham.value.single.dangTrangBi, isFalse);
  });

  test('an equip during a delayed startup read preserves both the new and saved slots', () async {
    final prefs = _PrefsCham();
    SharedPreferencesAsyncPlatform.instance = prefs;
    await LuuLuaChonKhoDo(
      wallet: viThu,
      chainId: 31337,
    ).luuOTrangBi('giap', armor.id);
    prefs.block = true;
    final next = game(_Auth(viThu));
    next.danhSachVatPham.value = [armor, boots];
    final restoring = next.khoiPhucLuaChonKhoDo();
    await prefs.started.future;
    final equipping = next.trangBiVatPham(boots.id);
    prefs.release.complete();
    await Future.wait([restoring, equipping]);
    expect(next.danhSachVatPham.value.every((i) => i.dangTrangBi), isTrue);
  });

  test(
    'choosing a character during startup preserves the saved armor slot',
    () async {
      final prefs = _PrefsCham();
      SharedPreferencesAsyncPlatform.instance = prefs;
      await LuuLuaChonKhoDo(
        wallet: viThu,
        chainId: 31337,
      ).luuOTrangBi('giap', armor.id);
      prefs.block = true;
      final next = game(_Auth(viThu));
      next.phienVi!.daCo.add(bangNhanVat.first.id);
      next.danhSachVatPham.value = [armor];
      final restoring = next.khoiPhucLuaChonKhoDo();
      await prefs.started.future;
      final choosing = next.luuNhanVatDaChon(bangNhanVat.first);
      prefs.release.complete();
      await Future.wait([restoring, choosing]);
      expect(next.nhanVatDangDung, bangNhanVat.first.tepAnh);
      expect(next.danhSachVatPham.value.single.oDangTrangBi, OTrangBi.giap);
    },
  );

  test(
    'removing the game during a pending restore leaves its inventory alone',
    () async {
      final prefs = _PrefsCham();
      SharedPreferencesAsyncPlatform.instance = prefs;
      await LuuLuaChonKhoDo(
        wallet: viThu,
        chainId: 31337,
      ).luuOTrangBi('giap', armor.id);
      prefs.block = true;
      final next = game(_Auth(viThu));
      next.danhSachVatPham.value = [armor];
      final restoring = next.khoiPhucLuaChonKhoDo();
      await prefs.started.future;
      next.onRemove();
      prefs.release.complete();
      await restoring;
      expect(next.danhSachVatPham.value.single.dangTrangBi, isFalse);
    },
  );

  test(
    'logout during a delayed preference read ignores the old selection',
    () async {
      final prefs = _PrefsCham();
      SharedPreferencesAsyncPlatform.instance = prefs;
      await LuuLuaChonKhoDo(
        wallet: viThu,
        chainId: 31337,
      ).luuOTrangBi('giap', armor.id);
      prefs.block = true;
      final auth = _Auth(viThu);
      final next = game(auth);
      next.danhSachVatPham.value = [armor];
      final restoring = next.khoiPhucLuaChonKhoDo();
      await prefs.started.future;
      auth.allowed = false;
      prefs.release.complete();
      await restoring;
      expect(next.danhSachVatPham.value.single.dangTrangBi, isFalse);
    },
  );

  test('AI restore stays in background and equipping armor does not cancel its skin', () async {
    const id = 'char_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final store = LuuLuaChonKhoDo(wallet: viThu, chainId: 31337);
    await store.luuNhanVat('ai:$id');
    final api = _ApiNhanVat();
    final next = game(_Auth(viThu), api: api);
    next.danhSachVatPham.value = [armor];
    await next.khoiPhucLuaChonKhoDo().timeout(const Duration(seconds: 1));
    expect(next.nhanVatDangDung, georgeGoc.tepAnh);
    api.detail.complete(
      KetQuaLuuNhanVat(
        nhanVat: ThongTinNhanVat(
          characterId: id,
          name: 'Alice',
          imageId: 'img_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          characterHash: '0x${'a' * 64}',
          verifiedWalletAddress: viThu,
          createdAt: DateTime.utc(2026),
          onchainStatus: TrangThaiOnchain.notRegistered,
        ),
      ),
    );
    await api.spriteRequested.future;
    await next.trangBiVatPham(armor.id);
    final picture = ui.PictureRecorder();
    ui.Canvas(picture)
        .drawRect(const ui.Rect.fromLTWH(0, 0, 64, 64), ui.Paint());
    final image = await picture.endRecording().toImage(64, 64);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    image.dispose();
    final restored = Completer<void>();
    next.danhSachVatPham.addListener(() {
      if (next.nhanVatDangDung == 'ai:$id' && !restored.isCompleted) {
        restored.complete();
      }
    });
    api.sprite.complete(KetQuaPngNhanVat(png: bytes));
    await restored.future.timeout(const Duration(seconds: 3));
    expect(next.tenNhanVatDangDung, 'Alice');
    expect(next.danhSachVatPham.value.single.oDangTrangBi, OTrangBi.giap);
  });
}
