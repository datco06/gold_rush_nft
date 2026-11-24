import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/http_client_boundary.dart';
import 'tong_the.dart';

enum LoiBangXepHang { dangNhap, ketNoi, mayChu, duLieu }

class LoiTaiBangXepHang implements Exception {
  const LoiTaiBangXepHang(this.loai);
  final LoiBangXepHang loai;
}

int _soNguyen(Object? value, int min, [int? max]) {
  if (value is! int || value < min || max != null && value > max) {
    throw const FormatException('Invalid ranking integer');
  }
  return value;
}

class DongXepHang {
  const DongXepHang({
    required this.hang,
    required this.ten,
    required this.diem,
    required this.giay,
    required this.soMan,
    required this.laBan,
  });
  final int hang;
  final String ten;
  final int diem;
  final double giay;
  final int soMan;
  final bool laBan;

  factory DongXepHang.tuJson(Object? raw) {
    if (raw is! Map ||
        raw['ten'] is! String ||
        (raw['ten'] as String).trim().isEmpty ||
        raw['la_ban'] is! bool ||
        raw['giay'] is! num ||
        !(raw['giay'] as num).isFinite ||
        (raw['giay'] as num) <= 0) {
      throw const FormatException('Invalid ranking entry');
    }
    return DongXepHang(
      hang: _soNguyen(raw['hang'], 1),
      ten: raw['ten'] as String,
      diem: _soNguyen(raw['diem'], 1),
      giay: (raw['giay'] as num).toDouble(),
      soMan: _soNguyen(raw['so_man'], 1, 20),
      laBan: raw['la_ban'] as bool,
    );
  }
}

class BangXepHangTuan {
  const BangXepHangTuan({
    required this.tuan,
    required this.batDau,
    required this.ketThuc,
    required this.chainId,
    required this.viewer,
    required this.man,
    required this.thichUng,
    required this.tongNguoi,
    required this.bang,
    required this.ban,
  });
  final String tuan;
  final DateTime batDau;
  final DateTime ketThuc;
  final int chainId;
  final String viewer;
  final int? man;
  final bool thichUng;
  final int tongNguoi;
  final List<DongXepHang> bang;
  final DongXepHang? ban;

  factory BangXepHangTuan.tuJson(Object? raw) {
    if (raw is! Map ||
        raw['tuan'] is! String ||
        raw['thich_ung'] is! bool ||
        raw['bang'] is! List ||
        (raw['bang'] as List).length > 100 ||
        raw['bat_dau'] is! String ||
        raw['ket_thuc'] is! String) {
      throw const FormatException('Invalid weekly ranking');
    }
    final start = DateTime.parse(raw['bat_dau'] as String).toUtc();
    final viewer = raw['viewer'];
    if (viewer is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(viewer)) {
      throw const FormatException('Invalid ranking viewer');
    }
    final end = DateTime.parse(raw['ket_thuc'] as String).toUtc();
    final total = _soNguyen(raw['tong_nguoi'], 0);
    final rows = (raw['bang'] as List).map(DongXepHang.tuJson).toList();
    final mine = raw['ban'] == null ? null : DongXepHang.tuJson(raw['ban']);
    if (end.difference(start) != const Duration(days: 7) ||
        rows.length > total ||
        rows.any((r) => r.hang > total) ||
        mine != null && (!mine.laBan || mine.hang > total)) {
      throw const FormatException('Inconsistent weekly ranking');
    }
    return BangXepHangTuan(
      tuan: raw['tuan'] as String,
      batDau: start,
      ketThuc: end,
      chainId: _soNguyen(raw['chain_id'], 1),
      viewer: viewer.toLowerCase(),
      man: raw['man'] == null ? null : _soNguyen(raw['man'], 1, 20),
      thichUng: raw['thich_ung'] as bool,
      tongNguoi: total,
      bang: List.unmodifiable(rows),
      ban: mine,
    );
  }
}

class MayChuBangXepHang {
  MayChuBangXepHang({
    String mayChu = const String.fromEnvironment(
      'GOLD_RUSH_API',
      defaultValue: 'http://localhost:8000',
    ),
    http.Client? client,
    this.thoiGianCho = const Duration(seconds: 10),
  }) : _mayChu = Uri.parse(mayChu),
       _client = client ?? taoHttpClientTrinhDuyet(),
       _tuSoHuu = client == null;

  final Uri _mayChu;
  final http.Client _client;
  final bool _tuSoHuu;
  final Duration thoiGianCho;
  Future<http.Response>? _tongTheDangTai;
  Completer<void>? _huyTongThe;
  Completer<void>? _huyCapHoSo;
  String? _phienTongThe;
  int _lanTongThe = 0;

  Future<BangXepHangTuan> tai({int? man, bool thichUng = false}) async {
    try {
      final uri = _mayChu
          .resolve('/api/bang-xep-hang/tuan')
          .replace(
            queryParameters: {
              if (man != null) 'man': '$man',
              'thich_ung': '$thichUng',
              'top': '100',
            },
          );
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(thoiGianCho);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.dangNhap);
      }
      if (response.statusCode != 200) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.mayChu);
      }
      return BangXepHangTuan.tuJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } on LoiTaiBangXepHang {
      rethrow;
    } on FormatException {
      throw const LoiTaiBangXepHang(LoiBangXepHang.duLieu);
    } catch (_) {
      throw const LoiTaiBangXepHang(LoiBangXepHang.ketNoi);
    }
  }

  void dong() {
    huyTaiTongThe();
    if (_tuSoHuu) _client.close();
  }

  void huyTaiTongThe() {
    _lanTongThe++;
    if (_huyCapHoSo case final trigger? when !trigger.isCompleted) {
      trigger.complete();
    }
    _huyCapHoSo = null;
    if (_huyTongThe case final trigger? when !trigger.isCompleted) {
      trigger.complete();
    }
    _tongTheDangTai = null;
    _huyTongThe = null;
    _phienTongThe = null;
  }

  Future<int> dongBoCapHoSo({
    required int level,
    required String wallet,
    required int chainId,
    required String csrfToken,
  }) async {
    if (level < 1 || level > 21 || csrfToken.isEmpty || _huyCapHoSo != null) {
      throw const LoiTaiBangXepHang(LoiBangXepHang.duLieu);
    }
    final trigger = Completer<void>();
    final epoch = _lanTongThe;
    _huyCapHoSo = trigger;
    try {
      final request =
          http.AbortableRequest(
              'POST',
              _mayChu.resolve('/api/bang-xep-hang/cap-ho-so'),
              abortTrigger: trigger.future,
            )
            ..headers.addAll({
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'X-CSRF-Token': csrfToken,
            })
            ..body = jsonEncode({
              'level': level,
              'expected_wallet': wallet,
              'expected_chain_id': chainId,
            });
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(thoiGianCho);
      if (epoch != _lanTongThe) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.ketNoi);
      }
      if ([401, 403, 409].contains(response.statusCode)) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.dangNhap);
      }
      if (response.statusCode != 200) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.mayChu);
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map ||
          data['level'] is! int ||
          data['level'] < level ||
          data['level'] > 21) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.duLieu);
      }
      return data['level'] as int;
    } on LoiTaiBangXepHang {
      rethrow;
    } on FormatException {
      throw const LoiTaiBangXepHang(LoiBangXepHang.duLieu);
    } catch (_) {
      throw const LoiTaiBangXepHang(LoiBangXepHang.ketNoi);
    } finally {
      if (!trigger.isCompleted) {
        trigger.complete();
      }
      if (identical(_huyCapHoSo, trigger)) {
        _huyCapHoSo = null;
      }
    }
  }

  Future<BangTongThe> taiTongThe({String? phien}) async {
    try {
      if (_tongTheDangTai != null && _phienTongThe != phien) huyTaiTongThe();
      final lan = _lanTongThe;
      if (_tongTheDangTai == null) {
        final trigger = Completer<void>();
        _huyTongThe = trigger;
        _phienTongThe = phien;
        final call = http.AbortableRequest(
          'GET',
          _mayChu.resolve('/api/bang-xep-hang/tong-the'),
          abortTrigger: trigger.future,
        )..headers['Accept'] = 'application/json';
        late final Future<http.Response> request;
        request = _client
            .send(call)
            .then(http.Response.fromStream)
            .whenComplete(() {
              if (identical(_tongTheDangTai, request)) {
                _tongTheDangTai = null;
                _huyTongThe = null;
                _phienTongThe = null;
              }
            });
        _tongTheDangTai = request;
      }
      final pending = _tongTheDangTai!;
      final trigger = _huyTongThe!;
      final response = await pending.timeout(
        thoiGianCho,
        onTimeout: () {
          if (identical(_tongTheDangTai, pending) && !trigger.isCompleted) {
            trigger.complete();
          }
          throw TimeoutException('Ranking request timed out');
        },
      );
      if (lan != _lanTongThe) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.ketNoi);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.dangNhap);
      }
      if (response.statusCode != 200) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.mayChu);
      }
      return BangTongThe.tuJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } on LoiTaiBangXepHang {
      rethrow;
    } on FormatException {
      throw const LoiTaiBangXepHang(LoiBangXepHang.duLieu);
    } catch (_) {
      throw const LoiTaiBangXepHang(LoiBangXepHang.ketNoi);
    }
  }
}
