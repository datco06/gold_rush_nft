import 'abi.dart';
import 'giao_dich.dart';
import 'vi.dart';

/// Một phiếu máy chủ đã ký, chờ nộp lên chuỗi.
class PhieuCho {
  final PhieuVang phieu;
  final String chuKy;

  /// Mã ván dạng chuỗi (UUID) — để xin ký lại khi phiếu hết hạn.
  final String maVan;

  const PhieuCho({required this.phieu, required this.chuKy, required this.maVan});

  bool get coCoc => phieu.ve != BigInt.zero;
}

/// Lớp nói chuyện với hợp đồng `CuaHangGoldRush` (bản 2) qua một [Vi] bất kỳ.
///
/// Không biết gì về MetaMask hay trình duyệt — kiểm thử bằng ví giả trong bộ nhớ
/// (`test/blockchain/cua_hang_test.dart`). Mọi giao dịch đi qua [BoGiaoDich].
class CuaHangChuoi {
  final Vi vi;
  final String hopDong;
  final BoGiaoDich bo;

  /// Phiếu sắp hết hạn trong khoảng này coi như đã hết (thời gian người chơi đọc hộp thoại MetaMask).
  static const Duration bienHan = Duration(seconds: 90);

  const CuaHangChuoi({required this.vi, required this.hopDong, required this.bo});

  Future<String> _doc(String duLieu) => vi.goi(toi: hopDong, duLieu: duLieu);

  Future<BigInt> soVang(String diaChi) async => docUint256(await _doc(maHoaBalanceOf(diaChi, 0)));

  Future<bool> coNhanVat(String diaChi, int id) async =>
      docUint256(await _doc(maHoaBalanceOf(diaChi, id))) > BigInt.zero;

  Future<BigInt> gia(int id) async => docUint256(await _doc(maHoaGia(id)));

  Future<bool> daDoi(String maVanBytes32) async =>
      docUint256(await _doc(maHoaDaDoi(maVanBytes32))) != BigInt.zero;

  Future<VeVaoMan> veCua(String diaChi) async => docVe(await _doc(maHoaVe(diaChi)));

  /// (cọc, trần vàng mỗi phiếu) của một màn trên hợp đồng.
  Future<(BigInt, BigInt)> manChoi(int id) async {
    final w = docCacUint256(await _doc(maHoaManChoi(id)), 2);
    return (w[0], w[1]);
  }

  /// Giữ lại các phiếu CÒN nộp được: đúng ví, còn hạn, chưa nhận, và (màn có cọc) đúng vé đang mở.
  Future<List<PhieuCho>> locPhieuDungDuoc(
    String diaChi,
    List<PhieuCho> ds,
    VeVaoMan ve, {
    DateTime? bayGio,
  }) async {
    final han = (bayGio ?? DateTime.now()).add(bienHan).millisecondsSinceEpoch ~/ 1000;
    final ra = <PhieuCho>[];
    final daThay = <String>{};
    for (final p in ds) {
      final q = p.phieu;
      if (q.nguoiChoi.toLowerCase() != diaChi.toLowerCase()) continue;
      if (q.hanChot < BigInt.from(han)) continue;
      if (!daThay.add(q.maVan.toLowerCase())) continue; // trùng phiếu
      if (p.coCoc && (q.ve != BigInt.from(ve.so) || q.man != BigInt.from(ve.man))) continue;
      if (await daDoi(q.maVan)) continue;
      ra.add(p);
    }
    return ra;
  }

  /// Làm một việc trên chuỗi, GỘP các phiếu đang chờ vào cùng giao dịch:
  ///   * chỉ [phieu]                → nhận vàng;
  ///   * [phieu] + [vaoMan]         → nhận vàng rồi vào màn (đốt cọc) — vé cũ được nhận TRƯỚC khi bị thay;
  ///   * [phieu] + [muaNhanVat]     → nhận vàng rồi mua.
  /// Một lệnh thì gọi thẳng; nhiều lệnh thì `multicall` — MetaMask chỉ hỏi MỘT lần, và nếu một phần
  /// thất bại thì cả giao dịch hoàn tác (không bao giờ "đã trừ cọc mà chưa nhận được phiếu").
  Future<KetQuaGui> thucHien({
    required String diaChi,
    List<PhieuCho> phieu = const [],
    int? vaoMan,
    int? muaNhanVat,
    BaoTienDo? baoTienDo,
  }) async {
    // Đọc trạng thái trên ĐÚNG mạng: người chơi có thể vừa đổi mạng trong MetaMask.
    await bo.damBaoMang();
    await bo.kiemHopDong();
    final ve = await veCua(diaChi);
    final hopLe = await locPhieuDungDuoc(diaChi, phieu, ve);
    var vangSau = await soVang(diaChi);
    for (final p in hopLe) {
      vangSau += p.phieu.soVang + (p.coCoc ? ve.coc : BigInt.zero);
    }

    if (muaNhanVat != null) {
      final g = await gia(muaNhanVat);
      if (g == BigInt.zero) throw const LoiVi('Nhân vật này chưa được bán.');
      if (await coNhanVat(diaChi, muaNhanVat)) throw const LoiVi('Bạn đã có nhân vật này.');
      if (vangSau < g) throw LoiVi('Chưa đủ vàng: cần $g, có $vangSau.');
    }
    if (vaoMan != null) {
      final (coc, tran) = await manChoi(vaoMan);
      if (tran == BigInt.zero) {
        throw LoiVi('Màn $vaoMan chưa được mở trên hợp đồng (chạy lại lệnh ignition deploy).');
      }
      if (coc == BigInt.zero) throw const LoiVi('Màn luyện tập không cần vé.');
      if (vangSau < coc) throw LoiVi('Chưa đủ vàng để đặt cọc: cần $coc, có $vangSau.');
    }

    final lenh = [
      for (final p in hopLe) maHoaNhanVang(p.phieu, p.chuKy),
      if (vaoMan != null) maHoaVaoMan(vaoMan),
      if (muaNhanVat != null) maHoaMua(muaNhanVat),
    ];
    if (lenh.isEmpty) return KetQuaGui.daXongTuTruoc; // mọi phiếu đã được nhận từ trước

    final moTa = [
      if (hopLe.isNotEmpty) 'nhận ${hopLe.length} phiếu vàng',
      if (vaoMan != null) 'vào màn $vaoMan',
      if (muaNhanVat != null) 'mua nhân vật',
    ].join(' + ');

    /// Trạng thái đích trên chuỗi — dùng để (1) không gửi lại việc đã xong, (2) nhận ra giao dịch
    /// đã vào khối dưới một mã khác (người chơi bấm "Tăng tốc" trong MetaMask).
    Future<bool> daXong() async {
      for (final p in hopLe) {
        if (!await daDoi(p.phieu.maVan)) return false;
      }
      if (vaoMan != null) {
        final v = await veCua(diaChi);
        if (!(v.dangMo && v.man == vaoMan && v.so != ve.so)) return false;
      }
      if (muaNhanVat != null && !await coNhanVat(diaChi, muaNhanVat)) return false;
      return true;
    }

    return bo.gui(
      tu: diaChi,
      duLieu: lenh.length == 1 ? lenh.single : maHoaMulticall(lenh),
      moTa: moTa,
      daXong: daXong,
      baoTienDo: baoTienDo,
    );
  }
}
