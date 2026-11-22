import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Preferences only; these IDs never establish inventory ownership or balances.
class LuaChonKhoDo {
  const LuaChonKhoDo({this.nhanVat, this.trangBi = const {}});
  final String? nhanVat;
  final Map<String, String> trangBi;

  static LuaChonKhoDo tuChuoi(String? raw) {
    if (raw == null) return const LuaChonKhoDo();
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['phien_ban'] != 1) return const LuaChonKhoDo();
      final slots = data['trang_bi'];
      return LuaChonKhoDo(
        nhanVat:
            data['nhan_vat'] is String &&
                (data['nhan_vat'] as String).isNotEmpty
            ? data['nhan_vat'] as String
            : null,
        trangBi: {
          if (slots is Map)
            for (final slot in _cacO)
              if (slots[slot] is String && (slots[slot] as String).isNotEmpty)
                slot: slots[slot] as String,
        },
      );
    } on FormatException {
      return const LuaChonKhoDo();
    }
  }

  String thanhChuoi() =>
      jsonEncode({'phien_ban': 1, 'nhan_vat': nhanVat, 'trang_bi': trangBi});
}

const _cacO = {'vuKhiChinh', 'vuKhiPhu', 'giap', 'giay'};

class LuuLuaChonKhoDo {
  LuuLuaChonKhoDo({
    required String wallet,
    required int chainId,
    Future<String?> Function(String)? doc,
    Future<void> Function(String, String)? ghi,
  }) : _khoa =
           'gold_rush.loadout.v1.$chainId.${Uri.encodeComponent(wallet.toLowerCase())}',
       _doc = doc ?? ((key) => SharedPreferencesAsync().getString(key)),
       _ghi =
           ghi ??
           ((key, value) => SharedPreferencesAsync().setString(key, value));

  final String _khoa;
  final Future<String?> Function(String) _doc;
  final Future<void> Function(String, String) _ghi;
  // Shared across consecutive game instances: a late write from the old login
  // cannot overwrite a newer choice made after logging back in.
  static final _hangDoi = <String, Future<void>>{};

  Future<LuaChonKhoDo> doc() async {
    await _hangDoi[_khoa];
    try {
      return LuaChonKhoDo.tuChuoi(await _doc(_khoa));
    } on Object {
      return const LuaChonKhoDo();
    }
  }

  Future<void> _capNhat(LuaChonKhoDo Function(LuaChonKhoDo) change) {
    final future = (_hangDoi[_khoa] ?? Future<void>.value()).then((_) async {
      try {
        final old = LuaChonKhoDo.tuChuoi(await _doc(_khoa));
        await _ghi(_khoa, change(old).thanhChuoi());
      } on Object {
        // Storage failure must not prevent using the current in-memory selection.
      }
    });
    _hangDoi[_khoa] = future;
    return future.whenComplete(() {
      if (identical(_hangDoi[_khoa], future)) _hangDoi.remove(_khoa);
    });
  }

  Future<void> luuNhanVat(String value) =>
      _capNhat((old) => LuaChonKhoDo(nhanVat: value, trangBi: old.trangBi));

  Future<void> luuOTrangBi(String slot, String? itemId) {
    if (!_cacO.contains(slot)) return Future<void>.value();
    return _capNhat(
      (old) => LuaChonKhoDo(
        nhanVat: old.nhanVat,
        trangBi: {
          for (final entry in old.trangBi.entries)
            if (entry.key != slot && entry.value != itemId)
              entry.key: entry.value,
          if (itemId != null && itemId.isNotEmpty) slot: itemId,
        },
      ),
    );
  }

  Future<void> xoaVatPham(String itemId) => _capNhat(
    (old) => LuaChonKhoDo(
      nhanVat: old.nhanVat,
      trangBi: {
        for (final entry in old.trangBi.entries)
          if (entry.value != itemId) entry.key: entry.value,
      },
    ),
  );
}
