import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// Mỗi hiệu ứng trong một ván dùng lại đúng một player.
class HieuUngAmThanhVan {
  HieuUngAmThanhVan({AudioPlayer Function()? taoPlayer})
    : _taoPlayer = taoPlayer ?? _taoPlayerMacDinh;

  final AudioPlayer Function() _taoPlayer;
  final Map<String, _KenhHieuUng> _cacKenh = {};
  Future<void>? _dangDong;

  static AudioPlayer _taoPlayerMacDinh() => AudioPlayer()
    ..audioCache = FlameAudio.audioCache
    ..positionUpdater = null;

  Future<void> phat(String tep, {required double amLuong}) async {
    if (_dangDong != null) return;
    final kenh = _cacKenh.putIfAbsent(tep, () => _KenhHieuUng(tep, _taoPlayer));
    await kenh.phat(amLuong);
  }

  Future<void> dong() => _dangDong ??= _dongTatCa();

  Future<void> _dongTatCa() async {
    await Future.wait(_cacKenh.values.map((kenh) => kenh.dong()));
    _cacKenh.clear();
  }
}

class _KenhHieuUng {
  _KenhHieuUng(this.tep, this._taoPlayer);

  final String tep;
  final AudioPlayer Function() _taoPlayer;
  static final _audioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();
  AudioPlayer? _player;
  Future<void>? _dangPhat;
  bool _daDong = false;

  Future<void> phat(double amLuong) async {
    if (_daDong || _dangPhat != null || _player?.state == PlayerState.playing) {
      return;
    }
    final dangPhat = _phat(amLuong);
    _dangPhat = dangPhat;
    try {
      await dangPhat;
    } finally {
      _dangPhat = null;
    }
  }

  Future<void> _phat(double amLuong) async {
    try {
      var player = _player;
      if (player == null) {
        player = _player = _taoPlayer();
        // MediaPlayer báo khi phát xong. ReleaseMode.stop giữ nguồn để phát lại.
        await player.setAudioContext(_audioContext);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(amLuong);
        await player.setSource(AssetSource(tep));
      }
      if (!_daDong) await player.resume();
    } catch (loi) {
      // Dừng kênh lỗi trong ván này để tránh tạo player mới ở mỗi tiếng bước chân.
      _daDong = true;
      debugPrint('Không phát được $tep: $loi');
      await _giaiPhong();
    }
  }

  Future<void> dong() async {
    _daDong = true;
    await _dangPhat;
    await _giaiPhong();
  }

  Future<void> _giaiPhong() async {
    final player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (loi) {
      debugPrint('Không dọn được âm thanh $tep: $loi');
    }
  }
}
