import 'dart:convert';

import '../abi.dart' as abi;
import '../giao_dich.dart';
import '../loi_hop_dong.dart';
import '../phien_vi.dart';
import '../vi.dart';
import 'sbt_model.dart';

/// Cấu hình SBT riêng, không dùng địa chỉ cửa hàng ERC-1155 làm địa chỉ SBT.
class CauHinhSBT {
  final int chainId;
  final String hopDong;
  final String? tenMang;
  final String? rpcUrl;

  CauHinhSBT({
    required this.chainId,
    required this.hopDong,
    this.tenMang,
    this.rpcUrl,
  }) {
    if (chainId <= 0) throw ArgumentError.value(chainId, 'chainId');
    _kiemDiaChi(hopDong);
  }
}

/// Đúng struct PhieuSBT của Solidity. Không có phương thức ký trên Flutter.
class PhieuSBT {
  final String player;
  final int achievementId;
  final String nonce;
  final BigInt deadline;

  PhieuSBT({
    required this.player,
    required this.achievementId,
    required this.nonce,
    required this.deadline,
  }) {
    _kiemDiaChi(player);
    _kiemId(achievementId);
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(nonce)) {
      throw const FormatException('nonce phải là bytes32 có tiền tố 0x');
    }
    abi.tu(deadline);
  }

  factory PhieuSBT.fromJson(Map<String, dynamic> json) => PhieuSBT(
    player: json['player'] as String,
    achievementId: _idJson(json['achievementId']),
    nonce: json['nonce'] as String,
    deadline: _uintJson(json['deadline']),
  );

  Map<String, dynamic> toJson() => {
    'player': player,
    'achievementId': achievementId,
    'nonce': nonce,
    'deadline': deadline.toString(),
  };
}

/// Kết quả của adapter Backend: phiếu, chữ ký ECDSA 65 byte và ngữ cảnh EIP-712.
/// Adapter của Người 5 chuyển response API thực tế sang kiểu này; chưa có endpoint mặc định.
class PhieuSBTDaKy {
  final PhieuSBT phieu;
  final String chuKy;
  final CauHinhSBT cauHinh;

  PhieuSBTDaKy({
    required this.phieu,
    required this.chuKy,
    required this.cauHinh,
  }) {
    if (!RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(chuKy)) {
      throw const FormatException('Chữ ký SBT phải có 65 byte (0x + 130 hex)');
    }
  }
}

abstract interface class NguonPhieuSBT {
  Future<PhieuSBTDaKy> xinPhieu({
    required String player,
    required int achievementId,
    required int chainId,
    required String hopDong,
  });
}

class ThongTinTokenSBT {
  final BigInt tokenId;
  final int achievementId;
  final String owner;

  const ThongTinTokenSBT({
    required this.tokenId,
    required this.achievementId,
    required this.owner,
  });
}

/// Dùng lại phienVi.vi và BoGiaoDich, không kết nối hoặc tạo ví mới.
/// Không ghi cache sở hữu chung: UI phải tải lại khi đổi ví/mạng.
/// Lỗi được ném dưới dạng LoiVi; khiCapNhat cung cấp model cho tiến độ UI.
class DichVuSBT {
  final PhienVi phienVi;
  final CauHinhSBT cauHinh;
  final NguonPhieuSBT? nguonPhieu;
  final Duration choToiDa;
  final Duration nhipKiemTra;
  final Future<void> Function(Duration)? ngu;

  DichVuSBT({
    required this.phienVi,
    required this.cauHinh,
    this.nguonPhieu,
    this.choToiDa = const Duration(minutes: 2),
    this.nhipKiemTra = const Duration(milliseconds: 1500),
    this.ngu,
  }) {
    if (choToiDa <= Duration.zero || nhipKiemTra <= Duration.zero) {
      throw ArgumentError('Thời gian chờ/nhịp kiểm tra phải lớn hơn 0');
    }
  }

  Vi get _vi => phienVi.vi;
  bool get coHoTroVi => _vi.coSan;

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

  /// Chỉ đọc trên đúng mạng, không tự mở hộp thoại chuyển mạng khi tải hồ sơ.
  /// tokenId cache bị bỏ: hasAchievement không trả tokenId và ERC-721 này không enumerable.
  Future<ThanhTuuSBT> taiThanhTuu(ThanhTuuSBT thanhTuu) => _docVoiPhien(
    (player) async => thanhTuu.copyWith(
      ownershipStatus: await _coThanhTuu(player, thanhTuu.achievementId)
          ? TrangThaiSoHuuSBT.daSoHuu
          : TrangThaiSoHuuSBT.chuaSoHuu,
      clearTokenId: true,
    ),
  );

  Future<List<ThanhTuuSBT>> taiDanhSach({List<ThanhTuuSBT>? danhSach}) =>
      _docVoiPhien((player) async {
        final ketQua = <ThanhTuuSBT>[];
        for (final thanhTuu in danhSach ?? bangThanhTuuSBT) {
          ketQua.add(
            thanhTuu.copyWith(
              ownershipStatus: await _coThanhTuu(player, thanhTuu.achievementId)
                  ? TrangThaiSoHuuSBT.daSoHuu
                  : TrangThaiSoHuuSBT.chuaSoHuu,
              clearTokenId: true,
            ),
          );
        }
        return List<ThanhTuuSBT>.unmodifiable(ketQua);
      });

  /// Đọc token đã biết ID từ nguồn sự kiện/indexer, không đoán tokenId = achievementId.
  Future<ThongTinTokenSBT> docToken(BigInt tokenId) => _docVoiPhien((
    player,
  ) async {
    abi.tu(tokenId);
    if (tokenId == BigInt.zero) throw const LoiVi('tokenId phải lớn hơn 0.');
    final id = _uint(await _goi(player, '0x47dd089f${abi.tu(tokenId)}'));
    if (id < BigInt.one || id > BigInt.from(5)) {
      throw const LoiVi('Loại thành tích trả về không hợp lệ.');
    }
    final owner = _diaChiAbi(
      await _goi(player, '0x6352211e${abi.tu(tokenId)}'),
    );
    return ThongTinTokenSBT(
      tokenId: tokenId,
      achievementId: id.toInt(),
      owner: owner,
    );
  });

  Future<String> docSigner() => _docVoiPhien(
    (player) async => _diaChiAbi(await _goi(player, '0x238ac933')),
  );

  /// Tùy chọn dùng interface Backend đã inject, không gọi URL API tự đặt.
  Future<PhieuSBTDaKy> xinPhieu(int achievementId) =>
      _docVoiPhien((player) async {
        _kiemId(achievementId);
        final phieu = await _xinPhieu(player, achievementId);
        await _kiemNguCanh(player);
        _kiemPhieu(phieu, player, achievementId);
        return phieu;
      });

  Future<PhieuSBTDaKy> _xinPhieu(String player, int id) {
    final nguon = nguonPhieu;
    if (nguon == null) {
      throw const LoiVi(
        'Chưa cấu hình nguồn phiếu SBT. Truyền phiếu đã ký hoặc inject NguonPhieuSBT.',
      );
    }
    return nguon.xinPhieu(
      player: player,
      achievementId: id,
      chainId: cauHinh.chainId,
      hopDong: cauHinh.hopDong,
    );
  }

  /// Nhận phiếu trực tiếp hoặc xin qua nguồn đã inject. Không dùng eligible để cấp quyền mint.
  /// Giao dịch vẫn do hợp đồng mô phỏng/xác minh chữ ký, deadline và nonce.
  /// Timeout/đổi ngữ cảnh sau khi gửi giữ choXacNhanChuoi, không khẳng định giao dịch thất bại.
  Future<ThanhTuuSBT> nhanThanhTuu(
    ThanhTuuSBT thanhTuu, {
    PhieuSBTDaKy? phieu,
    void Function(ThanhTuuSBT)? khiCapNhat,
    void Function(String)? khiDaGui,
  }) async {
    if (phienVi.dangXuLy || phienVi.dangHoi) {
      throw const LoiVi(
        'Phiên ví đang xử lý việc khác — đợi xong rồi thử lại.',
        loai: LoaiLoiVi.dangCho,
      );
    }
    phienVi.dangXuLy = true;
    var model = thanhTuu.copyWith(
      ownershipStatus: TrangThaiSoHuuSBT.chuaKiemTra,
      clearTokenId: true,
      claimStatus: TrangThaiNhanSBT.chuaBatDau,
    );
    var daGui = false;
    void capNhat(TrangThaiNhanSBT status) {
      model = model.copyWith(claimStatus: status);
      khiCapNhat?.call(model);
    }

    try {
      phienVi.veLai();
      capNhat(TrangThaiNhanSBT.chuaBatDau);
      final player = _diaChiPhien();
      // Adapter này chỉ quan sát đúng Vi hiện có; mọi JSON-RPC vẫn được chuyển nguyên vẹn.
      final viTheoDoi = _ViTheoDoi(
        _vi,
        baoVe: () => _kiemNguCanh(player),
        truocKhiGui: () => capNhat(TrangThaiNhanSBT.choXacNhanVi),
        sauKhiGui: (hash) {
          daGui = true;
          khiDaGui?.call(hash);
          capNhat(TrangThaiNhanSBT.dangGui);
          capNhat(TrangThaiNhanSBT.choXacNhanChuoi);
        },
      );
      final bo = _bo(viTheoDoi);
      await bo.damBaoMang();
      await _chuanBi(player);
      if (!await _coThanhTuu(player, thanhTuu.achievementId)) {
        final daKy = phieu ?? await _xinPhieu(player, thanhTuu.achievementId);
        await _kiemNguCanh(player);
        _kiemPhieu(daKy, player, thanhTuu.achievementId);
        final p = daKy.phieu;
        // Tuple tĩnh 4 từ + offset bytes (5*32) + độ dài chữ ký + 65 byte đệm thành 96.
        final calldata =
            '0x9e34f6bd${abi.tuDiaChi(p.player)}${abi.tu(BigInt.from(p.achievementId))}'
            '${abi.tuBytes32(p.nonce)}${abi.tu(p.deadline)}${abi.tu(BigInt.from(160))}'
            '${abi.tu(BigInt.from(65))}${abi.boOx(daKy.chuKy)}${'0' * 62}';
        await bo.gui(
          tu: player,
          duLieu: calldata,
          moTa: 'nhận huy hiệu ${thanhTuu.name}',
          daXong: () => _coThanhTuu(player, thanhTuu.achievementId),
        );
      }
      // Đọc lại trên đúng ví/mạng ngay cả khi BoGiaoDich phát hiện giao dịch tăng tốc.
      if (!await _coThanhTuu(player, thanhTuu.achievementId)) {
        throw const LoiVi(
          'Chưa xác minh được thành tích sau giao dịch. Hãy làm mới trước khi gửi lại.',
          loai: LoaiLoiVi.chuaXacNhan,
        );
      }
      model = model.copyWith(ownershipStatus: TrangThaiSoHuuSBT.daSoHuu);
      capNhat(TrangThaiNhanSBT.thanhCong);
      return model;
    } catch (error) {
      final loi = _dichLoi(error);
      final status = loi.nguoiDungTuChoi
          ? TrangThaiNhanSBT.daHuy
          : loi.loai == LoaiLoiVi.chuaXacNhan ||
                (daGui && loi.loai != LoaiLoiVi.hopDongTuChoi)
          ? TrangThaiNhanSBT.choXacNhanChuoi
          : TrangThaiNhanSBT.thatBai;
      model = model.copyWith(
        ownershipStatus: TrangThaiSoHuuSBT.chuaKiemTra,
        clearTokenId: true,
      );
      capNhat(status);
      throw loi;
    } finally {
      phienVi.dangXuLy = false;
      phienVi.veLai();
    }
  }

  String _diaChiPhien() {
    if (!coHoTroVi) {
      throw const LoiVi(
        'Nền tảng này chưa có ví được hỗ trợ. Dùng MetaMask trên Flutter Web.',
      );
    }
    final player = phienVi.diaChi;
    if (player == null) {
      throw const LoiVi(
        'Chưa kết nối phiên ví. Hãy kết nối MetaMask bằng PhienVi hiện có.',
      );
    }
    _kiemDiaChi(player);
    return player;
  }

  Future<void> _kiemNguCanh(String player) async {
    final taiKhoan = await _vi.taiKhoan();
    if (phienVi.diaChi?.toLowerCase() != player.toLowerCase() ||
        taiKhoan.isEmpty ||
        taiKhoan.first.toLowerCase() != player.toLowerCase()) {
      throw const _NguCanhDaDoi(
        LoiVi(
          'Tài khoản đã thay đổi — tải lại hồ sơ cho ví hiện tại.',
          loai: LoaiLoiVi.doiTaiKhoan,
        ),
      );
    }
    if (await _vi.chainId() != cauHinh.chainId) {
      throw const _NguCanhDaDoi(
        LoiVi('Ví đang sai mạng SBT. Chọn đúng mạng rồi tải lại hồ sơ.'),
      );
    }
  }

  Future<String> _goi(String player, String data) async {
    await _kiemNguCanh(player);
    final result = await _vi.goi(toi: cauHinh.hopDong, duLieu: data);
    await _kiemNguCanh(player);
    return result;
  }

  Future<bool> _coThanhTuu(String player, int id) async {
    _kiemId(id);
    final value = _uint(
      await _goi(
        player,
        '0xab5eba16${abi.tuDiaChi(player)}${abi.tu(BigInt.from(id))}',
      ),
    );
    if (value != BigInt.zero && value != BigInt.one) {
      throw const LoiVi('Kết quả hasAchievement không phải bool ABI.');
    }
    return value == BigInt.one;
  }

  Future<void> _chuanBi(String player) async {
    await _kiemNguCanh(player);
    await _bo(_vi).kiemHopDong();
    final typehash = await _goi(player, '0xdaf11c98');
    if (typehash.toLowerCase() !=
            '0x077c00b8deda7e1f1b254c408b884b55ac55baf4a26abc2c690095ac87dc7d7d' ||
        _uint(await _goi(player, '0x89502698')) != BigInt.from(5)) {
      throw const LoiVi(
        'Địa chỉ cấu hình không khớp hợp đồng ThanhTuuSBT hiện tại.',
      );
    }
    final domain = _thanAbi(await _goi(player, '0x84b0196e'));
    if (domain.length < 448 ||
        _word(domain, 0) != '0f${'0' * 62}' ||
        _chuoiAbi(domain, 1) != 'GoldRushSBT' ||
        _chuoiAbi(domain, 2) != '1' ||
        BigInt.parse(_word(domain, 3), radix: 16) !=
            BigInt.from(cauHinh.chainId) ||
        _diaChiAbi('0x${_word(domain, 4)}') != cauHinh.hopDong.toLowerCase()) {
      throw const LoiVi(
        'EIP-712 domain không khớp GoldRushSBT / 1 / chainId / hợp đồng đã cấu hình.',
      );
    }
  }

  Future<T> _docVoiPhien<T>(Future<T> Function(String player) viec) async {
    try {
      final player = _diaChiPhien();
      await _chuanBi(player);
      final result = await viec(player);
      await _kiemNguCanh(player);
      return result;
    } catch (error) {
      throw _dichLoi(error);
    }
  }

  void _kiemPhieu(PhieuSBTDaKy phieu, String player, int id) {
    if (phieu.cauHinh.chainId != cauHinh.chainId ||
        phieu.cauHinh.hopDong.toLowerCase() != cauHinh.hopDong.toLowerCase()) {
      throw const LoiVi('Phiếu SBT được cấp cho mạng hoặc hợp đồng khác.');
    }
    if (phieu.phieu.player.toLowerCase() != player.toLowerCase() ||
        phieu.phieu.achievementId != id) {
      throw const LoiVi(
        'Phiếu SBT không dành cho ví hoặc thành tích đang nhận.',
      );
    }
  }
}

// Ngoại lệ ngữ cảnh riêng để vòng chờ BoGiaoDich không nuốt nó như lỗi RPC tạm thời.
class _NguCanhDaDoi implements Exception {
  final LoiVi loi;
  const _NguCanhDaDoi(this.loi);
}

/// Adapter chuyển tiếp vào cùng Vi hiện có, chỉ thêm quan sát tiến độ và kiểm tra ngữ cảnh.
class _ViTheoDoi implements Vi {
  final Vi goc;
  final Future<void> Function() baoVe;
  final void Function() truocKhiGui;
  final void Function(String) sauKhiGui;
  _ViTheoDoi(
    this.goc, {
    required this.baoVe,
    required this.truocKhiGui,
    required this.sauKhiGui,
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
  Future<void> chuyenMang(int chainId, {String? tenMang, String? rpcUrl}) =>
      goc.chuyenMang(chainId, tenMang: tenMang, rpcUrl: rpcUrl);
  @override
  Future<String> goi({
    required String toi,
    required String duLieu,
    String? tu,
  }) => goc.goi(toi: toi, duLieu: duLieu, tu: tu);
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
    truocKhiGui();
    final hash = await goc.guiGiaoDich(
      tu: tu,
      toi: toi,
      duLieu: duLieu,
      gas: gas,
    );
    sauKhiGui(hash);
    return hash;
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    await baoVe();
    final result = await goc.bienLai(maGiaoDich);
    await baoVe();
    return result;
  }
}

void _kiemDiaChi(String value) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value) ||
      RegExp(r'^0x0{40}$').hasMatch(value)) {
    throw const FormatException(
      'Địa chỉ EVM phải có 20 byte và khác địa chỉ zero',
    );
  }
}

void _kiemId(int id) {
  if (id < 1 || id > 5) throw RangeError.range(id, 1, 5, 'achievementId');
}

int _idJson(Object? value) {
  final id = _uintJson(value);
  if (id < BigInt.one || id > BigInt.from(5)) {
    throw const FormatException('achievementId phải từ 1 đến 5');
  }
  return id.toInt();
}

BigInt _uintJson(Object? value) {
  final BigInt n;
  if (value is int && value >= 0 && value <= 9007199254740991) {
    n = BigInt.from(value);
  } else if (value is String && RegExp(r'^[0-9]+$').hasMatch(value)) {
    n = BigInt.parse(value);
  } else {
    throw const FormatException(
      'uint256 phải là số an toàn hoặc chuỗi thập phân',
    );
  }
  abi.tu(n);
  return n;
}

String _thanAbi(String data) {
  if (!RegExp(r'^0x(?:[0-9a-fA-F]{64})+$').hasMatch(data)) {
    throw const LoiVi('RPC trả dữ liệu ABI rỗng hoặc sai dạng.');
  }
  return data.substring(2).toLowerCase();
}

BigInt _uint(String data) {
  final body = _thanAbi(data);
  if (body.length != 64) {
    throw const LoiVi('RPC phải trả đúng một từ ABI uint256.');
  }
  return BigInt.parse(body, radix: 16);
}

String _diaChiAbi(String data) {
  final n = _uint(data);
  if (n == BigInt.zero || n.bitLength > 160) {
    throw const LoiVi('Địa chỉ trả về không hợp lệ.');
  }
  return '0x${n.toRadixString(16).padLeft(40, '0')}';
}

String _word(String body, int index) {
  if (index < 0 || body.length < (index + 1) * 64) {
    throw const LoiVi('Thiếu từ ABI trong kết quả RPC.');
  }
  return body.substring(index * 64, (index + 1) * 64);
}

String _chuoiAbi(String body, int index) {
  final offset = BigInt.parse(_word(body, index), radix: 16);
  if (offset < BigInt.from(224) ||
      offset * BigInt.two >= BigInt.from(body.length) ||
      offset % BigInt.from(32) != BigInt.zero) {
    throw const LoiVi('Offset chuỗi EIP-712 không hợp lệ.');
  }
  final start = offset.toInt() * 2;
  final length = BigInt.parse(body.substring(start, start + 64), radix: 16);
  if (length * BigInt.two > BigInt.from(body.length - start - 64)) {
    throw const LoiVi('Thiếu dữ liệu chuỗi EIP-712.');
  }
  final hex = body.substring(start + 64, start + 64 + length.toInt() * 2);
  return utf8.decode([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

LoiVi _dichLoi(Object error) {
  if (error is _NguCanhDaDoi) return error.loi;
  if (error is! LoiVi) return LoiVi('Không xử lý được dữ liệu SBT: $error');
  if (error.nguoiDungTuChoi) return error;
  final data =
      timDuLieuRevert(error.duLieu) ?? timDuLieuRevert(error.thongDiepGoc);
  final ten = data == null
      ? null
      : const {
          '0xcc3b34d5': 'WrongPlayer',
          '0x157fd87e': 'VoucherExpired',
          '0x8c242285': 'NonceAlreadyUsed',
          '0x509e2d52': 'AchievementAlreadyClaimed',
          '0x6672f527': 'InvalidAchievementId',
          '0x8baa579f': 'InvalidSignature',
          '0xa4420a95': 'Soulbound',
          '0x7e273289': 'ERC721NonexistentToken',
        }[data.substring(0, 10).toLowerCase()];
  if (ten == null) return error;
  final thongBao = switch (ten) {
    'WrongPlayer' => 'Phiếu cấp cho ví khác.',
    'VoucherExpired' => 'Phiếu đã hết hạn — xin Backend cấp lại.',
    'NonceAlreadyUsed' => 'Phiếu này đã được sử dụng.',
    'AchievementAlreadyClaimed' => 'Ví đã sở hữu thành tích này.',
    'InvalidAchievementId' => 'ID thành tích không hợp lệ.',
    'InvalidSignature' =>
      'Chữ ký Backend không hợp lệ hoặc signer đã thay đổi.',
    'Soulbound' => 'Huy hiệu SBT không thể chuyển nhượng.',
    _ => 'Token SBT chưa tồn tại.',
  };
  return LoiVi(
    '$thongBao ($ten)',
    ma: error.ma,
    duLieu: error.duLieu,
    thongDiepGoc: error.thongDiepGoc,
    loai: LoaiLoiVi.hopDongTuChoi,
  );
}
