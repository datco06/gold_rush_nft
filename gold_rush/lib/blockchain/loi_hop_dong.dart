/// Dịch lỗi REVERT của hợp đồng sang câu tiếng Việt — trước khi MetaMask kịp hiện hộp thoại.
///
/// Khi `eth_call`/`eth_estimateGas` mô phỏng một giao dịch sẽ thất bại, nút RPC trả về "dữ liệu revert":
/// 4 byte bộ chọn của lỗi tuỳ biến (custom error) + tham số mã hoá ABI. MetaMask bọc dữ liệu đó trong
/// đối tượng lỗi theo nhiều kiểu khác nhau tuỳ phiên bản (`error.data`, `error.data.data`,
/// `error.data.originalError.data`…), nên [timDuLieuRevert] lục tìm đệ quy.
///
/// Bộ chọn lỗi tính bằng Python (`sinh_abi_mau.py`, mục "loi") và được Hardhat đối chiếu với ABI thật.
library;

import 'dart:convert';

import 'abi.dart';
import 'vi.dart';

/// Bộ chọn (0x + 8 hex) → tên lỗi trong `CuaHangGoldRush.sol` / OpenZeppelin.
const Map<String, String> boChonLoi = {
  '0x9dcbecd8': 'KhongChuyenNhuong',
  '0xea1072d0': 'SaiNguoiNhan',
  '0x5f03bf35': 'PhieuHetHan',
  '0xd2725e2c': 'PhieuDaDung',
  '0xf5b1d64b': 'SoVangKhongHopLe',
  '0xcb098626': 'ChuKySai',
  '0x37805037': 'KhongBan',
  '0x1427af6a': 'DaCo',
  '0x3fe2af7e': 'DiaChiRong',
  '0x92141172': 'ManKhongTonTai',
  '0x1623efa8': 'ManMienPhi',
  '0x1cc576f1': 'SaiVe',
  '0x03dee4c5': 'ERC1155InsufficientBalance',
};

const String _chonErrorString = '0x08c379a0'; // Error(string) — require(..., "lý do")
const String _chonPanic = '0x4e487b71'; // Panic(uint256) — tràn số, chia 0…

/// Câu tiếng Việt cho từng lỗi. Viết cho NGƯỜI CHƠI: nói chuyện gì xảy ra và nên làm gì.
String _cauChoLoi(String ten, List<BigInt> thamSo) => switch (ten) {
      'KhongChuyenNhuong' => 'Vàng và nhân vật không chuyển nhượng được.',
      'SaiNguoiNhan' => 'Phiếu này cấp cho ví khác với ví đang kết nối.',
      'PhieuHetHan' => 'Phiếu đã hết hạn — bấm lại để app xin phiếu mới.',
      'PhieuDaDung' => 'Phiếu này đã được nhận rồi.',
      'SoVangKhongHopLe' => 'Số vàng trên phiếu vượt mức cho phép của màn.',
      'ChuKySai' => 'Chữ ký phiếu không khớp trọng tài của hợp đồng '
          '(máy chủ và hợp đồng đang dùng hai khoá khác nhau).',
      'KhongBan' => 'Nhân vật này chưa được bán.',
      'DaCo' => 'Bạn đã có nhân vật này.',
      'ManKhongTonTai' => 'Màn ${thamSo.isEmpty ? '' : thamSo.first} chưa được mở trên hợp đồng '
          '(chạy lại lệnh ignition deploy).',
      'ManMienPhi' => 'Màn luyện tập không cần vé.',
      'SaiVe' => 'Vé không khớp: vé của ván này đã bị thay bằng vé mới (cọc cũ đã mất).',
      'ERC1155InsufficientBalance' => thamSo.length >= 3
          ? 'Không đủ vàng: có ${thamSo[1]}, cần ${thamSo[2]}.'
          : 'Không đủ vàng.',
      _ => 'Hợp đồng từ chối ($ten).',
    };

/// Tìm chuỗi hex dữ liệu revert trong đối tượng lỗi (đã `dartify`) — đệ quy, ưu tiên khoá `data`.
String? timDuLieuRevert(Object? loi, [int sau = 0]) {
  if (sau > 6 || loi == null) return null;
  if (loi is String) {
    final m = RegExp(r'0x[0-9a-fA-F]{8,}').firstMatch(loi);
    return (m != null && m.group(0)!.length.isEven) ? m.group(0) : null;
  }
  if (loi is Map) {
    for (final khoa in ['data', 'originalError', 'error', 'cause']) {
      final kq = timDuLieuRevert(loi[khoa], sau + 1);
      if (kq != null) return kq;
    }
    return null;
  }
  if (loi is List) {
    for (final x in loi) {
      final kq = timDuLieuRevert(x, sau + 1);
      if (kq != null) return kq;
    }
  }
  return null;
}

/// Hardhat node còn ghi sẵn tên lỗi trong thông điệp: "reverted with custom error 'SaiVe()'".
String? _tenTrongThongDiep(String? thongDiep) =>
    thongDiep == null ? null : RegExp(r"custom error '(\w+)\(").firstMatch(thongDiep)?.group(1);

/// Dịch dữ liệu revert (và/hoặc thông điệp lỗi) thành câu cho người chơi. null = không phải lỗi revert.
String? dichLoiHopDong({Object? duLieu, String? thongDiep}) {
  final hex = timDuLieuRevert(duLieu) ?? timDuLieuRevert(thongDiep);
  if (hex != null && hex.length >= 10) {
    final chon = hex.substring(0, 10).toLowerCase();
    final than = hex.substring(10);
    final ten = boChonLoi[chon];
    if (ten != null) return _cauChoLoi(ten, docCacUint256(than, than.length ~/ 64));
    if (chon == _chonErrorString) return 'Hợp đồng từ chối: ${_docChuoiAbi(than) ?? 'không rõ lý do'}.';
    if (chon == _chonPanic) return 'Hợp đồng gặp lỗi tính toán (Panic).';
  }
  final ten = _tenTrongThongDiep(thongDiep);
  if (ten != null) return _cauChoLoi(ten, const []);
  if (thongDiep != null && thongDiep.toLowerCase().contains('revert')) {
    return 'Hợp đồng từ chối giao dịch.';
  }
  return null;
}

/// Error(string): offset (1 từ) · độ dài (1 từ) · byte UTF-8.
String? _docChuoiAbi(String than) {
  try {
    final w = docCacUint256(than, 2);
    final dai = w[1].toInt();
    const batDau = 128;
    if (than.length < batDau + dai * 2) return null;
    final h = than.substring(batDau, batDau + dai * 2);
    final bytes = [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// Biến lỗi thô của ví (mã + thông điệp + data) thành [LoiVi] đã phân loại, câu chữ cho người chơi.
///
/// Đây là chỗ gom kinh nghiệm "MetaMask hay báo lỗi gì" — mỗi nhánh là một lỗi sinh viên gặp thật.
LoiVi taoLoiVi({int? ma, String? thongDiep, Object? duLieu}) {
  final tm = (thongDiep ?? '').toLowerCase();
  LoiVi loi(String cau, LoaiLoiVi loai) =>
      LoiVi(cau, ma: ma, duLieu: duLieu, thongDiepGoc: thongDiep, loai: loai);

  if (ma == 4001 || tm.contains('user rejected') || tm.contains('user denied')) {
    return loi('Bạn đã từ chối trong ví — chưa có gì thay đổi.', LoaiLoiVi.tuChoi);
  }
  if (ma == -32002 || tm.contains('already pending')) {
    return loi('MetaMask đang mở một yêu cầu khác. Bấm biểu tượng MetaMask trên thanh công cụ '
        'để xử lý yêu cầu đó trước.', LoaiLoiVi.dangCho);
  }
  if (ma == 4902) return loi('Ví chưa có mạng này.', LoaiLoiVi.chuaCoMang);
  if (ma == 4100) {
    return loi('Trang chưa được ví cho phép — bấm "Kết nối MetaMask" lại.', LoaiLoiVi.doiTaiKhoan);
  }
  final hopDong = dichLoiHopDong(duLieu: duLieu, thongDiep: thongDiep);
  if (hopDong != null) return loi(hopDong, LoaiLoiVi.hopDongTuChoi);
  if (tm.contains('nonce')) {
    return loi('Ví đang nhớ thứ tự giao dịch (nonce) của một chuỗi cũ — thường do vừa khởi động lại '
        '"npx hardhat node". Trong MetaMask: Cài đặt → Nâng cao → Xoá dữ liệu tab hoạt động, '
        'rồi thử lại.', LoaiLoiVi.saiNonce);
  }
  if (tm.contains('insufficient funds')) {
    return loi('Ví không đủ ETH để trả phí giao dịch.', LoaiLoiVi.thieuEth);
  }
  return loi('Ví báo lỗi: ${thongDiep == null || thongDiep.isEmpty ? 'không rõ' : thongDiep}',
      LoaiLoiVi.khac);
}
