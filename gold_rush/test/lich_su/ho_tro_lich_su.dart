import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';

class AuthLichSu extends ChangeNotifier implements AuthController {
  String wallet = '0x${'a' * 40}';
  int chain = 31337;
  bool allowed = true;
  AuthStatus phase = AuthStatus.authenticated;
  bool pendingLogout = false;
  @override
  bool get canEnterGame => allowed;
  @override
  AuthStatus get status => phase;
  @override
  bool get logoutPending => pendingLogout;
  @override
  String get walletAddress => wallet;
  @override
  BigInt get chainId => BigInt.from(chain);
  @override
  String? get csrfToken => null;
  @override
  Null get user => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected auth action: ${invocation.memberName}',
  );
  void thayDoi() => notifyListeners();
}

Future<GoldRushGame> gameLichSu(AuthLichSu auth, {int gioiHan = 0}) async {
  final picture = ui.PictureRecorder();
  ui.Canvas(picture)
      .drawRect(const ui.Rect.fromLTWH(0, 0, 128, 128), ui.Paint());
  final image = await picture.endRecording().toImage(128, 128);
  final game = GoldRushGame(auth: auth, batBoss: false);
  game.taiNguyen.napTuAnhGia(image);
  game.khoiTaoChoKiemThu(
    banDoDau: BanDo.gia(
      luoi: LuoiVaCham.trong(30, 20),
      diemXuatHien: [
        DiemXuatHien('george', Vector2(64, 64)),
        DiemXuatHien('coin', Vector2(128, 64)),
      ],
    ),
    danhSachMan: [
      ManChoi(
        id: 7,
        ten: 'Rừng thưa',
        moTa: '',
        tep: 'gold_rush.tmx',
        gioiHanGiay: gioiHan,
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
