/// Tìm đường A* trên lưới ô — "bộ não" giúp kẻ địch vòng qua tường thay vì
/// dí mặt vào tường.
///
/// Tệp này CỐ Ý không import Flame hay Flutter: nó chỉ nhận một hàm trả lời
/// "ô (cột, hàng) có bị chặn không". Nhờ vậy:
///   * kiểm thử bằng `flutter test` trong vài mili giây (test/ai/tim_duong_test.dart);
///   * dùng lại được cho bất kỳ bản đồ nào, kể cả bản đồ do máy chủ sinh ra.
///
/// Bản tham chiếu bằng Python nằm ở `gold_rush_ai/core/luoi.py`, hàm
/// `tim_duong` — cùng thuật toán, cùng thứ tự láng giềng, cùng cách phá thế
/// hoà, nên hai bên cho CÙNG một đường đi. Sửa bên này thì sửa cả bên kia.
library;

/// Một ô trên lưới. Dùng `record` của Dart 3 để có sẵn `==` và `hashCode`.
typedef O = ({int cot, int hang});

/// Thứ tự láng giềng: phải, trái, xuống, lên — PHẢI giống bản Python.
const List<(int, int)> _langGieng = [(1, 0), (-1, 0), (0, 1), (0, -1)];

class TimDuong {
  final int soCot;
  final int soHang;

  /// Trả về true nếu ô bị chặn. Ô ngoài bản đồ được coi là chặn ở đây,
  /// không phụ thuộc vào hàm được truyền vào.
  final bool Function(int cot, int hang) _biChan;

  /// Số ô tối đa được xét trong một lần tìm. Bản đồ 40×30 = 1.200 ô nên
  /// 2.000 là dư; giới hạn này chặn trường hợp xấu nhất không làm khựng game.
  final int gioiHanO;

  TimDuong({
    required this.soCot,
    required this.soHang,
    required this._biChan,
    this.gioiHanO = 2000,
  });

  bool biChan(int cot, int hang) {
    if (cot < 0 || hang < 0 || cot >= soCot || hang >= soHang) return true;
    return _biChan(cot, hang);
  }

  /// Đường đi ngắn nhất (4 hướng) từ [dau] tới [dich].
  ///
  /// Trả về danh sách ô từ SAU ô đầu tới ô đích (rỗng nếu đầu == đích), hoặc
  /// `null` nếu không có đường hoặc đã xét quá [gioiHanO] ô.
  List<O>? tim(O dau, O dich) {
    if (biChan(dau.cot, dau.hang) || biChan(dich.cot, dich.hang)) return null;
    if (dau == dich) return const [];

    int h(O o) => (o.cot - dich.cot).abs() + (o.hang - dich.hang).abs();

    final g = <O, int>{dau: 0};
    final cha = <O, O>{};
    final daDong = <O>{};
    final mo = _DongUuTien()..them(_Nut(h(dau), h(dau), 0, dau));
    var dem = 0;

    while (mo.conPhanTu) {
      final nut = mo.lay();
      final o = nut.o;
      if (daDong.contains(o)) continue; // bản ghi cũ, đã có g tốt hơn
      if (o == dich) return _dungLaiDuong(cha, dau, dich);

      daDong.add(o);
      if (daDong.length > gioiHanO) return null;

      for (final (dx, dy) in _langGieng) {
        final ke = (cot: o.cot + dx, hang: o.hang + dy);
        if (daDong.contains(ke) || biChan(ke.cot, ke.hang)) continue;
        final gMoi = g[o]! + 1;
        if (gMoi < (g[ke] ?? 1 << 30)) {
          g[ke] = gMoi;
          cha[ke] = o;
          dem++;
          mo.them(_Nut(gMoi + h(ke), h(ke), dem, ke));
        }
      }
    }
    return null;
  }

  List<O> _dungLaiDuong(Map<O, O> cha, O dau, O dich) {
    final duong = <O>[dich];
    while (cha.containsKey(duong.last) && cha[duong.last] != dau) {
      duong.add(cha[duong.last]!);
    }
    return duong.reversed.toList();
  }
}

/// Một phần tử trong hàng đợi ưu tiên. So sánh theo f, rồi h, rồi thứ tự vào
/// hàng — đúng như bộ (f, h, dem) trong `heapq` của bản Python.
class _Nut {
  final int f;
  final int h;
  final int thuTu;
  final O o;
  const _Nut(this.f, this.h, this.thuTu, this.o);

  bool nhoHon(_Nut k) {
    if (f != k.f) return f < k.f;
    if (h != k.h) return h < k.h;
    return thuTu < k.thuTu;
  }
}

/// Đống nhị phân (binary heap) tối giản. Dart lõi không có sẵn hàng đợi ưu
/// tiên; gói `collection` có nhưng thêm phụ thuộc chỉ vì 30 dòng thì không đáng.
class _DongUuTien {
  final List<_Nut> _a = [];

  bool get conPhanTu => _a.isNotEmpty;

  void them(_Nut n) {
    _a.add(n);
    var i = _a.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_a[i].nhoHon(_a[p])) break;
      final t = _a[i];
      _a[i] = _a[p];
      _a[p] = t;
      i = p;
    }
  }

  _Nut lay() {
    final dau = _a.first;
    final cuoi = _a.removeLast();
    if (_a.isNotEmpty) {
      _a[0] = cuoi;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < _a.length && _a[l].nhoHon(_a[m])) m = l;
        if (r < _a.length && _a[r].nhoHon(_a[m])) m = r;
        if (m == i) break;
        final t = _a[i];
        _a[i] = _a[m];
        _a[m] = t;
        i = m;
      }
    }
    return dau;
  }
}
