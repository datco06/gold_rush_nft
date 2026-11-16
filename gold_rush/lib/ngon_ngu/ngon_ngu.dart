import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ban_dich.dart';

/// App text only: never changes protocol values, signed messages or game state.
class NgonNgu extends ChangeNotifier {
  NgonNgu({Future<String?> Function()? doc, Future<void> Function(String)? ghi})
    : _doc = doc ?? (() => SharedPreferencesAsync().getString(khoa)),
      _ghi = ghi ?? ((code) => SharedPreferencesAsync().setString(khoa, code));

  static const khoa = 'gold_rush.language.v1';
  static final chung = NgonNgu();
  final Future<String?> Function() _doc;
  final Future<void> Function(String) _ghi;
  String _ma = 'vi';
  int _phien = 0;
  Future<void> _hangDoi = Future<void>.value();
  String get ma => _ma;

  Future<void> nap() async {
    final phien = _phien;
    try {
      final saved = await _doc();
      if (phien == _phien && (saved == 'vi' || saved == 'en')) {
        _ma = saved!;
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable: keep the current in-memory choice.
    }
  }

  Future<bool> doi(String code) async {
    if (code != 'vi' && code != 'en') return false;
    ++_phien;
    _ma = code;
    notifyListeners();
    final done = Completer<bool>();
    _hangDoi = _hangDoi.then((_) async {
      try {
        await _ghi(code);
        done.complete(true);
      } catch (_) {
        done.complete(false);
      }
    });
    return done.future;
  }

  String dich(String source) {
    if (_ma == 'vi') return source;
    final exact = banDichAnh[source];
    if (exact != null) return exact;
    final uppercase = _nhanVietHoa[source];
    if (uppercase != null) return uppercase;
    for (final template in _mauDich) {
      final match = template.pattern.firstMatch(source);
      if (match == null) continue;
      // Substitute in one pass: user-supplied braces/$ are never re-evaluated.
      return template.english.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
        final value = match.group(int.parse(m[1]!) + 1) ?? '';
        return template.translateValues ? (banDichAnh[value] ?? value) : value;
      });
    }
    return source;
  }
}

final _nhanVietHoa = {
  for (final entry in banDichAnh.entries)
    if (!entry.key.contains(RegExp(r'\{\d+\}')))
      entry.key.toUpperCase(): entry.value.toUpperCase(),
};

final _mauDich =
    banDichAnh.entries
        .where((e) => e.key.contains(RegExp(r'\{\d+\}')))
        .map((e) => _MauDich(e.key, e.value))
        .toList()
      ..sort((a, b) => b.literalLength.compareTo(a.literalLength));

class _MauDich {
  _MauDich(String source, this.english)
    : translateValues = _nhanCoThamSo.contains(source),
      literalLength = source.replaceAll(RegExp(r'\{\d+\}'), '').length,
      pattern = RegExp(
        '^${source.splitMapJoin(RegExp(r'\{\d+\}'), onMatch: (_) => '(.*?)', onNonMatch: RegExp.escape)}\u0024',
        dotAll: true,
      );
  final RegExp pattern;
  final String english;
  final bool translateValues;
  final int literalLength;
}

// Only controlled enum/catalog labels are translated inside interpolations.
// Player names, wallet addresses, transaction hashes and AI prose stay verbatim.
const _nhanCoThamSo = {
  'Không thể mở camera: {0}',
  'Độ khó • {0}',
  'Độ khó đề xuất • {0}',
  'Nguồn sinh • {0}',
  'Nguồn đề xuất • {0}',
  'Điểm hiệu suất • {0}',
  'Trạng thái: {0}',
  'Đang trang bị: {0}',
  '{0} (Trống)',
  '{0} (Chưa hỗ trợ)',
  '{0} (Trống — bấm để mở Kho đồ)',
  'MÀN {0} · {1}',
  'Màn phiêu lưu local · {0}',
  'Màn luyện tập · {0}',
  'Màn có đặt cọc · {0}',
  'Bạn nhận được {0} ×{1}.',
};

class PhamViNgonNgu extends InheritedNotifier<NgonNgu> {
  const PhamViNgonNgu({
    super.key,
    required NgonNgu ngonNgu,
    required super.child,
  }) : super(notifier: ngonNgu);

  static NgonNgu of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhamViNgonNgu>()?.notifier ??
      NgonNgu.chung;
}

class ChonNgonNgu extends StatelessWidget {
  const ChonNgonNgu({super.key});

  @override
  Widget build(BuildContext context) {
    final language = PhamViNgonNgu.of(context);
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'vi', label: Text('Tiếng Việt')),
        ButtonSegment(value: 'en', label: Text('English')),
      ],
      selected: {language.ma},
      onSelectionChanged: (values) => unawaited(language.doi(values.single)),
      showSelectedIcon: false,
    );
  }
}

/// Same Text styling and const call sites; only presentation depends on language.
class ChuGame extends StatelessWidget {
  const ChuGame(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.dichNoiDung = true,
  });
  final String data;
  final bool dichNoiDung;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    final language = PhamViNgonNgu.of(context);
    return Text(
      dichNoiDung ? language.dich(data) : data,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
      semanticsLabel: semanticsLabel == null
          ? null
          : language.dich(semanticsLabel!),
    );
  }
}
