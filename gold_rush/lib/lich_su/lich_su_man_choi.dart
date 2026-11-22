import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local play history only, never evidence for rewards or stage ownership.
class VanDaChoi {
  const VanDaChoi({
    required this.maVan,
    required this.manId,
    required this.tenMan,
    required this.thang,
    required this.giay,
    required this.ketThuc,
  });

  final String maVan;
  final int manId;
  final String tenMan;
  final bool thang;
  final double giay;
  final DateTime ketThuc;

  factory VanDaChoi.tuJson(Object? raw) {
    if (raw is! Map ||
        raw['ma_van'] is! String ||
        (raw['ma_van'] as String).isEmpty ||
        raw['man_id'] is! int ||
        (raw['man_id'] as int) < 1 ||
        raw['ten_man'] is! String ||
        (raw['ten_man'] as String).isEmpty ||
        raw['thang'] is! bool ||
        raw['giay'] is! num ||
        !(raw['giay'] as num).isFinite ||
        (raw['giay'] as num) < 0 ||
        raw['ket_thuc'] is! String) {
      throw const FormatException('Invalid play history entry');
    }
    final time = DateTime.tryParse(raw['ket_thuc'] as String);
    if (time == null) throw const FormatException('Invalid completion time');
    return VanDaChoi(
      maVan: raw['ma_van'] as String,
      manId: raw['man_id'] as int,
      tenMan: raw['ten_man'] as String,
      thang: raw['thang'] as bool,
      giay: (raw['giay'] as num).toDouble(),
      ketThuc: time.toUtc(),
    );
  }

  Map<String, Object> thanhJson() => {
    'ma_van': maVan,
    'man_id': manId,
    'ten_man': tenMan,
    'thang': thang,
    'giay': giay,
    'ket_thuc': ketThuc.toUtc().toIso8601String(),
  };
}

class LuuLichSuManChoi {
  LuuLichSuManChoi({
    required String wallet,
    required int chainId,
    Future<String?> Function(String)? doc,
    Future<void> Function(String, String)? ghi,
  }) : _khoa =
           'gold_rush.history.v1.$chainId.${Uri.encodeComponent(wallet.toLowerCase())}',
       _doc = doc ?? ((key) => SharedPreferencesAsync().getString(key)),
       _ghi =
           ghi ??
           ((key, value) => SharedPreferencesAsync().setString(key, value));

  final String _khoa;
  final Future<String?> Function(String) _doc;
  final Future<void> Function(String, String) _ghi;
  static final _hangDoi = <String, Future<void>>{};

  static List<VanDaChoi> _giaiMa(String? raw) {
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['phien_ban'] != 1 || data['cac_van'] is! List) {
        return [];
      }
      final ids = <String>{};
      final result = <VanDaChoi>[];
      for (final entry in data['cac_van'] as List) {
        try {
          final van = VanDaChoi.tuJson(entry);
          if (ids.add(van.maVan)) result.add(van);
        } on FormatException {
          /* Skip only the damaged entry. */
        }
      }
      return _moiNhat(result);
    } on FormatException {
      return [];
    }
  }

  static List<VanDaChoi> _moiNhat(List<VanDaChoi> entries) {
    entries.sort((a, b) => b.ketThuc.compareTo(a.ketThuc));
    return List.unmodifiable(entries.take(100));
  }

  Future<List<VanDaChoi>> doc() async {
    await _hangDoi[_khoa];
    try {
      return _giaiMa(await _doc(_khoa));
    } on Object {
      return [];
    }
  }

  Future<void> ghi(VanDaChoi van) {
    final future = (_hangDoi[_khoa] ?? Future<void>.value()).then((_) async {
      try {
        // Validate before writing even if the caller constructed the record.
        VanDaChoi.tuJson(van.thanhJson());
        final old = _giaiMa(await _doc(_khoa));
        if (old.any((v) => v.maVan == van.maVan)) return;
        final entries = _moiNhat([van, ...old]);
        await _ghi(
          _khoa,
          jsonEncode({
            'phien_ban': 1,
            'cac_van': [for (final entry in entries) entry.thanhJson()],
          }),
        );
      } on Object {
        // Local history must never block results or the existing reward flow.
      }
    });
    _hangDoi[_khoa] = future;
    return future.whenComplete(() {
      if (identical(_hangDoi[_khoa], future)) _hangDoi.remove(_khoa);
    });
  }
}
