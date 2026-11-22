import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nguon_ban_dich.dart';

/// App text only: never changes protocol values, signed messages or game state.
class NgonNgu extends ChangeNotifier {
  NgonNgu({
    Future<String?> Function()? doc,
    Future<void> Function(String)? ghi,
    NguonBanDich? nguon,
  }) : _nguon = nguon ?? _nguonChung,
       _doc = doc ?? (() => SharedPreferencesAsync().getString(khoa)),
       _ghi = ghi ?? ((code) => SharedPreferencesAsync().setString(khoa, code));

  static const khoa = 'gold_rush.language.v1';
  static final _nguonChung = NguonBanDich();
  static Map<String, String> get hoTro => _nguonChung.cacNgonNgu;
  static final chung = NgonNgu();
  final NguonBanDich _nguon;
  final _cacBanDich = <String, _BanDich>{};
  final Future<String?> Function() _doc;
  final Future<void> Function(String) _ghi;
  String _ma = 'vi';
  int _phien = 0;
  int _lanChon = 0;
  int _lanDaChon = 0;
  final _dangChon = <int, String>{};
  Future<void> _hangDoi = Future<void>.value();
  String get ma => _ma;
  bool _daDong = false;
  Map<String, String> get cacNgonNgu => _nguon.cacNgonNgu;

  Future<void> chuanBi() async {
    try {
      await _nguon.nap();
      if (!_daDong) notifyListeners();
    } on Object {
      // Keep Vietnamese usable when the bundled language manifest is missing.
    }
  }

  Future<void> nap() async {
    final phien = _phien;
    try {
      await _nguon.nap();
      final saved = await _doc();
      if (!_daDong && phien == _phien) {
        if (cacNgonNgu.containsKey(saved)) {
          _ma = saved!;
        } else if (_phien == 0) {
          _ma = _nguon.macDinh;
        }
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable: keep the current in-memory choice.
    }
  }

  Future<bool> doi(String code) async {
    if (_daDong || _nguon.daNap && !cacNgonNgu.containsKey(code)) return false;
    final lan = ++_lanChon;
    if (!_nguon.daNap) {
      _dangChon[lan] = code;
      try {
        await _nguon.nap();
      } on Object {
        _dangChon.remove(lan);
        return false;
      }
      final coLuaChonMoiHon = _dangChon.entries.any(
        (entry) => entry.key > lan && cacNgonNgu.containsKey(entry.value),
      );
      _dangChon.remove(lan);
      if (_daDong ||
          lan < _lanDaChon ||
          coLuaChonMoiHon ||
          !cacNgonNgu.containsKey(code)) {
        return false;
      }
    }
    _lanDaChon = lan;
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
    return _cacBanDich
        .putIfAbsent(
          _ma,
          () => _BanDich({
            ..._nguon.banDich(_nguon.duPhong),
            ..._nguon.banDich(_ma),
          }),
        )
        .dich(source);
  }

  @override
  void dispose() {
    _daDong = true;
    _dangChon.clear();
    super.dispose();
  }
}

class _BanDich {
  _BanDich(Map<String, String> noiDung) : tu = noiDung {
    vietHoa = {
      for (final entry in tu.entries)
        if (!entry.key.contains(RegExp(r'\{\d+\}')))
          entry.key.toUpperCase(): entry.value.toUpperCase(),
    };
    mau =
        tu.entries
            .where((e) => e.key.contains(RegExp(r'\{\d+\}')))
            .map((e) => _MauDich(e.key, e.value))
            .toList()
          ..sort((a, b) => b.literalLength.compareTo(a.literalLength));
  }

  final Map<String, String> tu;
  late final Map<String, String> vietHoa;
  late final List<_MauDich> mau;

  String dich(String source) {
    final exact = tu[source];
    if (exact != null) return exact;
    final uppercase = vietHoa[source];
    if (uppercase != null) return uppercase;
    for (final template in mau) {
      final match = template.pattern.firstMatch(source);
      if (match == null) continue;
      // Substitute in one pass: user-supplied braces/$ are never re-evaluated.
      return template.english.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
        final value = match.group(int.parse(m[1]!) + 1) ?? '';
        return template.translateValues
            ? (tu[value] ?? vietHoa[value] ?? value)
            : value;
      });
    }
    return source;
  }
}

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
    return Semantics(
      label: language.dich('Ngôn ngữ'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF14221B),
          border: Border.all(color: const Color(0x887E7655)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: language.ma,
              dropdownColor: const Color(0xFF14221B),
              borderRadius: BorderRadius.circular(6),
              style: const TextStyle(color: Color(0xFFF1E4C4), fontSize: 13),
              icon: const Icon(
                Icons.language,
                color: Color(0xFFE7D9B2),
                size: 20,
              ),
              items: [
                for (final entry in language.cacNgonNgu.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (code) {
                if (code != null) unawaited(language.doi(code));
              },
            ),
          ),
        ),
      ),
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
