import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/am_thanh/hieu_ung_am_thanh_van.dart';

class _Player implements AudioPlayer {
  PlayerState trangThai = PlayerState.stopped;
  Completer<void>? choNap;
  bool loiKhiNap = false;
  int soLanNap = 0;
  int soLanPhat = 0;
  int soLanDong = 0;

  @override
  PlayerState get state => trangThai;

  @override
  Future<void> setAudioContext(AudioContext context) async {}

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    expect(mode, ReleaseMode.stop);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSource(Source source) async {
    expect(source, isA<AssetSource>());
    soLanNap++;
    if (loiKhiNap) throw StateError('Không nạp được hiệu ứng');
    await choNap?.future;
  }

  @override
  Future<void> resume() async {
    soLanPhat++;
    trangThai = PlayerState.playing;
  }

  @override
  Future<void> dispose() async {
    soLanDong++;
    trangThai = PlayerState.disposed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Dùng lại một player cho mỗi hiệu ứng và bỏ lượt trùng', () async {
    final players = <_Player>[];
    final hieuUng = HieuUngAmThanhVan(
      taoPlayer: () {
        final player = _Player();
        players.add(player);
        return player;
      },
    );
    await hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    await hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    await hieuUng.phat('dong_xu.wav', amLuong: 0.7);
    expect(players, hasLength(2));
    expect(players.first.soLanPhat, 1);

    players.first.trangThai = PlayerState.completed;
    await hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    expect(players, hasLength(2));
    expect(players.first.soLanNap, 1);
    expect(players.first.soLanPhat, 2);

    await hieuUng.dong();
    await hieuUng.dong();
    await hieuUng.phat('va_cham.wav', amLuong: 0.8);
    expect(players, hasLength(2));
    expect(players.map((player) => player.soLanDong), [1, 1]);
  });

  test('Thoát ván khi đang nạp thì không phát và vẫn dọn player', () async {
    final player = _Player()..choNap = Completer<void>();
    var soPlayer = 0;
    final hieuUng = HieuUngAmThanhVan(
      taoPlayer: () {
        soPlayer++;
        return player;
      },
    );
    final choPhat = hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    await hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    final choDong = hieuUng.dong();
    expect(soPlayer, 1);
    expect(player.soLanDong, 0);
    await hieuUng.phat('va_cham.wav', amLuong: 0.8);
    player.choNap!.complete();
    await choPhat;
    await choDong;
    expect(soPlayer, 1);
    expect(player.soLanPhat, 0);
    expect(player.soLanDong, 1);
  });

  test('Kênh lỗi được dọn và không liên tục tạo lại player', () async {
    final player = _Player()..loiKhiNap = true;
    var soPlayer = 0;
    final hieuUng = HieuUngAmThanhVan(
      taoPlayer: () {
        soPlayer++;
        return player;
      },
    );
    await hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    await hieuUng.phat('buoc_chan.wav', amLuong: 0.35);
    await hieuUng.dong();
    expect(soPlayer, 1);
    expect(player.soLanPhat, 0);
    expect(player.soLanDong, 1);
  });
}
