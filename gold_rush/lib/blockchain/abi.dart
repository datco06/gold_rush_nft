/// Mã hoá lời gọi hợp đồng `CuaHangGoldRush` (bản 2) theo chuẩn ABI của Ethereum — viết tay.
///
/// Vì sao không dùng thư viện (web3dart…): app chỉ gọi vài hàm, mọi tham số là số 32 byte trừ chữ ký
/// (`bytes`) và danh sách lệnh của `multicall` (`bytes[]`). Viết tay ~150 dòng thì sinh viên NHÌN THẤY
/// dữ liệu gửi lên chuỗi trông thế nào, và không kéo phụ thuộc mật mã nào vào bản dựng web.
///
/// Bộ chọn hàm (4 byte đầu của keccak256 chữ ký hàm) tính sẵn bằng Python
/// (`gold_rush_ai/scripts/sinh_abi_mau.py`) — Dart lõi không có keccak256. Ba bộ mã hoá độc lập
/// được đối chiếu với nhau: Python (theo đặc tả tổng quát) ↔ Dart (tệp này, `abi_test.dart`)
/// ↔ viem (`gold_rush_chain/test`, cùng tệp mẫu `abi_mau.json`).
library;

/// nhanVang((address,uint256,uint256,uint256,bytes32,uint256),bytes)
const String chonNhanVang = 'bde86a9e';

/// vaoMan(uint256)
const String chonVaoMan = '8680c8b8';

/// mua(uint256)
const String chonMua = '27654f7a';

/// multicall(bytes[]) — OpenZeppelin Multicall
const String chonMulticall = 'ac9650d8';

/// balanceOf(address,uint256) — chuẩn ERC-1155
const String chonBalanceOf = '00fdd58e';

/// gia(uint256)
const String chonGia = '0bf25ad5';

/// daDoi(bytes32)
const String chonDaDoi = '8a53b475';

/// ve(address) → (man, so, coc)
const String chonVe = 'e5c297ba';

/// manChoi(uint256) → (coc, thuongToiDa)
const String chonManChoi = 'cd4fbdbe';

/// Phiếu vàng do máy chủ trọng tài ký — khớp `struct PhieuVang` trong hợp đồng.
class PhieuVang {
  final String nguoiChoi; // 0x + 40 hex
  final BigInt man;
  final BigInt ve; // 0 = màn luyện tập
  final BigInt soVang; // xu + thưởng (chưa gồm cọc hoàn lại)
  final String maVan; // 0x + 64 hex
  final BigInt hanChot;

  const PhieuVang({
    required this.nguoiChoi,
    required this.man,
    required this.ve,
    required this.soVang,
    required this.maVan,
    required this.hanChot,
  });

  factory PhieuVang.tuJson(Map<String, dynamic> j) => PhieuVang(
        nguoiChoi: j['nguoiChoi'] as String,
        man: BigInt.from(j['man'] as int),
        ve: BigInt.from(j['ve'] as int),
        soVang: BigInt.from(j['soVang'] as int),
        maVan: j['maVan'] as String,
        hanChot: BigInt.from(j['hanChot'] as int),
      );
}

/// Vé vào màn đang mở của một ví (`ve(address)` trên hợp đồng). `so == 0`: không có vé.
class VeVaoMan {
  final int man;
  final int so;
  final BigInt coc;

  const VeVaoMan({required this.man, required this.so, required this.coc});

  static final khong = VeVaoMan(man: 0, so: 0, coc: BigInt.zero);

  bool get dangMo => so != 0;
}

String boOx(String hex) =>
    hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;

/// Một "từ" ABI: số nguyên không âm, 32 byte, big-endian = 64 ký tự hex.
String tu(BigInt n) {
  if (n.isNegative || n.bitLength > 256) {
    throw ArgumentError('Giá trị $n không vừa uint256');
  }
  return n.toRadixString(16).padLeft(64, '0');
}

String _tuInt(int n) => tu(BigInt.from(n));

/// Địa chỉ 20 byte, đệm trái thành 32 byte.
String tuDiaChi(String diaChi) {
  final h = boOx(diaChi).toLowerCase();
  if (h.length != 40 || !RegExp(r'^[0-9a-f]+$').hasMatch(h)) {
    throw ArgumentError('Địa chỉ không hợp lệ: $diaChi');
  }
  return h.padLeft(64, '0');
}

String tuBytes32(String hex) {
  final h = boOx(hex).toLowerCase();
  if (h.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(h)) {
    throw ArgumentError('bytes32 phải đúng 32 byte');
  }
  return h;
}

/// Giá trị `bytes` ở phần đuôi: độ dài (1 từ) + dữ liệu đệm phải cho đủ bội số 32 byte.
String _duoiBytes(String hex) {
  final h = boOx(hex).toLowerCase();
  if (h.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(h)) {
    throw ArgumentError('Dữ liệu bytes không phải hex chẵn');
  }
  return '${_tuInt(h.length ~/ 2)}$h${'0' * ((64 - h.length % 64) % 64)}';
}

/// `nhanVang(phieu, chuKy)`: bộ toàn kiểu tĩnh nằm thẳng ở phần đầu (6 từ), tiếp theo là OFFSET
/// tới phần `bytes` (= 7 × 32 = 0xe0), rồi độ dài + chữ ký đệm phải.
String maHoaNhanVang(PhieuVang p, String chuKy) {
  if (boOx(chuKy).length != 130) {
    throw ArgumentError('Chữ ký phải đúng 65 byte (r‖s‖v)');
  }
  return '0x$chonNhanVang'
      '${tuDiaChi(p.nguoiChoi)}${tu(p.man)}${tu(p.ve)}${tu(p.soVang)}'
      '${tuBytes32(p.maVan)}${tu(p.hanChot)}'
      '${_tuInt(7 * 32)}'
      '${_duoiBytes(chuKy)}';
}

/// `multicall(bytes[] lenh)` — gộp nhiều lời gọi thành MỘT giao dịch (MetaMask hỏi một lần).
///
/// Bố cục: offset tới mảng (0x20) · số phần tử n · n offset (tính từ ngay sau từ "n") ·
/// rồi từng phần tử `bytes` (độ dài + dữ liệu đệm).
String maHoaMulticall(List<String> lenh) {
  final dau = StringBuffer();
  final duoi = StringBuffer();
  var offset = 32 * lenh.length;
  for (final l in lenh) {
    final phan = _duoiBytes(l);
    dau.write(_tuInt(offset));
    duoi.write(phan);
    offset += phan.length ~/ 2;
  }
  return '0x$chonMulticall${_tuInt(32)}${_tuInt(lenh.length)}$dau$duoi';
}

String maHoaVaoMan(int man) => '0x$chonVaoMan${_tuInt(man)}';

String maHoaMua(int nhanVat) => '0x$chonMua${_tuInt(nhanVat)}';

String maHoaBalanceOf(String vi, int id) => '0x$chonBalanceOf${tuDiaChi(vi)}${_tuInt(id)}';

String maHoaGia(int nhanVat) => '0x$chonGia${_tuInt(nhanVat)}';

String maHoaDaDoi(String maVan) => '0x$chonDaDoi${tuBytes32(maVan)}';

String maHoaVe(String vi) => '0x$chonVe${tuDiaChi(vi)}';

String maHoaManChoi(int man) => '0x$chonManChoi${_tuInt(man)}';

/// Đọc các uint256 liên tiếp từ kết quả `eth_call` ("0x" + 64·k hex). Thiếu thì coi là 0.
List<BigInt> docCacUint256(String ketQua, int soTu) {
  final h = boOx(ketQua);
  return [
    for (var i = 0; i < soTu; i++)
      (i + 1) * 64 <= h.length ? BigInt.parse(h.substring(i * 64, (i + 1) * 64), radix: 16) : BigInt.zero,
  ];
}

BigInt docUint256(String ketQua) => docCacUint256(ketQua, 1).first;

VeVaoMan docVe(String ketQua) {
  final w = docCacUint256(ketQua, 3);
  return VeVaoMan(man: w[0].toInt(), so: w[1].toInt(), coc: w[2]);
}
