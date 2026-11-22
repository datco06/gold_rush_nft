import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:gold_rush/blockchain/cua_hang.dart';
import 'package:gold_rush/blockchain/giao_dich.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';

import '../blockchain/vi_gia.dart';
import '../lich_su/ho_tro_lich_su.dart';

export '../lich_su/ho_tro_lich_su.dart' show AuthLichSu;

Future<GoldRushGame> gameSoTay(
  AuthLichSu auth, {
  int manId = 7,
  bool boss = false,
  List<String> quai = const ['zombie'],
}) async {
  final picture = ui.PictureRecorder();
  ui.Canvas(picture)
      .drawRect(const ui.Rect.fromLTWH(0, 0, 128, 128), ui.Paint());
  final image = await picture.endRecording().toImage(128, 128);
  final vi = ViGia(taiKhoan: [auth.wallet], mang: auth.chain);
  final game = GoldRushGame(auth: auth, vi: vi, batBoss: boss);
  final pv = game.phienVi!;
  pv.diaChi = auth.wallet;
  pv.cauHinh = CauHinhChuoi(
    chainId: auth.chain,
    hopDong: hopDongThu,
    hopDongVatPham: hopDongThu,
    trongTai: viThu,
  );
  pv.cuaHang = CuaHangChuoi(
    vi: vi,
    hopDong: hopDongThu,
    bo: BoGiaoDich.choMang(vi: vi, chainId: auth.chain, hopDong: hopDongThu),
  );
  game.taiNguyen.napTuAnhGia(image);
  game.khoiTaoChoKiemThu(
    banDoDau: BanDo.gia(
      luoi: LuoiVaCham.trong(30, 20),
      diemXuatHien: [
        DiemXuatHien('george', Vector2(64, 64)),
        DiemXuatHien('coin', Vector2(128, 64)),
        for (final type in quai) DiemXuatHien(type, Vector2(240, 240)),
      ],
    ),
    danhSachMan: [
      ManChoi(
        id: manId,
        ten: 'Rừng thưa',
        moTa: 'Màn thử',
        tep: 'gold_rush.tmx',
        gioiHanGiay: 100,
        heSoKeDich: 1,
        coc: 0,
        thuong: 0,
        soXu: 1,
        sao: 1,
        chiChoiLocal: true,
      ),
    ],
  );
  return game;
}
