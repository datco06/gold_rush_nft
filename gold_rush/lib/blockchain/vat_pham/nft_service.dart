import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../abi.dart' as abi;
import '../giao_dich.dart';
import '../loi_hop_dong.dart';
import '../phien_vi.dart';
import '../vi.dart';
import 'nft_model.dart';

class CauHinhNFT {
  final int chainId;
  final String hopDong;
  final String? tenMang;
  final String? rpcUrl;

  CauHinhNFT({
    required this.chainId,
    required this.hopDong,
    this.tenMang,
    this.rpcUrl,
  }) {
    if (chainId <= 0 || chainId > 9007199254740991) {
      throw ArgumentError.value(chainId, 'chainId');
    }
    _kiemDiaChi(hopDong);
  }
}

/// Đúng năm trường PhieuVatPham trong Solidity. Không ký phiếu trong Flutter.
class PhieuVatPham {
  final String player;
  final BigInt tokenId;
  final BigInt amount;
  final String nonce;
  final BigInt deadline;

  PhieuVatPham({
    required this.player,
    required this.tokenId,
    required this.amount,
    required this.nonce,
    required this.deadline,
  }) {
    _kiemDiaChi(player);
    _kiemSoDuong(tokenId);
    _kiemSoDuong(amount);
    abi.tuBytes32(nonce);
    if (!nonce.startsWith('0x')) {
      throw const FormatException('nonce phải có tiền tố 0x');
    }
    abi.tu(deadline);
  }

  factory PhieuVatPham.fromJson(Map<String, dynamic> json) => PhieuVatPham(
    player: _chuoi(json['player']),
    tokenId: _uintJson(json['tokenId']),
    amount: _uintJson(json['amount']),
    nonce: _chuoi(json['nonce']),
    deadline: _uintJson(json['deadline']),
  );

  Map<String, dynamic> toJson() => {
    'player': player,
    'tokenId': tokenId.toString(),
    'amount': amount.toString(),
    'nonce': nonce,
    'deadline': deadline.toString(),
  };
}

/// Đầu vào của adapter API thật: phiếu, chữ ký 65 byte và domain triển khai.
/// Không có endpoint, khóa ký hay thao tác xin phiếu mặc định.
class PhieuVatPhamDaKy {
  final PhieuVatPham phieu;
  final String chuKy;
  final CauHinhNFT cauHinh;

  PhieuVatPhamDaKy({
    required this.phieu,
    required this.chuKy,
    required this.cauHinh,
  }) {
    if (!RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(chuKy)) {
      throw const FormatException('Chữ ký NFT phải có 65 byte (0x + 130 hex)');
    }
  }
}

/// Chỉ chứa thông tin hợp đồng thực sự có; tên/ảnh/category do danh mục cung cấp.
class ThongTinVatPhamNFT {
  final BigInt tokenId;
  final bool registered;
  final BigInt maxSupply;
  final BigInt totalMinted;
  final String? metadataUri;

  const ThongTinVatPhamNFT({
    required this.tokenId,
    required this.registered,
    required this.maxSupply,
    required this.totalMinted,
    this.metadataUri,
  });
}

enum TrangThaiGiaoDichNFT {
  chuaBatDau,
  choXacNhanVi,
  choXacNhanChuoi,
  daXacNhan,
  thanhCong,
  daHuy,
  thatBai,
  hetThoiGianCho,
  duLieuChuaCapNhat,
}

enum NguyenNhanLoiNFT {
  chuaKetNoi,
  saiMang,
  cauHinh,
  chuaSoHuu,
  thieuSoDu,
  duLieu,
}

class LoiNFT extends LoiVi {
  final NguyenNhanLoiNFT nguyenNhan;
  const LoiNFT(super.thongBao, {required this.nguyenNhan, super.loai});
}

/// Giữ hash/receipt khi timeout, đổi ví hoặc lỗi đọc lại sau khi đã gửi.
/// Receipt thành công nhưng model chưa đối chiếu được KHÔNG phải giao dịch revert.
class LoiGiaoDichNFT extends LoiVi {
  final LoiVi loiGoc;
  final String? transactionHash;
  final BienLai? receipt;
  LoiGiaoDichNFT(LoiVi loi, {this.transactionHash, this.receipt})
    : loiGoc = loi,
      super(
        loi.thongBao,
        ma: loi.ma,
        duLieu: loi.duLieu,
        thongDiepGoc: loi.thongDiepGoc,
        loai: loi.loai,
      );
}

class KetQuaGiaoDichNFT {
  final String transactionHash;
  final BienLai receipt;
  final VatPhamNFT vatPham;
  final String? nguoiNhan;
  final BigInt? soDuNguoiNhan;
  const KetQuaGiaoDichNFT({
    required this.transactionHash,
    required this.receipt,
    required this.vatPham,
    this.nguoiNhan,
    this.soDuNguoiNhan,
  });
}

/// Một service cho một cấu hình NFT, dùng đúng phienVi.vi và BoGiaoDich hiện có.
/// Không kết nối ví mới, không gọi API vàng, không ký Backend và không tải JSON URI.
///
/// UI nghe ChangeNotifier và đọc danhSach. Đổi phiên/sự kiện ví lập tức bỏ xác
/// minh; service tự tải lại danh mục trên đúng mạng, không tự mở hộp thoại ví.
/// Model đã trả về là ảnh chụp bất biến: UI phải thay nó bằng danhSach mới.
/// Dispose service trước khi dispose PhienVi; service không sở hữu PhienVi.
class DichVuNFT extends ChangeNotifier {
  final PhienVi phienVi;
  final CauHinhNFT cauHinh;
  final Duration choToiDa;
  final Duration nhipKiemTra;
  final Future<void> Function(Duration)? ngu;
  late final StreamSubscription<SuKienVi> _ngheVi;
  String? _diaChiCu;
  bool _daDong = false;
  int _theHe = 0;
  int _lanTai = 0;
  List<VatPhamNFT> _danhMuc = const [];
  List<VatPhamNFT> _danhSach = const [];
  bool dangTai = false;
  LoiVi? loiTai;
  TrangThaiGiaoDichNFT trangThai = TrangThaiGiaoDichNFT.chuaBatDau;
  String? transactionHash;
  String? _hashDangCho;

  DichVuNFT({
    required this.phienVi,
    required this.cauHinh,
    this.choToiDa = const Duration(minutes: 2),
    this.nhipKiemTra = const Duration(milliseconds: 1500),
    this.ngu,
  }) {
    if (choToiDa <= Duration.zero || nhipKiemTra <= Duration.zero) {
      throw ArgumentError('Thời gian chờ phải lớn hơn 0');
    }
    _diaChiCu = phienVi.diaChi?.toLowerCase();
    phienVi.addListener(_khiPhienDoi);
    _ngheVi = _vi.suKien.listen(
      (_) => _voHieuHoa(),
      onError: (Object error) {
        _voHieuHoa(taiLai: false);
        loiTai = _dichLoi(error);
        _bao();
      },
    );
  }

  Vi get _vi => phienVi.vi;
  bool get coHoTroVi => _vi.coSan;
  List<VatPhamNFT> get danhSach => _danhSach;

  void _bao() {
    if (!_daDong) notifyListeners();
  }

  void _khiPhienDoi() {
    final moi = phienVi.diaChi?.toLowerCase();
    if (moi != _diaChiCu) {
      _diaChiCu = moi;
      _voHieuHoa();
    }
  }

  void _voHieuHoa({bool taiLai = true}) {
    if (_daDong) return;
    _theHe++;
    _lanTai++;
    dangTai = false;
    _danhSach = List.unmodifiable(
      _danhSach.map(
        (v) => v.copyWith(clearBalance: true, clearWalletAddress: true),
      ),
    );
    _bao();
    if (taiLai && _danhMuc.isNotEmpty) {
      final lanDaHen = _lanTai;
      unawaited(
        Future<void>.microtask(() async {
          // Gộp sự kiện dồn dập; không để lượt tự tải thay thế lamMoi của UI.
          if (_daDong || _lanTai != lanDaHen) return;
          try {
            await lamMoi();
          } on LoiVi {
            /* loiTai đã được công bố, không giữ sở hữu cũ. */
          }
        }),
      );
    }
  }

  BoGiaoDich _bo(Vi vi) => BoGiaoDich(
    vi: vi,
    chainId: cauHinh.chainId,
    hopDong: cauHinh.hopDong,
    tenMang: cauHinh.tenMang,
    rpcUrl: cauHinh.rpcUrl,
    choToiDa: choToiDa,
    nhipKiemTra: nhipKiemTra,
    ngu: ngu,
  );

  String _player() {
    if (_daDong) throw const LoiVi('NFT Service đã dispose.');
    if (!coHoTroVi) {
      throw const LoiNFT(
        'Nền tảng chưa hỗ trợ ví; dùng MetaMask Web hiện có.',
        nguyenNhan: NguyenNhanLoiNFT.chuaKetNoi,
      );
    }
    final player = phienVi.diaChi;
    if (player == null) {
      throw const LoiNFT(
        'Chưa kết nối phiên ví.',
        nguyenNhan: NguyenNhanLoiNFT.chuaKetNoi,
      );
    }
    _kiemDiaChi(player);
    return player;
  }

  Future<void> _kiem(_NguCanh ctx) async {
    void kiemPhien() {
      if (_daDong ||
          ctx.theHe != _theHe ||
          phienVi.diaChi?.toLowerCase() != ctx.player.toLowerCase()) {
        throw const _DoiNguCanh(
          LoiVi(
            'Phiên ví đã thay đổi — tải lại NFT cho ví/mạng hiện tại.',
            loai: LoaiLoiVi.doiTaiKhoan,
          ),
        );
      }
    }

    kiemPhien();
    final accounts = await _vi.taiKhoan();
    kiemPhien();
    if (accounts.isEmpty ||
        accounts.first.toLowerCase() != ctx.player.toLowerCase()) {
      throw const _DoiNguCanh(
        LoiVi(
          'Tài khoản MetaMask đã thay đổi hoặc ngắt kết nối.',
          loai: LoaiLoiVi.doiTaiKhoan,
        ),
      );
    }
    final chain = await _vi.chainId();
    kiemPhien();
    if (chain != cauHinh.chainId) {
      throw const _DoiNguCanh(
        LoiNFT(
          'Ví đang sai mạng NFT. Chọn đúng mạng rồi làm mới.',
          nguyenNhan: NguyenNhanLoiNFT.saiMang,
        ),
      );
    }
  }

  Future<String> _goi(_NguCanh ctx, String data) async {
    await _kiem(ctx);
    final result = await _vi.goi(toi: cauHinh.hopDong, duLieu: data);
    await _kiem(ctx);
    return result;
  }

  Future<void> _chuanBi(_NguCanh ctx) async {
    await _kiem(ctx);
    await _bo(_vi).kiemHopDong();
    final typehash = await _goi(ctx, '0x2f4c3b18');
    if (typehash.toLowerCase() !=
            '0x65a15c8a6ba607b7c8d8157a095c5e3b7f1d09047255ca7ca609dd8a79aef887' ||
        !_bool(await _goi(ctx, '0x01ffc9a7d9b67a26${'0' * 56}'))) {
      throw const LoiNFT(
        'Địa chỉ không khớp hợp đồng VatPhamGoldRush ERC-1155.',
        nguyenNhan: NguyenNhanLoiNFT.cauHinh,
      );
    }
    final domain = _than(await _goi(ctx, '0x84b0196e'));
    if (domain.length < 448 ||
        _word(domain, 0) != '0f${'0' * 62}' ||
        _chuoiAbi(domain, 1, 224) != 'GoldRushEquipment' ||
        _chuoiAbi(domain, 2, 224) != '1' ||
        _soWord(domain, 3) != BigInt.from(cauHinh.chainId) ||
        _word(domain, 4) != abi.tuDiaChi(cauHinh.hopDong)) {
      throw const LoiNFT(
        'EIP-712 domain sai tên/version/chainId/hợp đồng NFT.',
        nguyenNhan: NguyenNhanLoiNFT.cauHinh,
      );
    }
  }

  Future<T> _doc<T>(Future<T> Function(_NguCanh) viec) async {
    try {
      final ctx = _NguCanh(_player(), _theHe);
      await _chuanBi(ctx);
      final result = await viec(ctx);
      await _kiem(ctx);
      return result;
    } catch (e) {
      if (e is _DoiNguCanh) {
        _danhSach = List.unmodifiable(
          _danhSach.map(
            (v) => v.copyWith(clearBalance: true, clearWalletAddress: true),
          ),
        );
        _bao();
      }
      throw _dichLoi(e);
    }
  }

  Future<BigInt> _soDu(_NguCanh ctx, BigInt id, {String? wallet}) async {
    _kiemSoDuong(id);
    return _uint(
      await _goi(
        ctx,
        '0x${abi.chonBalanceOf}${abi.tuDiaChi(wallet ?? ctx.player)}${abi.tu(id)}',
      ),
    );
  }

  Future<BigInt> docSoDu(BigInt tokenId) => _doc((ctx) => _soDu(ctx, tokenId));
  Future<List<BigInt>> docSoDuBatch(List<BigInt> tokenIds) =>
      _doc((ctx) => _batch(ctx, List.of(tokenIds)));

  Future<List<BigInt>> _batch(_NguCanh ctx, List<BigInt> ids) async {
    for (final id in ids) {
      _kiemSoDuong(id);
    }
    if (ids.isEmpty) return const [];
    final n = BigInt.from(ids.length);
    final data =
        '0x4e1273f4${abi.tu(BigInt.from(64))}${abi.tu(BigInt.from(96) + n * BigInt.from(32))}'
        '${abi.tu(n)}${List.filled(ids.length, abi.tuDiaChi(ctx.player)).join()}'
        '${abi.tu(n)}${ids.map(abi.tu).join()}';
    final body = _than(await _goi(ctx, data));
    if (_soWord(body, 0) != BigInt.from(32) ||
        _soWord(body, 1) != n ||
        body.length != (ids.length + 2) * 64) {
      throw const LoiNFT(
        'balanceOfBatch trả mảng ABI sai độ dài/offset.',
        nguyenNhan: NguyenNhanLoiNFT.duLieu,
      );
    }
    return List.unmodifiable(
      List.generate(ids.length, (i) => _soWord(body, i + 2)),
    );
  }

  Future<ThongTinVatPhamNFT> docThongTinVatPham(BigInt tokenId) =>
      _doc((ctx) => _thongTin(ctx, tokenId));

  Future<ThongTinVatPhamNFT> _thongTin(_NguCanh ctx, BigInt id) async {
    _kiemSoDuong(id);
    final registered = _bool(await _goi(ctx, '0xe6cf1346${abi.tu(id)}'));
    final cap = _uint(await _goi(ctx, '0x869f7594${abi.tu(id)}'));
    final minted = _uint(await _goi(ctx, '0x9d7f4ebf${abi.tu(id)}'));
    if (minted > cap ||
        (registered && cap == BigInt.zero) ||
        (!registered && (cap != BigInt.zero || minted != BigInt.zero))) {
      throw const LoiNFT(
        'Nguồn cung NFT trả về không hợp lệ.',
        nguyenNhan: NguyenNhanLoiNFT.duLieu,
      );
    }
    final uri = registered
        ? _chuoiAbi(_than(await _goi(ctx, '0x0e89341c${abi.tu(id)}')), 0, 32)
        : null;
    if (uri != null && uri.isEmpty) {
      throw const LoiNFT(
        'URI vật phẩm đã đăng ký bị rỗng.',
        nguyenNhan: NguyenNhanLoiNFT.duLieu,
      );
    }
    return ThongTinVatPhamNFT(
      tokenId: id,
      registered: registered,
      maxSupply: cap,
      totalMinted: minted,
      metadataUri: uri,
    );
  }

  void _kiemModel(VatPhamNFT v) {
    if (v.chainId != cauHinh.chainId ||
        v.contractAddress.toLowerCase() != cauHinh.hopDong.toLowerCase()) {
      throw const LoiNFT(
        'Model NFT thuộc mạng/hợp đồng khác.',
        nguyenNhan: NguyenNhanLoiNFT.cauHinh,
      );
    }
  }

  Future<VatPhamNFT> _tai(_NguCanh ctx, VatPhamNFT v, {BigInt? soDu}) async {
    _kiemModel(v);
    final info = await _thongTin(ctx, v.tokenId);
    return v.copyWith(
      walletAddress: ctx.player,
      balance: soDu ?? await _soDu(ctx, v.tokenId),
      balanceStatus: TrangThaiSoDuNFT.daKiemTra,
      maxSupply: info.registered ? info.maxSupply : null,
      clearMaxSupply: !info.registered,
      metadataUri: info.metadataUri,
      clearMetadataUri: !info.registered,
    );
  }

  Future<VatPhamNFT> taiVatPham(VatPhamNFT metadata) =>
      _doc((ctx) => _tai(ctx, metadata));

  /// Danh mục là metadata do UI/Backend cung cấp; không đoán ID/ảnh/category trên chuỗi.
  /// Gọi một lần khi mở Kho; sau đó có thể dùng lamMoi và nghe danhSach/loiTai.
  Future<List<VatPhamNFT>> taiDanhSach(List<VatPhamNFT> metadata) async {
    for (final v in metadata) {
      _kiemModel(v);
    }
    _danhMuc = List.unmodifiable(metadata);
    return lamMoi();
  }

  Future<List<VatPhamNFT>> lamMoi() async {
    final lan = ++_lanTai;
    final catalog = _danhMuc;
    _danhSach = List.unmodifiable(
      catalog.map(
        (v) => v.copyWith(clearBalance: true, clearWalletAddress: true),
      ),
    );
    dangTai = true;
    loiTai = null;
    _bao();
    try {
      final result = await _doc((ctx) async {
        final balances = await _batch(
          ctx,
          catalog.map((v) => v.tokenId).toList(),
        );
        final list = <VatPhamNFT>[];
        for (var i = 0; i < catalog.length; i++) {
          list.add(await _tai(ctx, catalog[i], soDu: balances[i]));
        }
        return List<VatPhamNFT>.unmodifiable(list);
      });
      if (_daDong || lan != _lanTai) {
        throw const LoiVi('Lượt tải NFT đã bị thay thế.');
      }
      _danhSach = result;
      return result;
    } catch (e) {
      if (lan == _lanTai && !_daDong) loiTai = _dichLoi(e);
      rethrow;
    } finally {
      if (lan == _lanTai) {
        dangTai = false;
        _bao();
      }
    }
  }

  Future<KetQuaGiaoDichNFT> nhanVatPham(
    VatPhamNFT metadata, {
    PhieuVatPhamDaKy? phieu,
    void Function(String)? khiDaGui,
    void Function(TrangThaiGiaoDichNFT)? khiCapNhat,
  }) => _gui(
    metadata: metadata,
    khiDaGui: khiDaGui,
    khiCapNhat: khiCapNhat,
    kiemTruocChuyenMang: (player) =>
        _kiemPhieu(phieu, player, metadata.tokenId),
    chuanBi: (ctx) async {
      _kiemPhieu(phieu, ctx.player, metadata.tokenId);
      final p = phieu!.phieu;
      // Deadline/chữ ký/nonce/cap kiểm tra bằng mô phỏng claimItem trên node,
      // dùng thời gian chuỗi và signer hiện tại, không dựa vào đồng hồ thiết bị.
      return '0xbf60e081${abi.tuDiaChi(p.player)}${abi.tu(p.tokenId)}${abi.tu(p.amount)}${abi.tuBytes32(p.nonce)}${abi.tu(p.deadline)}'
          '${abi.tu(BigInt.from(192))}${abi.tu(BigInt.from(65))}${abi.boOx(phieu.chuKy)}${'0' * 62}';
    },
    kiemSau: (ctx, before, after) async {
      if (!_bool(
            await _goi(ctx, '0xfeb61724${abi.tuBytes32(phieu!.phieu.nonce)}'),
          ) ||
          after.balance! < before + phieu.phieu.amount) {
        throw _chuaCapNhat();
      }
      return null;
    },
  );

  void _kiemPhieu(PhieuVatPhamDaKy? phieu, String player, BigInt id) {
    if (phieu == null) throw const LoiVi('Chưa có phiếu NFT đã ký từ Backend.');
    if (phieu.cauHinh.chainId != cauHinh.chainId ||
        phieu.cauHinh.hopDong.toLowerCase() != cauHinh.hopDong.toLowerCase()) {
      throw const LoiVi('Phiếu NFT thuộc mạng/hợp đồng khác.');
    }
    if (phieu.phieu.player.toLowerCase() != player.toLowerCase() ||
        phieu.phieu.tokenId != id) {
      throw const LoiVi('Phiếu NFT không dành cho ví hoặc vật phẩm đang nhận.');
    }
  }

  /// Chỉ chuyển tài sản của ví hiện tại, không dùng owner/operator và không tự approve.
  /// metadata có thể bỏ nếu tokenId đã nằm trong danh mục của taiDanhSach.
  Future<KetQuaGiaoDichNFT> chuyenVatPham({
    required BigInt tokenId,
    required String nguoiNhan,
    required BigInt amount,
    VatPhamNFT? metadata,
    void Function(String)? khiDaGui,
    void Function(TrangThaiGiaoDichNFT)? khiCapNhat,
  }) async {
    _kiemSoDuong(tokenId);
    _kiemSoDuong(amount);
    _kiemDiaChi(nguoiNhan);
    final v =
        metadata ?? _danhMuc.where((v) => v.tokenId == tokenId).firstOrNull;
    if (v == null || v.tokenId != tokenId) {
      throw const LoiVi(
        'Cần metadata đúng tokenId; tải danh mục NFT hoặc truyền metadata.',
      );
    }
    return _gui(
      metadata: v,
      khiDaGui: khiDaGui,
      khiCapNhat: khiCapNhat,
      chuanBi: (ctx) async {
        if (nguoiNhan.toLowerCase() == ctx.player.toLowerCase()) {
          throw const LoiVi(
            'Người nhận phải khác ví gửi trong luồng chuyển vật phẩm.',
          );
        }
        final balance = await _soDu(ctx, tokenId);
        if (balance == BigInt.zero) {
          throw const LoiNFT(
            'Ví chưa sở hữu NFT này.',
            nguyenNhan: NguyenNhanLoiNFT.chuaSoHuu,
          );
        }
        if (balance < amount) {
          throw const LoiNFT(
            'Không đủ số dư NFT để chuyển.',
            nguyenNhan: NguyenNhanLoiNFT.thieuSoDu,
          );
        }
        return '0xf242432a${abi.tuDiaChi(ctx.player)}${abi.tuDiaChi(nguoiNhan)}${abi.tu(tokenId)}${abi.tu(amount)}${abi.tu(BigInt.from(160))}${abi.tu(BigInt.zero)}';
      },
      kiemSau: (ctx, before, after) async {
        if (after.balance! > before - amount) throw _chuaCapNhat();
        return _soDu(ctx, tokenId, wallet: nguoiNhan);
      },
      nguoiNhan: nguoiNhan,
    );
  }

  Future<KetQuaGiaoDichNFT> _gui({
    required VatPhamNFT metadata,
    required Future<String> Function(_NguCanh) chuanBi,
    required Future<BigInt?> Function(_NguCanh, BigInt, VatPhamNFT) kiemSau,
    String? nguoiNhan,
    void Function(String)? kiemTruocChuyenMang,
    void Function(String)? khiDaGui,
    void Function(TrangThaiGiaoDichNFT)? khiCapNhat,
  }) async {
    if (phienVi.dangXuLy || phienVi.dangHoi) {
      throw const LoiVi(
        'Phiên ví đang xử lý giao dịch khác.',
        loai: LoaiLoiVi.dangCho,
      );
    }
    if (_hashDangCho != null) {
      throw LoiVi(
        'Giao dịch $_hashDangCho chưa rõ kết quả. Gọi docBienLai trước khi gửi tiếp.',
        loai: LoaiLoiVi.chuaXacNhan,
      );
    }
    phienVi.dangXuLy = true;
    String? hash;
    BienLai? receipt;
    void capNhat(TrangThaiGiaoDichNFT s) {
      trangThai = s;
      _bao();
      khiCapNhat?.call(s);
    }

    try {
      phienVi.veLai();
      transactionHash = null;
      capNhat(TrangThaiGiaoDichNFT.chuaBatDau);
      final player = _player();
      _kiemModel(metadata);
      kiemTruocChuyenMang?.call(player);
      // Chỉ hành động nhận/chuyển mới được phép xin chuyển mạng.
      await _bo(_vi).damBaoMang();
      final ctx = _NguCanh(player, _theHe);
      await _chuanBi(ctx);
      final before = await _soDu(ctx, metadata.tokenId);
      final calldata = await chuanBi(ctx);
      await _kiem(ctx);
      _voHieuHoa(
        taiLai: false,
      ); // Bỏ số dư cũ trước khi giao dịch có thể đổi tài sản.
      final txCtx = _NguCanh(player, _theHe);
      final adapter = _ViNFT(
        _vi,
        baoVe: () => _kiem(txCtx),
        truocGui: () => capNhat(TrangThaiGiaoDichNFT.choXacNhanVi),
        daGui: (h) {
          hash = h;
          transactionHash = h;
          _hashDangCho = h;
          capNhat(TrangThaiGiaoDichNFT.choXacNhanChuoi);
          khiDaGui?.call(h);
        },
        daCoBienLai: (bl) {
          receipt = bl;
        },
      );
      // Không dùng daXong theo số dư: số dư thay đổi không chứng minh receipt thành công.
      await _bo(adapter).gui(
        tu: player,
        duLieu: calldata,
        moTa: nguoiNhan == null
            ? 'nhận NFT ${metadata.name}'
            : 'chuyển NFT ${metadata.name}',
      );
      if (hash == null || receipt?.thanhCong != true) throw _chuaCapNhat();
      _hashDangCho = null;
      capNhat(TrangThaiGiaoDichNFT.daXacNhan);
      final updated = await _tai(txCtx, metadata);
      final recipientBalance = await kiemSau(txCtx, before, updated);
      await _kiem(txCtx);
      _danhSach = List.unmodifiable(
        _danhSach.map((v) => v.tokenId == metadata.tokenId ? updated : v),
      );
      capNhat(TrangThaiGiaoDichNFT.thanhCong);
      return KetQuaGiaoDichNFT(
        transactionHash: hash!,
        receipt: receipt!,
        vatPham: updated,
        nguoiNhan: nguoiNhan,
        soDuNguoiNhan: recipientBalance,
      );
    } catch (e) {
      var loi = _dichLoi(e);
      if (receipt?.thanhCong == true) {
        _hashDangCho = null;
        loi = LoiVi(
          'Giao dịch đã xác nhận nhưng chưa đối chiếu được dữ liệu NFT: ${loi.thongBao} Làm mới trước khi gửi lại.',
          loai: LoaiLoiVi.chuaXacNhan,
        );
        capNhat(TrangThaiGiaoDichNFT.duLieuChuaCapNhat);
      } else if (loi.nguoiDungTuChoi) {
        capNhat(TrangThaiGiaoDichNFT.daHuy);
      } else if (hash != null && receipt == null) {
        capNhat(
          loi.loai == LoaiLoiVi.chuaXacNhan
              ? TrangThaiGiaoDichNFT.hetThoiGianCho
              : TrangThaiGiaoDichNFT.choXacNhanChuoi,
        );
      } else {
        _hashDangCho = null;
        capNhat(TrangThaiGiaoDichNFT.thatBai);
      }
      throw LoiGiaoDichNFT(loi, transactionHash: hash, receipt: receipt);
    } finally {
      phienVi.dangXuLy = false;
      if (!_daDong) phienVi.veLai();
    }
  }

  /// Theo dõi hash sau timeout/đổi phiên, không gửi lại. Sau receipt thành công,
  /// gọi lamMoi để lấy dữ liệu mới; chưa tự coi số dư cũ là đã xác minh.
  Future<BienLai?> docBienLai(String hash) => _doc((ctx) async {
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash)) {
      throw const FormatException('Hash giao dịch không hợp lệ');
    }
    final bl = await _vi.bienLai(hash);
    await _kiem(ctx);
    if (_hashDangCho == hash && bl != null) {
      _hashDangCho = null;
      trangThai = bl.thanhCong
          ? TrangThaiGiaoDichNFT.daXacNhan
          : TrangThaiGiaoDichNFT.thatBai;
      _bao();
    }
    return bl;
  });

  @override
  void dispose() {
    _daDong = true;
    _theHe++;
    _lanTai++;
    phienVi.removeListener(_khiPhienDoi);
    unawaited(_ngheVi.cancel());
    super.dispose();
  }
}

class _NguCanh {
  final String player;
  final int theHe;
  const _NguCanh(this.player, this.theHe);
}

class _DoiNguCanh implements Exception {
  final LoiVi loi;
  const _DoiNguCanh(this.loi);
}

/// Adapter của cùng Vi, không tạo provider hay cơ chế MetaMask mới.
class _ViNFT implements Vi {
  final Vi goc;
  final Future<void> Function() baoVe;
  final void Function() truocGui;
  final void Function(String) daGui;
  final void Function(BienLai) daCoBienLai;
  _ViNFT(
    this.goc, {
    required this.baoVe,
    required this.truocGui,
    required this.daGui,
    required this.daCoBienLai,
  });
  @override
  bool get coSan => goc.coSan;
  @override
  String get ten => goc.ten;
  @override
  Stream<SuKienVi> get suKien => goc.suKien;
  @override
  Future<String> ketNoi() => goc.ketNoi();
  @override
  Future<List<String>> taiKhoan() => goc.taiKhoan();
  @override
  Future<int> chainId() => goc.chainId();
  @override
  Future<void> chuyenMang(
    int chainId, {
    String? tenMang,
    String? rpcUrl,
  }) async {
    await baoVe();
    await goc.chuyenMang(chainId, tenMang: tenMang, rpcUrl: rpcUrl);
  }

  @override
  Future<String> goi({
    required String toi,
    required String duLieu,
    String? tu,
  }) async {
    await baoVe();
    final String r;
    try {
      r = await goc.goi(toi: toi, duLieu: duLieu, tu: tu);
    } catch (e) {
      throw _dichLoi(e);
    }
    await baoVe();
    return r;
  }

  @override
  Future<String> maHopDong(String diaChi) => goc.maHopDong(diaChi);
  @override
  Future<BigInt> uocLuongGas({
    required String tu,
    required String toi,
    required String duLieu,
  }) => goc.uocLuongGas(tu: tu, toi: toi, duLieu: duLieu);
  @override
  Future<BigInt> giaGas() => goc.giaGas();
  @override
  Future<BigInt> soDu(String diaChi) => goc.soDu(diaChi);
  @override
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  }) async {
    await baoVe();
    truocGui();
    final hash = await goc.guiGiaoDich(
      tu: tu,
      toi: toi,
      duLieu: duLieu,
      gas: gas,
    );
    daGui(hash);
    return hash;
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    await baoVe();
    final bl = await goc.bienLai(maGiaoDich);
    if (bl != null) daCoBienLai(bl);
    await baoVe();
    return bl;
  }
}

LoiVi _chuaCapNhat() => const LoiVi(
  'Dữ liệu Blockchain chưa cập nhật hoặc có giao dịch đồng thời; cần đọc lại số dư.',
  loai: LoaiLoiVi.chuaXacNhan,
);
void _kiemDiaChi(String address) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address) ||
      RegExp(r'^0x0{40}$').hasMatch(address)) {
    throw const FormatException('Địa chỉ EVM phải có 20 byte và khác zero');
  }
}

void _kiemSoDuong(BigInt n) {
  abi.tu(n);
  if (n == BigInt.zero) throw ArgumentError('tokenId/amount phải lớn hơn 0');
}

String _chuoi(Object? v) {
  if (v is String) return v;
  throw const FormatException('Trường JSON phải là String');
}

BigInt _uintJson(Object? v) {
  final BigInt n;
  if (v is int && v >= 0 && v <= 9007199254740991) {
    n = BigInt.from(v);
  } else if (v is String && RegExp(r'^[0-9]+$').hasMatch(v)) {
    n = BigInt.parse(v);
  } else {
    throw const FormatException(
      'uint256 phải dùng số JSON an toàn hoặc chuỗi thập phân',
    );
  }
  abi.tu(n);
  return n;
}

String _than(String data) {
  if (!RegExp(r'^0x(?:[0-9a-fA-F]{64})+$').hasMatch(data)) {
    throw const LoiNFT(
      'RPC trả ABI rỗng hoặc sai dạng; chưa xác minh số dư.',
      nguyenNhan: NguyenNhanLoiNFT.duLieu,
    );
  }
  return data.substring(2).toLowerCase();
}

String _word(String body, int i) {
  if (i < 0 || (i + 1) * 64 > body.length) {
    throw const LoiNFT(
      'Thiếu từ ABI trong dữ liệu RPC.',
      nguyenNhan: NguyenNhanLoiNFT.duLieu,
    );
  }
  return body.substring(i * 64, (i + 1) * 64);
}

BigInt _soWord(String body, int i) => BigInt.parse(_word(body, i), radix: 16);
BigInt _uint(String data) {
  final body = _than(data);
  if (body.length != 64) {
    throw const LoiNFT(
      'RPC phải trả đúng một từ uint256.',
      nguyenNhan: NguyenNhanLoiNFT.duLieu,
    );
  }
  return _soWord(body, 0);
}

bool _bool(String data) {
  final n = _uint(data);
  if (n != BigInt.zero && n != BigInt.one) {
    throw const LoiNFT(
      'Giá trị bool ABI không hợp lệ.',
      nguyenNhan: NguyenNhanLoiNFT.duLieu,
    );
  }
  return n == BigInt.one;
}

String _chuoiAbi(String body, int index, int minOffset) {
  final offset = _soWord(body, index);
  if (offset < BigInt.from(minOffset) ||
      offset % BigInt.from(32) != BigInt.zero ||
      offset + BigInt.from(32) > BigInt.from(body.length ~/ 2)) {
    throw const LoiNFT(
      'Offset chuỗi ABI không hợp lệ.',
      nguyenNhan: NguyenNhanLoiNFT.duLieu,
    );
  }
  final start = offset.toInt() * 2;
  final length = BigInt.parse(body.substring(start, start + 64), radix: 16);
  if (length > BigInt.from((body.length - start - 64) ~/ 2)) {
    throw const LoiNFT(
      'Thiếu dữ liệu chuỗi ABI.',
      nguyenNhan: NguyenNhanLoiNFT.duLieu,
    );
  }
  final h = body.substring(start + 64, start + 64 + length.toInt() * 2);
  return utf8.decode([
    for (var i = 0; i < h.length; i += 2)
      int.parse(h.substring(i, i + 2), radix: 16),
  ]);
}

LoiVi _dichLoi(Object error) {
  if (error is _DoiNguCanh) return error.loi;
  if (error is! LoiVi) return LoiVi('Không xử lý được dữ liệu NFT: $error');
  if (error.nguoiDungTuChoi) return error;
  final data =
      timDuLieuRevert(error.duLieu) ?? timDuLieuRevert(error.thongDiepGoc);
  final ten = data == null
      ? null
      : const {
          '0xcc3b34d5': 'WrongPlayer',
          '0x157fd87e': 'VoucherExpired',
          '0x8c242285': 'NonceAlreadyUsed',
          '0x8baa579f': 'InvalidSignature',
          '0x6c3517c8': 'ItemNotRegistered',
          '0x2c5211c6': 'InvalidAmount',
          '0xb14d3f5b': 'MaxSupplyExceeded',
          '0xed15e6cf': 'InvalidTokenId',
          '0x03dee4c5': 'ERC1155InsufficientBalance',
          '0x57f447ce': 'ERC1155InvalidReceiver',
          '0xe237d922': 'ERC1155MissingApprovalForAll',
          '0x5b059991': 'ERC1155InvalidArrayLength',
        }[data.substring(0, 10).toLowerCase()];
  if (ten == null) return error;
  final text = switch (ten) {
    'WrongPlayer' => 'Phiếu NFT dành cho ví khác.',
    'VoucherExpired' => 'Phiếu hết hạn — cần Backend cấp phiếu mới.',
    'NonceAlreadyUsed' => 'Nonce phiếu đã được sử dụng; không gửi lại.',
    'InvalidSignature' => 'Chữ ký Backend sai hoặc signer đã thay đổi.',
    'ItemNotRegistered' => 'Vật phẩm chưa được owner đăng ký.',
    'MaxSupplyExceeded' => 'Không thể mint vượt maxSupply của vật phẩm.',
    'InvalidAmount' => 'Số lượng NFT phải lớn hơn 0.',
    'InvalidTokenId' => 'Token ID không hợp lệ.',
    'ERC1155InsufficientBalance' => 'Không đủ số dư NFT để chuyển.',
    'ERC1155InvalidReceiver' =>
      'Địa chỉ nhận không hợp lệ hoặc hợp đồng không nhận ERC-1155.',
    'ERC1155MissingApprovalForAll' => 'Ví không được quyền chuyển NFT này.',
    _ => 'Hợp đồng từ chối dữ liệu chuyển NFT.',
  };
  return LoiVi(
    '$text ($ten)',
    ma: error.ma,
    duLieu: error.duLieu,
    thongDiepGoc: error.thongDiepGoc,
    loai: LoaiLoiVi.hopDongTuChoi,
  );
}
