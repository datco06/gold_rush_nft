import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'hieu_ung_am_thanh_van.dart';

/// Lớp bọc quanh flame_audio.
///
/// Vì sao phải bọc lại thay vì gọi thẳng FlameAudio khắp nơi:
///
///  1. Âm thanh là thứ dễ hỏng nhất khi đổi nền tảng. Trình duyệt chặn phát
///     tiếng trước khi người dùng chạm vào trang; máy ảo có khi không có thiết
///     bị ra. Bọc lại thì một lỗi âm thanh không bao giờ làm sập game.
///  2. Bật/tắt nhạc ở màn hình Cài đặt chỉ cần sửa một chỗ.
///  3. Sau này muốn đổi sang gói khác thì chỉ sửa tệp này.
class AmThanh {
  AmThanh._();

  static const _dongXu = 'dong_xu.wav';
  static const _vaCham = 'va_cham.wav';
  static const _buocChan = 'buoc_chan.wav';
  static const _nhacNen = 'nhac_nen.wav';

  static bool batNhac = true;
  static bool batHieuUng = true;

  static bool _dangPhatNhac = false;
  static HieuUngAmThanhVan? _hieuUngVan;
  static Future<void>? _dangDongHieuUng;

  static bool get _dungHieuUngTheoVan =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Trả về hàm dọn hiệu ứng thuộc đúng ván vừa mở.
  static VoidCallback? moHieuUngVan() {
    if (!_dungHieuUngTheoVan) return null;
    if (_hieuUngVan case final cu?) _dongHieuUngVan(cu);
    final moi = HieuUngAmThanhVan();
    _hieuUngVan = moi;
    return () => _dongHieuUngVan(moi);
  }

  static void _dongHieuUngVan(HieuUngAmThanhVan van) {
    if (!identical(_hieuUngVan, van)) return;
    _hieuUngVan = null;
    // Nếu vào lại rất nhanh, đợi player cũ được dọn trước khi phát hiệu ứng mới.
    final dangDong = Future.wait<void>([
      if (_dangDongHieuUng case final cu?) cu,
      van.dong(),
    ]).then<void>((_) {});
    _dangDongHieuUng = dangDong;
    unawaited(
      dangDong.then((_) {
        if (identical(_dangDongHieuUng, dangDong)) _dangDongHieuUng = null;
      }),
    );
  }

  /// Nạp sẵn toàn bộ tệp âm thanh vào bộ nhớ đệm.
  ///
  /// Không nạp trước thì lần phát đầu tiên bị trễ rõ rệt, nghe như game giật.
  static Future<void> napTruoc() async {
    try {
      await FlameAudio.audioCache.loadAll([
        _dongXu,
        _vaCham,
        _buocChan,
        _nhacNen,
      ]);
    } catch (e) {
      debugPrint('Không nạp được âm thanh: $e');
    }
  }

  static Future<void> _phat(String ten, {double amLuong = 1.0}) async {
    if (!batHieuUng) return;
    try {
      if (_dungHieuUngTheoVan) {
        if (_dangDongHieuUng == null) {
          await _hieuUngVan?.phat(ten, amLuong: amLuong);
        }
        return;
      }
      await FlameAudio.play(ten, volume: amLuong);
    } catch (e) {
      debugPrint('Không phát được $ten: $e');
    }
  }

  static void nhatDongXu() => _phat(_dongXu, amLuong: 0.7);

  static void keDichNo() => _phat(_vaCham, amLuong: 0.8);

  static void buocChan() => _phat(_buocChan, amLuong: 0.35);

  /// Nhạc nền chỉ được bật SAU khi người chơi bấm nút, không bật lúc khởi động.
  ///
  /// Trình duyệt chặn mọi âm thanh phát trước thao tác đầu tiên của người dùng
  /// (chính sách autoplay). Gọi ở đây, ngay sau cú chạm vào nút "Chơi", là
  /// thời điểm hợp lệ trên mọi nền tảng.
  static Future<void> batNhacNen() async {
    if (!batNhac || _dangPhatNhac) return;
    try {
      await FlameAudio.bgm.play(_nhacNen, volume: 0.45);
      _dangPhatNhac = true;
    } catch (e) {
      debugPrint('Không phát được nhạc nền: $e');
    }
  }

  static Future<void> dungNhacNen() async {
    if (!_dangPhatNhac) return;
    try {
      await FlameAudio.bgm.stop();
    } catch (e) {
      debugPrint('Không dừng được nhạc nền: $e');
    } finally {
      _dangPhatNhac = false;
    }
  }

  static Future<void> tamDungNhac() async {
    if (!_dangPhatNhac) return;
    try {
      await FlameAudio.bgm.pause();
    } catch (_) {}
  }

  static Future<void> tiepTucNhac() async {
    if (!_dangPhatNhac || !batNhac) return;
    try {
      await FlameAudio.bgm.resume();
    } catch (_) {}
  }

  /// Gọi khi người dùng gạt công tắc ở màn hình Cài đặt.
  static Future<void> datBatNhac(bool bat) async {
    batNhac = bat;
    if (bat) {
      await batNhacNen();
    } else {
      await dungNhacNen();
    }
  }
}
