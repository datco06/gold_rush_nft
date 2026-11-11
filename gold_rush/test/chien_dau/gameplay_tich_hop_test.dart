import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/chien_dau/ki_nang.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/boss.dart';
import 'package:gold_rush/components/dan_ban.dart';
import 'package:gold_rush/components/dong_xu.dart';
import 'package:gold_rush/components/george.dart';
import 'package:gold_rush/components/ke_dich.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/components/vat_pham_roi.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';

Future<ui.Image> _taoAnhGia() async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    const ui.Rect.fromLTWH(0, 0, 128, 128),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return rec.endRecording().toImage(128, 128);
}

BanDo _taoBanDoThu({
  String tep = 'gold_rush.tmx',
  int soXu = 2,
  bool coSkeleton = true,
}) {
  final diem = <DiemXuatHien>[
    DiemXuatHien('george', Vector2(64, 64)),
    for (var i = 0; i < soXu; i++)
      DiemXuatHien('coin', Vector2(96.0 + i * 24, 64)),
    if (coSkeleton) DiemXuatHien('skeleton', Vector2(200, 200)),
  ];
  return BanDo.gia(
    luoi: LuoiVaCham.trong(30, 20),
    diemXuatHien: diem,
    tep: tep,
  );
}

Future<GoldRushGame> _dungGameThu({
  bool batBoss = false,
  BanDo? banDoDau,
  Map<String, BanDo>? cacBanDoKhac,
  List<ManChoi>? danhSachMan,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final anh = await _taoAnhGia();
  final game = GoldRushGame(batBoss: batBoss);
  game.taiNguyen.napTuAnhGia(anh);
  final bd = banDoDau ?? _taoBanDoThu();
  game.khoiTaoChoKiemThu(
    banDoDau: bd,
    cacBanDoKhac: cacBanDoKhac,
    danhSachMan: danhSachMan,
  );
  game.batDauVanMoi();
  return game;
}

void main() {
  test('4. George chết thì thua và dừng ván', () async {
    final game = await _dungGameThu();
    expect(game.trangThai, TrangThaiChoi.dangChoi);

    final g = game.george!;
    g.nhanSatThuong(CauHinh.mauToiDa);

    expect(g.mau, 0);
    expect(g.conSong, isFalse);
    expect(game.trangThai, TrangThaiChoi.thua);
    expect(game.ketQuaVan.value?.thang, isFalse);
  });

  test('5. Hết thời gian thì thua', () async {
    const manCoGio = ManChoi(
      id: 2,
      ten: 'Rừng thưa',
      moTa: 'Thử hết giờ',
      tep: 'man_2.tmx',
      gioiHanGiay: 10,
      heSoKeDich: 1.0,
      coc: 5,
      thuong: 5,
      soXu: 2,
      sao: 2,
    );
    final bd2 = _taoBanDoThu(tep: 'man_2.tmx', soXu: 2);
    final game = await _dungGameThu(banDoDau: bd2, danhSachMan: [manCoGio]);
    await game.choiMan(manCoGio, maVan: 'van-test-het-gio', ve: 1);
    expect(game.trangThai, TrangThaiChoi.dangChoi);
    expect(game.giayConLai, 10);

    game.update(10.5);

    expect(game.giayConLai, 0);
    expect(game.trangThai, TrangThaiChoi.thua);
    expect(game.ketQuaVan.value?.thang, isFalse);
    expect(game.ketQuaVan.value?.matCoc, isTrue);
  });

  test('6 & 7. Nhặt đủ xu nhưng Boss sống thì chưa thắng; hạ Boss sau đó hoặc trước đó đều thắng', () async {
    // Trường hợp A: Nhặt đủ xu trước, hạ Boss sau
    final gameA = await _dungGameThu(batBoss: true);
    final gA = gameA.george!;
    final bossA = gameA.boss!;
    final xuA = gameA.theGioi.children.whereType<DongXu>().toList();
    expect(xuA.length, 2);

    for (final x in xuA) {
      gA.onCollisionStart({}, x);
    }
    expect(gameA.soXuDaNhat, 2);
    expect(bossA.sucKhoe.conSong, isTrue);
    expect(
      gameA.trangThai,
      TrangThaiChoi.dangChoi,
    ); // chưa thắng vì Boss còn sống

    // Hạ Boss
    expect(bossA.nhanSatThuong(CauHinh.mauBoss), isTrue);
    expect(gameA.trangThai, TrangThaiChoi.thang);
    expect(gameA.ketQuaVan.value?.thang, isTrue);
    expect(gameA.ketQuaVan.value?.thongKe['boss_defeated'], isTrue);

    // Trường hợp B: Hạ Boss trước, nhặt xu cuối sau
    final gameB = await _dungGameThu(batBoss: true);
    final gB = gameB.george!;
    final bossB = gameB.boss!;
    final xuB = gameB.theGioi.children.whereType<DongXu>().toList();

    expect(bossB.nhanSatThuong(CauHinh.mauBoss), isTrue);
    expect(gameB.trangThai, TrangThaiChoi.dangChoi); // chưa đủ xu

    for (final x in xuB) {
      gB.onCollisionStart({}, x);
    }
    expect(gameB.trangThai, TrangThaiChoi.thang);
    expect(gameB.ketQuaVan.value?.thang, isTrue);
  });

  test(
    '8. Màn không có Boss vẫn thắng ngay khi nhặt đủ xu theo luật cũ',
    () async {
      final game = await _dungGameThu(batBoss: false);
      expect(game.boss, isNull);
      final g = game.george!;
      final xu = game.theGioi.children.whereType<DongXu>().toList();

      for (final x in xu) {
        g.onCollisionStart({}, x);
      }
      expect(game.trangThai, TrangThaiChoi.thang);
      expect(game.ketQuaVan.value?.thang, isTrue);
    },
  );

  test(
    '9. Đạn không gây sát thương trùng lên cùng mục tiêu hoặc mục tiêu thứ hai',
    () async {
      final game = await _dungGameThu(batBoss: false);
      final bd = game.banDo;
      final z1 = KeDich.zombie(
        banDo: bd,
        hoatAnh: game.taiNguyen.zombie,
        viTri: Vector2(100, 100),
        viTriNguoiChoi: () => Vector2.zero(),
      );
      final z2 = KeDich.zombie(
        banDo: bd,
        hoatAnh: game.taiNguyen.zombie,
        viTri: Vector2(100, 100),
        viTriNguoiChoi: () => Vector2.zero(),
      );
      var soHa = 0;
      final dan = DanBan(
        banDo: bd,
        viTri: Vector2(98, 100),
        huong: Vector2(1, 0),
        satThuong: 10,
        tamBay: 100,
        khiHaMucTieu: (_) => soHa++,
      );

      dan.onCollisionStart({}, z1);
      dan.onCollisionStart({}, z1); // gọi lặp lần 2 trên cùng mục tiêu
      dan.onCollisionStart({}, z2); // chạm mục tiêu thứ 2 trong cùng frame

      expect(z1.sucKhoe.hien, CauHinh.mauZombie - 10);
      expect(z2.sucKhoe.hien, CauHinh.mauZombie); // không bị mất máu
      expect(soHa, 0);
    },
  );

  test('10 & 11. Kỹ năng có cooldown đúng, Shield chặn sát thương và hết hiệu lực đúng hạn', () async {
    final game = await _dungGameThu();
    final g = game.george!;

    // Bật Shield
    expect(g.dungKyNang(LoaiKyNang.shield), isTrue);
    expect(g.kyNang.dangDung(LoaiKyNang.shield), isTrue);
    // Không thể bật lại khi đang hồi
    expect(g.dungKyNang(LoaiKyNang.shield), isFalse);

    // Khi Shield đang bật, George không mất máu khi nhận sát thương
    g.nhanSatThuong(25);
    expect(g.mau, CauHinh.mauToiDa);

    // Sau khi hết thời gian hiệu lực (1.5s), Shield tắt nhưng vẫn đang hồi chiêu (6.0s)
    g.update(1.6);
    expect(g.kyNang.dangDung(LoaiKyNang.shield), isFalse);
    expect(g.dungKyNang(LoaiKyNang.shield), isFalse);

    // Bây giờ nhận sát thương sẽ bị trừ máu
    g.nhanSatThuong(25);
    expect(g.mau, CauHinh.mauToiDa - 25);

    // Sau khi trôi qua đủ thời gian hồi còn lại, dùng lại được Shield
    g.update(4.5);
    expect(g.dungKyNang(LoaiKyNang.shield), isTrue);
  });

  test('12 & 13. Vật phẩm rơi và đồng xu không nhặt trùng; EXP không cộng hai lần cho cùng sự kiện chết', () async {
    final game = await _dungGameThu();
    final g = game.george!;

    // Kiểm tra nhặt vật phẩm rơi nhiều lần trong cùng frame
    final vp = VatPhamRoi(
      phanThuong: const PhanThuong(LoaiVatPham.cucExp, 25),
      viTri: g.position.clone(),
    );
    g.onCollisionStart({}, vp);
    g.onCollisionStart({}, vp);
    expect(g.capDo.currentExp, 25);

    // Kiểm tra đồng xu chạm nhiều lần chỉ cộng điểm 1 lần
    final xu = DongXu(
      hoatAnh: game.taiNguyen.dongXu,
      viTri: g.position.clone(),
    );
    final diemTruoc = g.diem;
    g.onCollisionStart({}, xu);
    g.onCollisionStart({}, xu);
    expect(g.diem, diemTruoc + CauHinh.diemMoiDongXu);

    // Kiểm tra hạ cùng một kẻ địch từ hai đòn/mũi tên đồng thời chỉ cộng EXP 1 lần
    final keDich = game.theGioi.children.whereType<KeDich>().first;
    keDich.position.setFrom(
      g.position + Vector2(0, 12),
    ); // đứng ngay trước mặt George (hướng xuống)
    final expTruoc = g.capDo.currentExp;
    final haTruoc = g.soKeDichDaHa;

    // Hai mũi tên cùng bắn trúng hạ gục mục tiêu
    final d1 = DanBan(
      banDo: game.banDo,
      viTri: keDich.position.clone(),
      huong: Vector2(0, 1),
      satThuong: 100,
      tamBay: 100,
      khiHaMucTieu: g.khiHaMucTieu,
    );
    expect(keDich.nhanSatThuong(100), isTrue);
    expect(keDich.nhanSatThuong(100), isFalse); // lần 2 trả về false

    // Tấn công cận chiến của George hạ quái thực tế
    final quaiMoi = KeDich.skeleton(
      banDo: game.banDo,
      hoatAnh: game.taiNguyen.skeleton,
      viTri: g.position + Vector2(0, 10),
      viTriNguoiChoi: () => g.position,
    );
    await game.theGioi.add(quaiMoi);
    game.theGioi.updateTree(0);

    // Đánh 2 nhát kiếm (mỗi nhát 10 sát thương, skeleton có 20 máu)
    expect(g.tanCong(), isTrue);
    g.update(CauHinh.thoiGianHoiDanh + 0.05);
    expect(g.tanCong(), isTrue);

    expect(quaiMoi.daNo, isTrue);
    expect(g.soKeDichDaHa, haTruoc + 1);
    expect(
      g.capDo.currentExp,
      greaterThanOrEqualTo(expTruoc + CauHinh.expMoiKeDich),
    );
    expect(d1.tuKeDich, isFalse);
  });

  test('14 & 15. Chơi lại không giữ sai trạng thái Boss/kỹ năng; chuyển màn ghi đúng stage_id', () async {
    const man1 = ManChoi.macDinh;
    const man2 = ManChoi(
      id: 2,
      ten: 'Rừng thưa',
      moTa: 'Màn 2',
      tep: 'man_2.tmx',
      gioiHanGiay: 100,
      heSoKeDich: 1.0,
      coc: 5,
      thuong: 5,
      soXu: 2,
      sao: 2,
    );
    final bd1 = _taoBanDoThu(tep: 'gold_rush.tmx', soXu: 2);
    final bd2 = _taoBanDoThu(tep: 'man_2.tmx', soXu: 2);

    final game = await _dungGameThu(
      batBoss: true,
      banDoDau: bd1,
      cacBanDoKhac: {'man_2.tmx': bd2},
      danhSachMan: [man1, man2],
    );

    // Hạ Boss ở ván 1 và bật kỹ năng
    game.george!.dungKyNang(LoaiKyNang.shield);
    game.boss!.nhanSatThuong(CauHinh.mauBoss);
    expect(game.nhatKy.bossDaHa, isTrue);

    // Chơi lại ván mới: Boss được tạo mới đầy máu, bossDaHa reset về false, shield không còn giữ từ ván cũ
    game.batDauVanMoi();
    expect(game.nhatKy.bossDaHa, isFalse);
    expect(game.boss, isNotNull);
    expect(game.boss!.sucKhoe.hien, CauHinh.mauBoss);
    expect(game.george!.kyNang.dangDung(LoaiKyNang.shield), isFalse);

    // Chuyển sang màn 2 và thắng màn 2 -> stage_id phải là 2
    final doiDuoc = await game.choiMan(man2, maVan: 'ma-van-man-2', ve: 3);
    expect(doiDuoc, isTrue);
    expect(game.manHienTai.id, 2);

    game.boss!.nhanSatThuong(CauHinh.mauBoss);
    for (final x in game.theGioi.children.whereType<DongXu>().toList()) {
      game.george!.onCollisionStart({}, x);
    }

    expect(game.trangThai, TrangThaiChoi.thang);
    final kq = game.ketQuaVan.value!;
    expect(kq.stageId, 2);
    expect(kq.maVan, 'ma-van-man-2');
    expect(kq.thongKe['stage_id'], 2);
    expect(kq.thongKe['won'], isTrue);
    expect(kq.thongKe['boss_defeated'], isTrue);
  });

  test(
    '16. Sáu màn TMX hợp lệ, có đủ điểm george, coin và skeleton cho Boss/quái',
    () {
      final ds = ManChoi.docDanhSach(
        File('assets/tiles/man_choi.json').readAsStringSync(),
      );
      expect(ds.map((m) => m.id).toList(), [1, 2, 3, 4, 5, 6]);
      for (final m in ds) {
        final tmx = File('assets/tiles/${m.tep}');
        expect(tmx.existsSync(), isTrue, reason: 'Thiếu ${m.tep}');
        final noiDung = tmx.readAsStringSync();
        expect(noiDung.contains('name="Nen"'), isTrue, reason: m.tep);
        expect(noiDung.contains('name="VaCham"'), isTrue, reason: m.tep);
        expect(noiDung.contains('name="DoiTuong"'), isTrue, reason: m.tep);
        expect(
          RegExp(r'name="george"').allMatches(noiDung).length,
          1,
          reason: m.tep,
        );
        expect(
          RegExp(r'name="coin"').allMatches(noiDung).length,
          m.soXu,
          reason: m.tep,
        );
        expect(
          RegExp(r'name="skeleton"|name="boss"').allMatches(noiDung).length,
          greaterThan(0),
          reason: 'Màn ${m.id} cần ít nhất 1 điểm xuất hiện cho Boss/skeleton',
        );
      }
    },
  );

  test(
    '17. Đổi ván khi component còn trong hàng đợi add thì không bị nhân đôi',
    () async {
      final game = await _dungGameThu(batBoss: true);
      // Không chạy update giữa các lần dựng: các component của ván trước còn trong hàng đợi.
      game.batDauVanMoi();
      game.batDauVanMoi();
      game.update(0);
      game.update(0);

      final con = game.theGioi.children;
      expect(con.whereType<George>().length, 1);
      expect(con.whereType<DongXu>().length, 2);
      expect(con.whereType<Boss>().length, 1);
      expect(con.whereType<KeDich>().length, 1);
      expect(game.tongSoXu, 2);
      expect(game.soXuDaNhat, 0);
    },
  );

  test(
    '18. KetQuaVan.voiPhieu giữ nguyên maVan, thongKe, stageId và kết quả',
    () {
      const kq = KetQuaVan(
        man: ManChoi.macDinh,
        maVan: 'ma-van-x',
        thang: true,
        xu: 3,
        thongKe: {'stage_id': 1, 'won': true},
      );
      final kq2 = kq.voiPhieu('đã có phiếu');
      expect(kq2.maVan, 'ma-van-x');
      expect(kq2.thongKe, kq.thongKe);
      expect(kq2.stageId, 1);
      expect(kq2.thang, isTrue);
      expect(kq2.xu, 3);
      expect(kq2.phieu, 'đã có phiếu');
    },
  );
}
