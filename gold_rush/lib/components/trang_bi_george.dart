import 'dart:ui';

import 'package:flame/components.dart';

import '../cau_hinh.dart';
import 'nhan_vat.dart';

/// Các lớp sprite trang bị của George. Mỗi món dùng một sheet 4x4 độc lập;
/// component này chỉ lo ghép hình, không thay đổi va chạm hay điều khiển.
class TrangBiGeorge extends Component {
  final Map<HuongDi, SpriteAnimation>? vuKhi;
  final Map<HuongDi, SpriteAnimation>? giap;
  final Map<HuongDi, SpriteAnimation>? giay;

  late final SpriteAnimationGroupComponent<HuongDi> _lopVuKhi;
  late final SpriteAnimationGroupComponent<HuongDi> _lopGiap;
  late final SpriteAnimationGroupComponent<HuongDi> _lopGiay;

  HuongDi _huong = HuongDi.xuong;
  bool _dangDi = false;
  double _thoiGianBan = 0;

  TrangBiGeorge({this.vuKhi, this.giap, this.giay});

  @override
  Future<void> onLoad() async {
    _lopGiay = _taoLop(giay, priority: -2, offset: const Offset(0, 2));
    _lopGiap = _taoLop(giap, priority: -1, offset: const Offset(0, 0));
    _lopVuKhi = _taoLop(vuKhi, priority: 1, offset: const Offset(1.5, 0));
    addAll([_lopGiay, _lopGiap, _lopVuKhi]);
    capNhatHuong(_huong);
    datDangDi(_dangDi);
  }

  SpriteAnimationGroupComponent<HuongDi> _taoLop(
    Map<HuongDi, SpriteAnimation>? animations, {
    required int priority,
    required Offset offset,
  }) {
    return SpriteAnimationGroupComponent<HuongDi>(
      animations: animations?.isEmpty == true ? null : animations,
      current: _huong,
      position: Vector2(
        CauHinh.kichThuocO / 2 + offset.dx,
        CauHinh.kichThuocO / 2 + offset.dy,
      ),
      size: Vector2.all(CauHinh.kichThuocO),
      anchor: Anchor.center,
      priority: priority,
    );
  }

  void capNhatHuong(HuongDi huong) {
    _huong = huong;
    _lopVuKhi.current = huong;
    _lopGiap.current = huong;
    _lopGiay.current = huong;
  }

  void capNhatTrangBi({
    Map<HuongDi, SpriteAnimation>? vuKhi,
    Map<HuongDi, SpriteAnimation>? giap,
    Map<HuongDi, SpriteAnimation>? giay,
  }) {
    _lopVuKhi.animations = vuKhi?.isEmpty == true ? null : vuKhi;
    _lopGiap.animations = giap?.isEmpty == true ? null : giap;
    _lopGiay.animations = giay?.isEmpty == true ? null : giay;
  }

  void datDangDi(bool dangDi) {
    _dangDi = dangDi;
    if (_thoiGianBan <= 0) {
      _lopVuKhi.playing = dangDi;
    }
    _lopGiap.playing = dangDi;
    _lopGiay.playing = dangDi;
  }

  /// Phát một vòng frame của sheet khi người chơi bấm BẮN.
  void phatBan() {
    _thoiGianBan = 0.24;
    _lopVuKhi
      ..current = _huong
      ..playing = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_thoiGianBan <= 0) return;
    _thoiGianBan -= dt;
    if (_thoiGianBan <= 0) _lopVuKhi.playing = _dangDi;
  }
}
