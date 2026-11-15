import 'abi.dart';
import 'giao_dich.dart';
import 'vi.dart';

/// Một phiếu máy chủ đã ký, chờ nộp lên chuỗi.
class PhieuCho {
  final PhieuVang phieu;
  final String chuKy;

  /// Mã ván dạng chuỗi (UUID) — để xin ký lại khi phiếu hết hạn.
  final String maVan;

  const PhieuCho({
    required this.phieu,
    required this.chuKy,
    required this.maVan,
  });

  bool get coCoc => phieu.ve != BigInt.zero;
}

/// Lớp nói chuyện với hợp đồng `CuaHangGoldRush` (bản 2) qua một [Vi] bất kỳ.
///
/// Không biết gì về MetaMask hay trình duyệt — kiểm thử bằng ví giả trong bộ nhớ
/// (`test/blockchain/cua_hang_test.dart`). Mọi giao dịch đi qua [BoGiaoDich].
class CuaHangChuoi {
  final Vi vi;
  final String hopDong;
  final String? hopDongVatPham;
  final BoGiaoDich bo;

  /// Phiếu sắp hết hạn trong khoảng này coi như đã hết (thời gian người chơi đọc hộp thoại MetaMask).
  static const Duration bienHan = Duration(seconds: 90);

  const CuaHangChuoi({
    required this.vi,
    required this.hopDong,
    this.hopDongVatPham,
    required this.bo,
  });

  Future<String> _doc(String duLieu) => vi.goi(toi: hopDong, duLieu: duLieu);

  Future<BigInt> soVang(String diaChi) async =>
      docUint256(await _doc(maHoaBalanceOf(diaChi, 0)));

  Future<bool> coNhanVat(String diaChi, int id) async =>
      docUint256(await _doc(maHoaBalanceOf(diaChi, id))) > BigInt.zero;

  Future<BigInt> gia(int id) async => docUint256(await _doc(maHoaGia(id)));

  Future<BigInt> giaVatPham(int id) async =>
      docUint256(await _doc(maHoaGiaVatPham(id)));

  Future<BigInt> soLuongVatPham(String diaChi, int tokenId) async {
    final nft = hopDongVatPham;
    if (nft == null || nft.isEmpty) {
      throw const LoiVi('Chưa cấu hình địa chỉ hợp đồng NFT vật phẩm.');
    }
    return docUint256(
      await vi.goi(toi: nft, duLieu: maHoaBalanceOf(diaChi, tokenId)),
    );
  }

  Future<bool> daDoi(String maVanBytes32) async =>
      docUint256(await _doc(maHoaDaDoi(maVanBytes32))) != BigInt.zero;

  Future<VeVaoMan> veCua(String diaChi) async =>
      docVe(await _doc(maHoaVe(diaChi)));

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
    final han =
        (bayGio ?? DateTime.now()).add(bienHan).millisecondsSinceEpoch ~/ 1000;
    final ra = <PhieuCho>[];
    final daThay = <String>{};
    for (final p in ds) {
      final q = p.phieu;
      if (q.nguoiChoi.toLowerCase() != diaChi.toLowerCase()) continue;
      if (q.hanChot < BigInt.from(han)) continue;
      if (!daThay.add(q.maVan.toLowerCase())) continue; // trùng phiếu
      if (p.coCoc &&
          (q.ve != BigInt.from(ve.so) || q.man != BigInt.from(ve.man)))
        continue;
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
      if (await coNhanVat(diaChi, muaNhanVat))
        throw const LoiVi('Bạn đã có nhân vật này.');
      if (vangSau < g) throw LoiVi('Chưa đủ vàng: cần $g, có $vangSau.');
    }
    if (vaoMan != null) {
      final (coc, tran) = await manChoi(vaoMan);
      if (tran == BigInt.zero) {
        throw LoiVi(
          'Màn $vaoMan chưa được mở trên hợp đồng (chạy lại lệnh ignition deploy).',
        );
      }
      if (coc == BigInt.zero) throw const LoiVi('Màn luyện tập không cần vé.');
      if (vangSau < coc)
        throw LoiVi('Chưa đủ vàng để đặt cọc: cần $coc, có $vangSau.');
    }

    final lenh = [
      for (final p in hopLe) maHoaNhanVang(p.phieu, p.chuKy),
      if (vaoMan != null) maHoaVaoMan(vaoMan),
      if (muaNhanVat != null) maHoaMua(muaNhanVat),
    ];
    if (lenh.isEmpty)
      return KetQuaGui.daXongTuTruoc; // mọi phiếu đã được nhận từ trước

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
      if (muaNhanVat != null && !await coNhanVat(diaChi, muaNhanVat))
        return false;
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

  /// Mua vật phẩm: burn vàng trong CuaHangGoldRush rồi mint NFT trong
  /// VatPhamGoldRush bằng một giao dịch MetaMask nguyên tử.
  Future<KetQuaGui> muaVatPham({
    required String diaChi,
    required int tokenId,
    int soLuong = 1,
    List<PhieuCho> phieu = const [],
    BaoTienDo? baoTienDo,
  }) async {
    if (soLuong <= 0) throw const LoiVi('Số lượng mua phải lớn hơn 0.');
    final nft = hopDongVatPham;
    if (nft == null || nft.isEmpty) {
      throw const LoiVi(
        'Chưa cấu hình hợp đồng NFT vật phẩm. Đặt HOP_DONG_VAT_PHAM rồi tải lại game.',
      );
    }

    await bo.damBaoMang();
    await bo.kiemHopDong();
    final nftCode = await vi.maHopDong(nft);
    if (nftCode == '0x' ||
        nftCode.isEmpty ||
        RegExp(r'^0x0*$').hasMatch(nftCode)) {
      throw const LoiVi('Không thấy hợp đồng NFT vật phẩm trên mạng hiện tại.');
    }

    final ve = await veCua(diaChi);
    final hopLe = await locPhieuDungDuoc(diaChi, phieu, ve);
    var vangSau = await soVang(diaChi);
    for (final p in hopLe) {
      vangSau += p.phieu.soVang + (p.coCoc ? ve.coc : BigInt.zero);
    }

    final giaMoi = await giaVatPham(tokenId);
    if (giaMoi == BigInt.zero) {
      throw const LoiVi('Vật phẩm này chưa được cấu hình giá trên cửa hàng.');
    }
    final tongGia = giaMoi * BigInt.from(soLuong);
    if (vangSau < tongGia) {
      throw LoiVi('Chưa đủ vàng: cần $tongGia, có $vangSau.');
    }
    final truoc = await soLuongVatPham(diaChi, tokenId);
    final lenh = [
      for (final p in hopLe) maHoaNhanVang(p.phieu, p.chuKy),
      maHoaMuaVatPham(tokenId, soLuong),
    ];

    Future<bool> daXong() async {
      for (final p in hopLe) {
        if (!await daDoi(p.phieu.maVan)) return false;
      }
      return await soLuongVatPham(diaChi, tokenId) >=
          truoc + BigInt.from(soLuong);
    }

    return bo.gui(
      tu: diaChi,
      duLieu: lenh.length == 1 ? lenh.single : maHoaMulticall(lenh),
      moTa: [
        if (hopLe.isNotEmpty) 'nhận ${hopLe.length} phiếu vàng',
        'mua vật phẩm ×$soLuong',
      ].join(' + '),
      daXong: daXong,
      baoTienDo: baoTienDo,
    );
  }
}
