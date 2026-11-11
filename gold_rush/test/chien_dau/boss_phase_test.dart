import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/boss.dart';
import 'package:gold_rush/components/dan_ban.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';

Future<Map<HuongDi, SpriteAnimation>> _taoHoatAnhGia() async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    const ui.Rect.fromLTWH(0, 0, 64, 64),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final anh = await rec.endRecording().toImage(64, 64);
  SpriteAnimation hang(int i) => SpriteAnimation.fromFrameData(
        anh,
        SpriteAnimationData.sequenced(
          amount: 4,
          amountPerRow: 4,
          stepTime: 0.1,
          textureSize: Vector2.all(16),
          texturePosition: Vector2(0, i * 16.0),
        ),
      );
  return {
    HuongDi.xuong: hang(0),
    HuongDi.trai: hang(1),
    HuongDi.phai: hang(2),
    HuongDi.len: hang(3),
  };
}

void main() {
  const max = 300;

  test('trên 50% là phase 1', () {
    expect(xacDinhPhase(300, max), PhaseBoss.mot);
    expect(xacDinhPhase(151, max), PhaseBoss.mot);
  });

  test('đúng 50% chuyển sang phase 2', () {
    expect(xacDinhPhase(150, max), PhaseBoss.hai);
    expect(xacDinhPhase(61, max), PhaseBoss.hai);
  });

  test('từ 20% trở xuống là phase 3', () {
    expect(xacDinhPhase(60, max), PhaseBoss.ba);
    expect(xacDinhPhase(1, max), PhaseBoss.ba);
    expect(xacDinhPhase(0, max), PhaseBoss.ba);
  });

  test('Boss chuyển phase đúng ngưỡng HP và không kích hoạt phase lặp lại', () async {
    final hoatAnh = await _taoHoatAnhGia();
    final banDo = BanDo.gia(luoi: LuoiVaCham.trong(20, 20));
    final cacPhase = <PhaseBoss>[];
    final boss = Boss(
      banDo: banDo,
      hoatAnh: hoatAnh,
      viTri: Vector2(100, 100),
      viTriNguoiChoi: () => Vector2(100, 100),
      gayDame: (_) {},
    )..khiDoiPhase = cacPhase.add;

    expect(boss.phase, PhaseBoss.mot);
    expect(boss.nhanSatThuong(149), isFalse); // còn 151 HP (> 50%)
    expect(boss.phase, PhaseBoss.mot);
    expect(cacPhase, isEmpty);

    expect(boss.nhanSatThuong(1), isFalse); // còn 150 HP (đúng 50%)
    expect(boss.phase, PhaseBoss.hai);
    expect(cacPhase, [PhaseBoss.hai]);

    // Update nhiều khung hình vẫn không gọi khiDoiPhase lặp lại
    boss.update(0.1);
    boss.update(0.1);
    expect(cacPhase, [PhaseBoss.hai]);

    expect(boss.nhanSatThuong(90), isFalse); // còn 60 HP (đúng 20%)
    expect(boss.phase, PhaseBoss.ba);
    expect(cacPhase, [PhaseBoss.hai, PhaseBoss.ba]);
  });

  test('Boss chết đúng một lần và không gây sát thương hay bắn đạn sau khi chết', () async {
    final hoatAnh = await _taoHoatAnhGia();
    final banDo = BanDo.gia(luoi: LuoiVaCham.trong(20, 20));
    final cha = Component();
    var soLanChet = 0;
    var satThuongGayRa = 0;

    final boss = Boss(
      banDo: banDo,
      hoatAnh: hoatAnh,
      viTri: Vector2(100, 100),
      viTriNguoiChoi: () => Vector2(105, 100),
      gayDame: (d) => satThuongGayRa += d,
      khiChet: (_) => soLanChet++,
    );
    await cha.add(boss);

    // Đưa xuống phase 3 (<= 60 HP) và kích hoạt gồng chiêu diện rộng
    boss.nhanSatThuong(250);
    expect(boss.phase, PhaseBoss.ba);
    boss.update(2.0); // kích hoạt gồng chiêu (_gongChieu = 1.0)

    // Hạ gục Boss ngay khi đang gồng chiêu
    expect(boss.nhanSatThuong(100), isTrue);
    expect(boss.daChet, isTrue);
    expect(soLanChet, 1);

    // Gọi nhanSatThuong thêm nhiều lần nữa không kích hoạt khiChet lặp lại
    expect(boss.nhanSatThuong(50), isFalse);
    expect(boss.nhanSatThuong(10), isFalse);
    expect(soLanChet, 1);

    // Update sau khi chết: không nổ chiêu diện rộng, không bắn thêm đạn
    final soDanTruoc = cha.children.whereType<DanBan>().length;
    boss.update(1.5);
    boss.update(5.0);
    expect(satThuongGayRa, 0);
    expect(cha.children.whereType<DanBan>().length, soDanTruoc);
  });

  test('Boss không đi xuyên tường hoặc ra ngoài bản đồ', () async {
    final hoatAnh = await _taoHoatAnhGia();
    final chan = List.generate(10, (y) => List.generate(10, (x) => x == 5));
    final banDo = BanDo.gia(luoi: LuoiVaCham(chan));
    final boss = Boss(
      banDo: banDo,
      hoatAnh: hoatAnh,
      viTri: Vector2(3 * 16.0, 5 * 16.0),
      viTriNguoiChoi: () => Vector2(8 * 16.0, 5 * 16.0), // bên kia bức tường x=5
      gayDame: (_) {},
    );

    for (var i = 0; i < 60; i++) {
      boss.update(0.05);
    }
    // Cột 5 (x từ 80..96) là tường, hộp chân Boss không được vượt qua x = 80
    expect(boss.position.x, lessThan(5 * 16.0));
  });
}
