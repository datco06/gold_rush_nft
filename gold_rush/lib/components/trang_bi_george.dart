import 'dart:ui';

import 'package:flame/components.dart';

import '../cau_hinh.dart';
import 'nhan_vat.dart';

class _KhongDoi implements Map<HuongDi, SpriteAnimation> {
  const _KhongDoi();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const Map<HuongDi, SpriteAnimation> _chuaTruyen = _KhongDoi();

/// Các lớp sprite trang bị của George. Mỗi món dùng một sheet 4x4 độc lập;
/// component này chỉ lo ghép hình, không thay đổi va chạm hay điều khiển.
class TrangBiGeorge extends Component {
  Map<HuongDi, SpriteAnimation>? vuKhi;
  Map<HuongDi, SpriteAnimation>? giap;
  Map<HuongDi, SpriteAnimation>? giay;

  final SpriteAnimationGroupComponent<HuongDi> _lopVuKhi;
  final SpriteAnimationGroupComponent<HuongDi> _lopGiap;
  final SpriteAnimationGroupComponent<HuongDi> _lopGiay;

  HuongDi _huong = HuongDi.xuong;
  bool _dangDi = false;
  double _thoiGianBan = 0;

  TrangBiGeorge({this.vuKhi, this.giap, this.giay})
      : _lopGiay = _taoLop(giay, priority: -2, offset: const Offset(0, 2)),
        _lopGiap = _taoLop(giap, priority: -1, offset: const Offset(0, 0)),
        _lopVuKhi = _taoLop(vuKhi, priority: 1, offset: const Offset(1.5, 0));

  @override
  Future<void> onLoad() async {
    addAll([_lopGiay, _lopGiap, _lopVuKhi]);
    capNhatHuong(_huong);
    datDangDi(_dangDi);
  }

  static SpriteAnimationGroupComponent<HuongDi> _taoLop(
    Map<HuongDi, SpriteAnimation>? animations, {
    required int priority,
    required Offset offset,
  }) {
    final coHieuLuc = animations != null && animations.isNotEmpty;
    return SpriteAnimationGroupComponent<HuongDi>(
      animations: coHieuLuc ? animations : null,
      current: coHieuLuc && animations.containsKey(HuongDi.xuong)
          ? HuongDi.xuong
          : null,
      position: Vector2(
        CauHinh.kichThuocO / 2 + offset.dx,
        CauHinh.kichThuocO / 2 + offset.dy,
      ),
      size: Vector2.all(CauHinh.kichThuocO),
      anchor: Anchor.center,
      priority: priority,
    );
  }

  void _capNhatHuongLop(
    SpriteAnimationGroupComponent<HuongDi> lop,
    HuongDi huong,
  ) {
    final anims = lop.animations;
    if (anims == null || anims.isEmpty) return;
    if (anims.containsKey(huong)) {
      lop.current = huong;
    }
  }

  void capNhatHuong(HuongDi huong) {
    _huong = huong;
    _capNhatHuongLop(_lopVuKhi, huong);
    _capNhatHuongLop(_lopGiap, huong);
    _capNhatHuongLop(_lopGiay, huong);
  }

  void _capNhatTrangBiLop(
    SpriteAnimationGroupComponent<HuongDi> lop,
    Map<HuongDi, SpriteAnimation>? animations,
  ) {
    final coHieuLuc = animations != null && animations.isNotEmpty;
    lop.animations = coHieuLuc ? animations : null;
    if (coHieuLuc) {
      if (animations.containsKey(_huong)) {
        lop.current = _huong;
      }
      lop.playing = _dangDi;
    } else {
      lop.playing = false;
    }
  }

  void capNhatTrangBi({
    Map<HuongDi, SpriteAnimation>? vuKhi = _chuaTruyen,
    Map<HuongDi, SpriteAnimation>? giap = _chuaTruyen,
    Map<HuongDi, SpriteAnimation>? giay = _chuaTruyen,
  }) {
    if (!identical(vuKhi, _chuaTruyen)) {
      this.vuKhi = vuKhi;
      _capNhatTrangBiLop(_lopVuKhi, vuKhi);
    }
    if (!identical(giap, _chuaTruyen)) {
      this.giap = giap;
      _capNhatTrangBiLop(_lopGiap, giap);
    }
    if (!identical(giay, _chuaTruyen)) {
      this.giay = giay;
      _capNhatTrangBiLop(_lopGiay, giay);
    }
  }

  void datDangDi(bool dangDi) {
    _dangDi = dangDi;
    if (_thoiGianBan <= 0 && _lopVuKhi.animations != null) {
      _lopVuKhi.playing = dangDi;
    }
    if (_lopGiap.animations != null) {
      _lopGiap.playing = dangDi;
    }
    if (_lopGiay.animations != null) {
      _lopGiay.playing = dangDi;
    }
  }

  /// Phát một vòng frame của sheet khi người chơi bấm BẮN.
  void phatBan() {
    _thoiGianBan = 0.24;
    final anims = _lopVuKhi.animations;
    if (anims != null && anims.isNotEmpty) {
      if (anims.containsKey(_huong)) {
        _lopVuKhi.current = _huong;
      }
      _lopVuKhi.playing = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_thoiGianBan <= 0) return;
    _thoiGianBan -= dt;
    if (_thoiGianBan <= 0 && _lopVuKhi.animations != null) {
      _lopVuKhi.playing = _dangDi;
    }
  }
}
