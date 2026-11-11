import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';

/// Kiểm thử phần tính toán va chạm.
///
/// Chạy: `flutter test`
///
/// Điểm đáng chú ý: các bài kiểm thử này KHÔNG cần nạp tệp .tmx, không cần
/// dựng giao diện, không cần Flame chạy. Đó là phần thưởng cho việc tách
/// `LuoiVaCham` ra khỏi `BanDo` — logic thuần thì kiểm thử được trong vài
/// mili giây.
void main() {
  const o = CauHinh.kichThuocO; // 16

  /// Dựng lưới từ chuỗi cho dễ đọc: '#' là ô chặn, '.' là ô đi được.
  LuoiVaCham tuChuoi(List<String> hang) {
    return LuoiVaCham(
      hang.map((d) => d.split('').map((c) => c == '#').toList()).toList(),
    );
  }

  group('biChanTaiDiem', () {
    final luoi = tuChuoi([
      '....',
      '.##.',
      '....',
    ]);

    test('ô trống thì không chặn', () {
      expect(luoi.biChanTaiDiem(o * 0.5, o * 0.5), isFalse);
    });

    test('ô có tường thì chặn', () {
      expect(luoi.biChanTaiDiem(o * 1.5, o * 1.5), isTrue);
      expect(luoi.biChanTaiDiem(o * 2.5, o * 1.5), isTrue);
    });

    test('ngoài bản đồ luôn coi là chặn', () {
      expect(luoi.biChanTaiDiem(-1, 8), isTrue);
      expect(luoi.biChanTaiDiem(8, -1), isTrue);
      expect(luoi.biChanTaiDiem(o * 4 + 1, 8), isTrue);
      expect(luoi.biChanTaiDiem(8, o * 3 + 1), isTrue);
    });

    test('toạ độ âm KHÔNG bị hiểu nhầm thành ô 0', () {
      // Đây là lỗi thật đã gặp: dùng `~/` thay cho `floor()` thì
      // -1 ~/ 16 == 0, khiến điểm nằm ngoài rìa trái lại tra vào cột 0.
      expect(luoi.biChanTaiDiem(-0.5, o * 0.5), isTrue);
    });

    test('đúng biên giữa hai ô', () {
      // x = 16.0 thuộc về ô số 1, không phải ô số 0.
      expect(luoi.biChanTaiDiem(o, o * 1.5), isTrue); // ô (1,1) là tường
      expect(luoi.biChanTaiDiem(o - 0.01, o * 1.5), isFalse); // ô (0,1) trống
    });
  });

  group('diDuoc', () {
    final luoi = tuChuoi([
      '.....',
      '..#..',
      '.....',
    ]);
    final hop = Vector2(10, 7); // đúng kích thước hộp chân của nhân vật

    test('đứng giữa ô trống thì đi được', () {
      expect(luoi.diDuoc(Vector2(o * 0.5, o * 0.5), hop), isTrue);
    });

    test('đứng đè lên tường thì không đi được', () {
      expect(luoi.diDuoc(Vector2(o * 2.5, o * 1.5), hop), isFalse);
    });

    test('một góc hộp chạm tường là đủ để bị chặn', () {
      // Tâm nằm ở ô trống bên trái tường, nhưng mép phải của hộp (rộng 10)
      // thò sang ô tường.
      final tam = Vector2(o * 2 - 3, o * 1.5); // tường bắt đầu ở x = 32
      expect(luoi.biChanTaiDiem(tam.x, tam.y), isFalse, reason: 'tâm ở ô trống');
      expect(luoi.diDuoc(tam, hop), isFalse, reason: 'mép phải chạm tường');
    });

    test('sát mép tường mà chưa chạm thì vẫn đi được', () {
      final tam = Vector2(o * 2 - 5.5, o * 1.5); // mép phải ở 32 - 0.5
      expect(luoi.diDuoc(tam, hop), isTrue);
    });

    test('ra ngoài bản đồ thì không đi được', () {
      expect(luoi.diDuoc(Vector2(1, o * 0.5), hop), isFalse);
    });
  });

  group('nhinThay', () {
    final luoi = tuChuoi([
      '.....',
      '.....',
      '..#..',
      '.....',
      '.....',
    ]);

    Vector2 tamO(int cx, int cy) => Vector2(cx * o + o / 2, cy * o + o / 2);

    test('không có vật cản thì nhìn thấy', () {
      expect(luoi.nhinThay(tamO(0, 0), tamO(4, 0)), isTrue);
    });

    test('có tường chắn giữa thì không nhìn thấy', () {
      // (2,0) --- (2,4) đi xuyên qua ô tường (2,2)
      expect(luoi.nhinThay(tamO(2, 0), tamO(2, 4)), isFalse);
    });

    test('vòng qua bên cạnh tường thì vẫn nhìn thấy', () {
      expect(luoi.nhinThay(tamO(1, 0), tamO(1, 4)), isTrue);
    });

    test('nhìn chính mình luôn thấy', () {
      final p = tamO(3, 3);
      expect(luoi.nhinThay(p, p.clone()), isTrue);
    });

    test('nhìn ra ngoài bản đồ thì không thấy', () {
      expect(luoi.nhinThay(tamO(0, 0), Vector2(-40, -40)), isFalse);
    });
  });

  group('kích thước', () {
    test('quy đổi số ô sang pixel thế giới', () {
      final luoi = tuChuoi(['....', '....', '....']);
      expect(luoi.soCot, 4);
      expect(luoi.soHang, 3);
      expect(luoi.kichThuoc, Vector2(4 * o, 3 * o));
    });

    test('lưới trống thì không chặn ở đâu cả', () {
      final luoi = LuoiVaCham.trong(5, 5);
      expect(luoi.biChanTaiDiem(o * 2.5, o * 2.5), isFalse);
      expect(luoi.diDuoc(Vector2(o * 2.5, o * 2.5), Vector2(10, 7)), isTrue);
    });
  });

  group('biChanO (cổng cho bộ tìm đường A*)', () {
    final luoi = tuChuoi([
      '.#',
      '..',
    ]);

    test('đọc đúng theo (cột, hàng)', () {
      expect(luoi.biChanO(1, 0), isTrue);
      expect(luoi.biChanO(0, 1), isFalse);
    });

    test('ngoài bản đồ coi như chặn', () {
      expect(luoi.biChanO(-1, 0), isTrue);
      expect(luoi.biChanO(2, 0), isTrue);
      expect(luoi.biChanO(0, 2), isTrue);
    });
  });
}
