import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/world_map/luu_tien_trinh.dart';

class _KhoNho implements KhoTienTrinhLocal {
  String? data;
  bool loiDoc = false;
  bool loiGhi = false;
  Future<void> Function()? truocGhi;
  final List<String> daGhi = [];

  @override
  Future<String?> doc() async {
    if (loiDoc) throw StateError('storage unavailable');
    return data;
  }

  @override
  Future<void> ghi(String noiDung) async {
    await truocGhi?.call();
    if (loiGhi) throw StateError('storage unavailable');
    data = noiDung;
    daGhi.add(noiDung);
  }
}

void main() {
  final levels = ManChoi.docBoManChoi(
    File('assets/tiles/man_choi.json').readAsStringSync(),
    File('assets/tiles/man_mo_rong.json').readAsStringSync(),
  );

  test(
    'Máy chưa có tiến trình chỉ mở màn 1, không tự đánh dấu hoàn thành',
    () async {
      final progress = BoTienTrinhWorldMap(kho: _KhoNho());
      addTearDown(progress.dispose);
      expect(progress.duocChoi(1), isFalse);
      await progress.nap(levels);
      expect(progress.tienTrinh.cacManDaMo, {1});
      expect(progress.tienTrinh.cacManHoanThanh, isEmpty);
      expect(progress.duocChoi(2), isFalse);
    },
  );

  test(
    'Thắng mở đúng một màn kế tiếp và khôi phục sau khi đóng/mở app',
    () async {
      final storage = _KhoNho();
      final first = BoTienTrinhWorldMap(kho: storage);
      addTearDown(first.dispose);
      await first.nap(levels);
      expect(await first.ghiNhanThang(1), isTrue);
      expect(first.tienTrinh.cacManDaMo, {1, 2});
      expect(first.tienTrinh.cacManHoanThanh, {1});
      final reopened = BoTienTrinhWorldMap(kho: storage);
      addTearDown(reopened.dispose);
      await reopened.nap(levels);
      expect(reopened.tienTrinh.cacManDaMo, {1, 2});
      expect(reopened.tienTrinh.manHienTai, 2);
      expect(reopened.duocChoi(3), isFalse);
    },
  );

  test(
    'Không nhận thắng từ màn khóa, ID lạ hoặc tiến trình chưa tải',
    () async {
      final storage = _KhoNho();
      final progress = BoTienTrinhWorldMap(kho: storage);
      addTearDown(progress.dispose);
      expect(await progress.ghiNhanThang(1), isFalse);
      await progress.nap(levels);
      expect(await progress.ghiNhanThang(20), isFalse);
      expect(await progress.ghiNhanThang(100), isFalse);
      expect(storage.daGhi, isEmpty);
      expect(progress.tienTrinh.cacManDaMo, {1});
    },
  );

  test('Chơi lại màn cũ không mở nhảy cóc', () async {
    final progress = BoTienTrinhWorldMap(kho: _KhoNho());
    addTearDown(progress.dispose);
    await progress.nap(levels);
    await progress.ghiNhanThang(1);
    await progress.ghiNhanThang(1);
    expect(progress.tienTrinh.cacManDaMo, {1, 2});
    expect(progress.duocChoi(3), isFalse);
  });

  test('Thắng đủ 20 màn giữ màn 20, không tạo màn 21', () async {
    final progress = BoTienTrinhWorldMap(kho: _KhoNho());
    addTearDown(progress.dispose);
    await progress.nap(levels);
    for (final level in levels) {
      expect(await progress.ghiNhanThang(level.id), isTrue);
    }
    expect(progress.tienTrinh.cacManHoanThanh, hasLength(20));
    expect(progress.tienTrinh.cacManDaMo, hasLength(20));
    expect(progress.tienTrinh.manHienTai, 20);
    expect(progress.duocChoi(21), isFalse);
  });

  test('Dữ liệu bị sửa có khoảng trống không mở các màn phía sau', () async {
    final storage = _KhoNho()
      ..data = jsonEncode({
        'phien_ban': 1,
        'hoan_thanh': [1, 3, 4, 5, 99],
      });
    final progress = BoTienTrinhWorldMap(kho: storage);
    addTearDown(progress.dispose);
    await progress.nap(levels);
    expect(progress.tienTrinh.cacManHoanThanh, {1});
    expect(progress.tienTrinh.cacManDaMo, {1, 2});
  });

  test(
    'Lỗi đọc/JSON hiển thị cảnh báo, không mở sẵn màn nào ngoài màn 1',
    () async {
      for (final storage in [
        _KhoNho()..loiDoc = true,
        _KhoNho()..data = 'not-json',
      ]) {
        final progress = BoTienTrinhWorldMap(kho: storage);
        addTearDown(progress.dispose);
        await progress.nap(levels);
        expect(progress.tienTrinh.cacManDaMo, {1});
        expect(progress.loi, isNotEmpty);
      }
    },
  );

  test('Lỗi lưu được báo rõ, lần thử lại lưu được tiến trình', () async {
    final storage = _KhoNho()..loiGhi = true;
    final progress = BoTienTrinhWorldMap(kho: storage);
    addTearDown(progress.dispose);
    await progress.nap(levels);
    expect(await progress.ghiNhanThang(1), isFalse);
    expect(progress.duocChoi(2), isTrue);
    expect(progress.loi, isNotEmpty);
    storage.loiGhi = false;
    expect(await progress.ghiNhanThang(1), isTrue);
    expect(progress.loi, isNull);
    expect(storage.data, contains('1'));
  });

  test(
    'Hai lần hoàn thành liên tiếp được ghi tuần tự, không mất tiến trình mới',
    () async {
      final gate = Completer<void>();
      final storage = _KhoNho()..truocGhi = () => gate.future;
      final progress = BoTienTrinhWorldMap(kho: storage);
      addTearDown(progress.dispose);
      await progress.nap(levels);
      final first = progress.ghiNhanThang(1);
      final second = progress.ghiNhanThang(2);
      gate.complete();
      await Future.wait([first, second]);
      expect(jsonDecode(storage.data!)['hoan_thanh'], [1, 2]);
      expect(storage.daGhi, hasLength(2));
    },
  );

  test(
    'Gameplay từ chối yêu cầu vào màn khóa trước cả khi nạp bản đồ',
    () async {
      final game = GoldRushGame();
      expect(await game.choiMan(levels[1]), isFalse);
      // Không mount Flame, không DB/network/wallet; nếu đụng banDo sẽ ném lỗi.
    },
  );
}
