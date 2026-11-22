import 'dart:convert';

import 'package:flutter/services.dart';

/// Bundled UI translations; never loads network URLs or arbitrary file paths.
class NguonBanDich {
  NguonBanDich({Future<String> Function(String)? taiTep})
    : _taiTep = taiTep ?? ((path) => rootBundle.loadString(path));

  final Future<String> Function(String) _taiTep;
  Map<String, String> _cacNgonNgu = const {'vi': 'Tiếng Việt'};
  Map<String, Map<String, String>> _banDich = const {};
  String _macDinh = 'vi';
  String _duPhong = 'en';
  bool _daNap = false;
  Future<void>? _dangNap;

  Map<String, String> get cacNgonNgu => _cacNgonNgu;
  Map<String, String> banDich(String code) => _banDich[code] ?? const {};
  String get macDinh => _macDinh;
  String get duPhong => _duPhong;
  bool get daNap => _daNap;

  Future<void> nap() {
    if (_daNap) return Future<void>.value();
    final dangNap = _dangNap;
    if (dangNap != null) return dangNap;
    final future = _nap();
    _dangNap = future;
    return future.whenComplete(() {
      if (identical(_dangNap, future)) _dangNap = null;
    });
  }

  static Map<String, String> _chuoi(Object? raw) {
    if (raw is! Map ||
        raw.entries.any(
          (e) =>
              e.key is! String ||
              (e.key as String).trim().isEmpty ||
              e.value is! String ||
              (e.value as String).trim().isEmpty,
        )) {
      throw const FormatException(
        'Expected nonempty string translation entries',
      );
    }
    return Map.unmodifiable(Map<String, String>.from(raw));
  }

  static List<String> _thamSo(String value) =>
      RegExp(r'\{\d+\}').allMatches(value).map((m) => m[0]!).toList()..sort();

  Future<Map<String, String>?> _taiBanDich(String code) async {
    try {
      final dictionary = _chuoi(
        jsonDecode(await _taiTep('assets/i18n/$code.json')),
      );
      for (final entry in dictionary.entries) {
        if (_thamSo(entry.key).join(',') != _thamSo(entry.value).join(',')) {
          throw const FormatException('Translation parameters do not match');
        }
      }
      return dictionary;
    } on Object {
      // One damaged locale must not remove the healthy choices.
      return null;
    }
  }

  Future<void> _nap() async {
    final raw = jsonDecode(await _taiTep('assets/i18n/languages.json'));
    if (raw is! Map ||
        raw['default'] is! String ||
        raw['fallback'] is! String) {
      throw const FormatException('Invalid language manifest');
    }
    final declared = _chuoi(raw['languages']);
    final safeCode = RegExp(r'^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$');
    if (!declared.containsKey('vi') ||
        !declared.containsKey(raw['default']) ||
        !declared.containsKey(raw['fallback']) ||
        declared.keys.any((code) => !safeCode.hasMatch(code))) {
      throw const FormatException('Invalid supported language code');
    }
    final codes = declared.keys.toList();
    final loaded = await Future.wait(codes.map(_taiBanDich));
    final dictionaries = <String, Map<String, String>>{};
    final supported = <String, String>{};
    for (var i = 0; i < codes.length; i++) {
      final dictionary = loaded[i];
      if (dictionary != null || codes[i] == 'vi') {
        supported[codes[i]] = declared[codes[i]]!;
        dictionaries[codes[i]] = dictionary ?? const {};
      }
    }
    _cacNgonNgu = Map.unmodifiable(supported);
    _banDich = Map.unmodifiable(dictionaries);
    _macDinh = supported.containsKey(raw['default'])
        ? raw['default'] as String
        : 'vi';
    _duPhong = supported.containsKey(raw['fallback'])
        ? raw['fallback'] as String
        : 'vi';
    _daNap = true;
  }
}
