import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Informational discoveries only, never ownership or access to a stage.
class SoTayKhamPha {
  SoTayKhamPha({Iterable<String> daMo = const []})
    : daMo = Set.unmodifiable(daMo);
  final Set<String> daMo;
}

class LuuSoTayKhamPha {
  LuuSoTayKhamPha({
    required String wallet,
    required int chainId,
    Future<String?> Function(String)? doc,
    Future<void> Function(String, String)? ghi,
  }) : _khoa =
           'gold_rush.notebook.v1.$chainId.${Uri.encodeComponent(wallet.toLowerCase())}',
       _doc = doc ?? ((key) => SharedPreferencesAsync().getString(key)),
       _ghi =
           ghi ??
           ((key, value) => SharedPreferencesAsync().setString(key, value));

  final String _khoa;
  final Future<String?> Function(String) _doc;
  final Future<void> Function(String, String) _ghi;
  static final _hangDoi = <String, Future<void>>{};
  static final _khoaHopLe = RegExp(
    r'^(dia_diem:[1-9][0-9]{0,3}|quai:(zombie|skeleton|thuong|giap|khong_lo|boss)|trang_bi:[a-z0-9_]{1,80})$',
  );

  static Set<String> _loc(Iterable<Object?> values) => {
    for (final value in values.take(2048))
      if (value is String && _khoaHopLe.hasMatch(value)) value,
  };

  static SoTayKhamPha _giaiMa(String? raw) {
    if (raw == null) return SoTayKhamPha();
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['phien_ban'] == 1 && data['da_mo'] is List) {
        return SoTayKhamPha(daMo: _loc(data['da_mo'] as List));
      }
    } on FormatException {
      /* A damaged notebook must not block play. */
    }
    return SoTayKhamPha();
  }

  Future<SoTayKhamPha> doc() async {
    await _hangDoi[_khoa];
    try {
      return _giaiMa(await _doc(_khoa));
    } on Object {
      return SoTayKhamPha();
    }
  }

  Future<void> ghi(Iterable<String> keys) {
    final moi = _loc(keys);
    if (moi.isEmpty) return Future<void>.value();
    final future = (_hangDoi[_khoa] ?? Future<void>.value()).then((_) async {
      try {
        final old = _giaiMa(await _doc(_khoa)).daMo;
        if (old.containsAll(moi)) return;
        await _ghi(
          _khoa,
          jsonEncode({
            'phien_ban': 1,
            'da_mo': {...old, ...moi}.take(2048).toList(),
          }),
        );
      } on Object {
        /* Keep gameplay independent from local storage. */
      }
    });
    _hangDoi[_khoa] = future;
    return future.whenComplete(() {
      if (identical(_hangDoi[_khoa], future)) _hangDoi.remove(_khoa);
    });
  }
}
