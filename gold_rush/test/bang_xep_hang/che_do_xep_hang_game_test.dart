// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/mo_hinh_do_kho.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../lich_su/ho_tro_lich_su.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actual game frames retain adaptive ranking mode after toggle and reset next run', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final auth = AuthLichSu();
    final game = await gameLichSu(auth);
    addTearDown(auth.dispose);
    addTearDown(game.danhSachVatPham.dispose);
    addTearDown(game.ketQuaVan.dispose);
    addTearDown(game.phienVi!.dispose);
    game.danhSachMan = const [
      ManChoi(
        id: 1,
        ten: 'Test',
        moTa: '',
        tep: 'gold_rush.tmx',
        gioiHanGiay: 0,
        heSoKeDich: 1,
        coc: 0,
        thuong: 0,
        soXu: 1,
        sao: 1,
        chiChoiLocal: true,
      ),
    ];
    game.manHienTai = game.danhSachMan.single;
    game.tienTrinhWorldMap.khoiTaoChoKiemThu([1]);
    game.doKho.moHinh = MoHinhDoKho.tuJson(
      jsonDecode(File('assets/models/do_kho_v1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await game.batDauVanMoi(maVan: 'rank-mode-1');
    game.doKho.batThichUng = false;
    game.update(0.1);
    game.doKho.batThichUng = true;
    game.update(0.1);
    game.doKho.batThichUng = false;
    game.update(0.1);
    Map<String, Object> data() => game.nhatKy.thanhJson(
      ketQua: 'thang',
      diem: 20,
      phienBanApp: 'test',
      doKhoThichUng: false,
    );
    expect(data()['xep_hang_thich_ung'], isTrue);
    expect(data()['do_kho_thich_ung'], isFalse);
    await game.batDauVanMoi(maVan: 'rank-mode-2');
    game.update(0.1);
    expect(data()['xep_hang_thich_ung'], isFalse);
  });
}
