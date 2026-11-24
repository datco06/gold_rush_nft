class DongBangTongThe {
  const DongBangTongThe({
    required this.hang,
    required this.ten,
    required this.level,
    required this.vang,
    required this.huyHieu,
    required this.laBan,
  });
  final int hang;
  final String ten;
  final int level;
  final BigInt vang;
  final List<int> huyHieu;
  final bool laBan;

  factory DongBangTongThe.tuJson(Object? raw) {
    if (raw is! Map ||
        raw['hang'] is! int ||
        (raw['hang'] as int) < 1 ||
        raw['level'] is! int ||
        (raw['level'] as int) < 1 ||
        raw['ten'] is! String ||
        (raw['ten'] as String).trim().isEmpty ||
        raw['vang'] is! String ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw['vang'] as String) ||
        raw['huy_hieu'] is! List ||
        raw['la_ban'] is! bool) {
      throw const FormatException('Invalid overall ranking entry');
    }
    final ids = raw['huy_hieu'] as List;
    if (ids.any((id) => id is! int || id < 1 || id > 5) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid owned badge IDs');
    }
    return DongBangTongThe(
      hang: raw['hang'] as int,
      ten: raw['ten'] as String,
      level: raw['level'] as int,
      vang: BigInt.parse(raw['vang'] as String),
      huyHieu: List.unmodifiable(ids.cast<int>()),
      laBan: raw['la_ban'] as bool,
    );
  }
}

class BangTongThe {
  const BangTongThe({
    required this.chainId,
    required this.viewer,
    required this.capNhatLuc,
    required this.duLieuCu,
    required this.tongNguoi,
    required this.bang,
    required this.ban,
  });
  final int chainId;
  final String viewer;
  final DateTime capNhatLuc;
  final bool duLieuCu;
  final int tongNguoi;
  final List<DongBangTongThe> bang;
  final DongBangTongThe? ban;

  factory BangTongThe.tuJson(Object? raw) {
    if (raw is! Map ||
        raw['chain_id'] is! int ||
        (raw['chain_id'] as int) < 1 ||
        raw['viewer'] is! String ||
        !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(raw['viewer'] as String) ||
        raw['cap_nhat_luc'] is! String ||
        raw['du_lieu_cu'] is! bool ||
        raw['tong_nguoi'] is! int ||
        (raw['tong_nguoi'] as int) < 0 ||
        raw['bang'] is! List) {
      throw const FormatException('Invalid overall ranking');
    }
    final date = raw['cap_nhat_luc'] as String;
    if (!RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(date)) {
      throw const FormatException('Ranking timestamp needs timezone');
    }
    final rows = (raw['bang'] as List).map(DongBangTongThe.tuJson).toList();
    final total = raw['tong_nguoi'] as int;
    final mine = raw['ban'] == null ? null : DongBangTongThe.tuJson(raw['ban']);
    if (rows.length != (total < 30 ? total : 30) ||
        rows.indexed.any((pair) => pair.$2.hang != pair.$1 + 1) ||
        mine != null && (!mine.laBan || mine.hang > total) ||
        rows.where((r) => r.laBan).length > 1) {
      throw const FormatException('Inconsistent Top30 positions');
    }
    return BangTongThe(
      chainId: raw['chain_id'] as int,
      viewer: (raw['viewer'] as String).toLowerCase(),
      capNhatLuc: DateTime.parse(date).toUtc(),
      duLieuCu: raw['du_lieu_cu'] as bool,
      tongNguoi: total,
      bang: List.unmodifiable(rows),
      ban: mine,
    );
  }
}
