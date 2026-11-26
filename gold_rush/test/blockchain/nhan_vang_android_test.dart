// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/abi.dart';
import 'package:gold_rush/blockchain/cua_hang.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/blockchain/vi.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'vi_gia.dart';

class _MayChuGia extends MayChuPhieu {
  _MayChuGia(this.phieu) : super(mayChu: 'http://localhost:8000');

  final PhieuCho phieu;
  int soLanTaiPhieu = 0;

  @override
  Future<List<PhieuCho>> phieuChoNhan(String vi) async {
    soLanTaiPhieu++;
    return [phieu];
  }
}

class _ViChoBienLai extends ViGia {
  final dangCho = Completer<void>();
  final bienLaiMoi = Completer<BienLai>();

  @override
  Future<BienLai?> bienLai(String maGiaoDich) {
    if (!dangCho.isCompleted) dangCho.complete();
    return bienLaiMoi.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PhieuCho phieu;
  late _MayChuGia mayChu;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    phieu = PhieuCho(
      maVan: 'van-2',
      chuKy: '0x${'3' * 130}',
      phieu: PhieuVang(
        nguoiChoi: viThu,
        man: BigInt.from(2),
        ve: BigInt.one,
        soVang: BigInt.from(18),
        maVan: '0x${'a' * 64}',
        hanChot: BigInt.from(
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
        ),
      ),
    );
    mayChu = _MayChuGia(phieu);
  });

  PhienVi taoPhien(ViGia vi) {
    vi.datVe(viThu, man: 2, so: 1, coc: 5);
    final pv = PhienVi(vi: vi, mayChu: mayChu)
      ..diaChi = viThu
      ..cuaHang = CuaHangChuoi(vi: vi, hopDong: hopDongThu, bo: boThu(vi));
    addTearDown(pv.dispose);
    return pv;
  }

  test(
    'Nhận vàng ván có cọc cập nhật số dư và vé sau khi ví trả biên lai',
    () async {
      final vi = ViGia();
      final pv = taoPhien(vi);
      vi.khiGui = (_) {
        vi.datSo(maHoaDaDoi(phieu.phieu.maVan), BigInt.one);
        vi.datSo(maHoaBalanceOf(viThu, 0), BigInt.from(23));
        vi.datVe(viThu, man: 0, so: 0, coc: 0);
      };

      expect(await pv.nhanTatCa(), isTrue);
      expect(vi.daGui, [maHoaNhanVang(phieu.phieu, phieu.chuKy)]);
      expect(pv.vang, BigInt.from(23));
      expect(pv.ve.dangMo, isFalse);
      expect(pv.phieuCho, isEmpty);
      expect(mayChu.soLanTaiPhieu, 1);
    },
  );

  test('Phiên đóng khi chờ biên lai thì không đồng bộ vào phiên cũ', () async {
    final vi = _ViChoBienLai();
    final pv = taoPhien(vi);
    final nhan = pv.nhanTatCa();
    await vi.dangCho.future;
    pv.dispose();
    vi.bienLaiMoi.complete(const BienLai(thanhCong: true));

    expect(await nhan, isFalse);
    expect(vi.daGui, hasLength(1));
    expect(mayChu.soLanTaiPhieu, 1);
  });
}
