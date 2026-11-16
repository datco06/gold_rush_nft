import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cau_hinh.dart';
import '../ngon_ngu/ngon_ngu.dart';

class LuuHuongDan {
  LuuHuongDan({Future<bool?> Function()? doc, Future<void> Function()? ghi})
    : _doc = doc ?? (() => SharedPreferencesAsync().getBool(khoa)),
      _ghi = ghi ?? (() => SharedPreferencesAsync().setBool(khoa, true));

  static const khoa = 'gold_rush.tutorial.v1';
  static final chung = LuuHuongDan();
  final Future<bool?> Function() _doc;
  final Future<void> Function() _ghi;
  bool _daMoTrongPhien = false;
  bool _dangMo = false;

  Future<bool> nenHienTuDong() async {
    if (_daMoTrongPhien) return false;
    try {
      return await _doc() != true && !_daMoTrongPhien;
    } catch (_) {
      // Storage unavailable: manual replay remains available in settings.
      return false;
    }
  }

  Future<void> danhDauDaXem() async {
    _daMoTrongPhien = true;
    try {
      await _ghi();
    } catch (_) {
      // Keep the session flag even when browser storage is unavailable.
    }
  }
}

/// Owned by the opening screen, so the guide cannot outlive that screen.
class PhienHuongDan {
  PhienHuongDan._(this._route);
  final DialogRoute<void> _route;

  void dong() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_route.isActive) _route.navigator?.removeRoute(_route);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

PhienHuongDan? moHuongDanTanThu(BuildContext context, {LuuHuongDan? luu}) {
  final store = luu ?? LuuHuongDan.chung;
  if (!context.mounted || store._dangMo) return null;
  final language = PhamViNgonNgu.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        PhamViNgonNgu(ngonNgu: language, child: const _HuongDanDialog()),
  );
  store._dangMo = true;
  store._daMoTrongPhien = true;
  unawaited(
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
      store._dangMo = false;
      unawaited(store.danhDauDaXem());
    }),
  );
  return PhienHuongDan._(route);
}

/// The readiness callback keeps delayed storage reads from covering another screen.
class HuongDanLanDau extends StatefulWidget {
  const HuongDanLanDau({
    super.key,
    required this.child,
    this.luu,
    this.sanSang,
  });
  final Widget child;
  final LuuHuongDan? luu;
  final bool Function()? sanSang;
  @override
  State<HuongDanLanDau> createState() => _HuongDanLanDauState();
}

class _HuongDanLanDauState extends State<HuongDanLanDau> {
  PhienHuongDan? _phien;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_moLanDau()));
  }

  Future<void> _moLanDau() async {
    final store = widget.luu ?? LuuHuongDan.chung;
    if (!await store.nenHienTuDong() || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false ||
        !(widget.sanSang?.call() ?? true)) {
      return;
    }
    _phien = moHuongDanTanThu(context, luu: store);
  }

  @override
  void dispose() {
    _phien?.dong();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const _cacBuoc = [
  (
    Icons.home_outlined,
    'Làm quen với sảnh',
    'Từ sảnh, bấm BẮT ĐẦU để mở bản đồ. Hồ sơ hiển thị nhân vật; Kho đồ chứa vật phẩm; Cài đặt cho phép đổi ngôn ngữ và xem lại hướng dẫn.',
  ),
  (
    Icons.map_outlined,
    'Chọn màn chơi đầu tiên',
    'Chọn màn 1 — Đồng cỏ để luyện tập miễn phí, không giới hạn thời gian. Bấm vào địa điểm trên bản đồ để xem mục tiêu và điều kiện vào màn. Hoàn thành màn để mở địa điểm kế tiếp.',
  ),
  (
    Icons.sports_esports_outlined,
    'Điều khiển nhân vật',
    'Máy tính: WASD hoặc phím mũi tên để di chuyển; Space/J để tấn công; Shift/K để lướt; Q để đổi vũ khí. Trên màn hình cảm ứng, dùng cần điều khiển và các nút kỹ năng.',
  ),
  (
    Icons.flag_outlined,
    'Mục tiêu ván chơi',
    'Thu thập đủ xu, sống sót và hạ Boss nếu màn có Boss. Theo dõi thanh máu, số xu còn lại và đồng hồ. Với màn có cọc, chết, hết giờ hoặc bỏ ván sẽ mất cọc; thời hạn máy chủ vẫn chạy khi tạm dừng.',
  ),
  (
    Icons.backpack_outlined,
    'Chuẩn bị cho hành trình',
    'Mở Kho đồ để xem vật phẩm và chọn trang bị đang có. Đọc kỹ số vàng cọc và điều kiện thưởng trước khi xác nhận vào màn. Bạn có thể xem lại hướng dẫn trong Cài đặt bất cứ lúc nào.',
  ),
];

class _HuongDanDialog extends StatefulWidget {
  const _HuongDanDialog();
  @override
  State<_HuongDanDialog> createState() => _HuongDanDialogState();
}

class _HuongDanDialogState extends State<_HuongDanDialog> {
  int _buoc = 0;
  final _cuon = ScrollController();

  void _chuyen(int buoc) {
    setState(() => _buoc = buoc);
    if (_cuon.hasClients) _cuon.jumpTo(0);
  }

  @override
  void dispose() {
    _cuon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buoc = _cacBuoc[_buoc];
    final progress = 'Bước ${_buoc + 1}/5';
    return AlertDialog(
      backgroundColor: CauHinh.mauNen,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: const ChuGame(
        'Hướng dẫn tân thủ',
        style: TextStyle(color: CauHinh.mauChinh, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          controller: _cuon,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChuGame(progress, style: const TextStyle(color: CauHinh.mauChu)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_buoc + 1) / 5,
                color: CauHinh.mauChinh,
                semanticsLabel: PhamViNgonNgu.of(context).dich(progress),
              ),
              const SizedBox(height: 16),
              Icon(buoc.$1, color: CauHinh.mauChinh, size: 40),
              const SizedBox(height: 12),
              ChuGame(
                buoc.$2,
                style: const TextStyle(
                  color: CauHinh.mauChu,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ChuGame(
                buoc.$3,
                style: const TextStyle(color: CauHinh.mauChu, height: 1.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const ChuGame('Bỏ qua'),
        ),
        if (_buoc > 0)
          OutlinedButton(
            onPressed: () => _chuyen(_buoc - 1),
            child: const ChuGame('Quay lại'),
          ),
        FilledButton(
          onPressed: () =>
              _buoc == 4 ? Navigator.of(context).pop() : _chuyen(_buoc + 1),
          child: ChuGame(_buoc == 4 ? 'Hoàn tất' : 'Tiếp theo'),
        ),
      ],
    );
  }
}
