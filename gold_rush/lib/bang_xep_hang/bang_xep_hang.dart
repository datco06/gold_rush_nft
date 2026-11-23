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
    if (_tuSoHuu) _client.close();
  }

  Future<BangTongThe> taiTongThe() async {
    try {
      if (_tongTheDangTai == null) {
        late final Future<http.Response> request;
        request = _client
            .get(
              _mayChu.resolve('/api/bang-xep-hang/tong-the'),
              headers: const {'Accept': 'application/json'},
            )
            .whenComplete(() {
              if (identical(_tongTheDangTai, request)) _tongTheDangTai = null;
            });
        _tongTheDangTai = request;
      }
      final response = await _tongTheDangTai!.timeout(thoiGianCho);
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
