import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../man_choi.dart';
import 'tien_trinh_world_map.dart';

abstract interface class KhoTienTrinhLocal {
  Future<String?> doc();
  Future<void> ghi(String noiDung);
}

class KhoTienTrinhPreferences implements KhoTienTrinhLocal {
  const KhoTienTrinhPreferences();
  static const khoa = 'gold_rush.world_map.progress.v1';

  @override
  Future<String?> doc() => SharedPreferencesAsync().getString(khoa);

  @override
  Future<void> ghi(String noiDung) =>
      SharedPreferencesAsync().setString(khoa, noiDung);
}

/// Tiến trình local của thiết bị, không phải quyền sở hữu tài sản/blockchain.
/// Chỉ hoàn thành một màn đã mở mới mở đúng màn kế tiếp trong danh mục.
class BoTienTrinhWorldMap extends ChangeNotifier {
  BoTienTrinhWorldMap({KhoTienTrinhLocal? kho})
    : _kho = kho ?? const KhoTienTrinhPreferences();

  final KhoTienTrinhLocal _kho;
  List<int> _thuTu = const [];
  final Set<int> _hoanThanh = {};
  Future<void>? _dangNap;
  Future<void> _hangDoiGhi = Future.value();
  bool _daTai = false;
  bool _daDong = false;
  String? _loi;

  bool get daTai => _daTai;
  String? get loi => _loi;

  TienTrinhWorldMap get tienTrinh {
    final opened = <int>[];
    for (final id in _thuTu) {
      opened.add(id);
      if (!_hoanThanh.contains(id)) break;
    }
    return TienTrinhWorldMap(
      cacManDaMo: opened,
      cacManHoanThanh: _hoanThanh,
      manHienTai: opened.isEmpty ? null : opened.last,
    );
  }

  bool duocChoi(int id) => _daTai && !_daDong && tienTrinh.daMoMan(id);

  Future<void> nap(List<ManChoi> cacMan) => _dangNap ??= _nap(cacMan);

  Future<void> _nap(List<ManChoi> cacMan) async {
    final ids = cacMan.map((m) => m.id).toList()..sort();
    if (ids.isEmpty || ids.first != 1 || ids.toSet().length != ids.length) {
      throw ArgumentError(
        'Danh mục tiến trình phải bắt đầu từ màn 1, không trùng ID.',
      );
    }
    _thuTu = List.unmodifiable(ids);
    try {
      final raw = await _kho.doc();
      if (_daDong) return;
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map ||
            data['phien_ban'] != 1 ||
            data['hoan_thanh'] is! List ||
            (data['hoan_thanh'] as List).any((v) => v is! int)) {
          throw const FormatException('Tiến trình không hợp lệ.');
        }
        final saved = Set<int>.from(data['hoan_thanh'] as List);
        // Không mở nhảy cóc nếu dữ liệu local có ID lạ hoặc thiếu màn trước đó.
        for (final id in ids) {
          if (!saved.contains(id)) break;
          _hoanThanh.add(id);
        }
      }
    } catch (_) {
      _loi = 'Chưa đọc được tiến trình đã lưu. Tạm bắt đầu từ màn 1.';
    }
    if (_daDong) return;
    _daTai = true;
    notifyListeners();
  }

  Future<bool> ghiNhanThang(int id) async {
    if (!duocChoi(id)) return false;
    _hoanThanh.add(id);
    _loi = null;
    notifyListeners();
    final snapshot = jsonEncode({
      'phien_ban': 1,
      'hoan_thanh': _thuTu.where(_hoanThanh.contains).toList(),
    });
    var saved = true;
    // Ghi tuần tự để một lần lưu cũ không ghi đè tiến trình mới hơn.
    final operation = _hangDoiGhi.then((_) async {
      try {
        await _kho.ghi(snapshot);
        if (!_daDong && _loi != null) {
          _loi = null;
          notifyListeners();
        }
      } catch (_) {
        saved = false;
        if (!_daDong) {
          _loi = 'Đã mở màn tiếp theo trong phiên này nhưng chưa lưu được trên máy.';
          notifyListeners();
        }
      }
    });
    _hangDoiGhi = operation;
    await operation;
    return saved;
  }

  @override
  void dispose() {
    _daDong = true;
    super.dispose();
  }
}
