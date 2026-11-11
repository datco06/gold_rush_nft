/// Giao diện VÍ — mọi thứ app cần từ MetaMask, không phụ thuộc nền tảng.
///
/// Bản web (`vi_web.dart`) nói chuyện với MetaMask qua EIP-6963 (chọn đúng MetaMask khi trình duyệt có
/// nhiều ví) và EIP-1193 (`request({method, params})`). Bản Android/iOS chưa cài: hướng đề xuất là gói
/// `reown_appkit` (WalletConnect) cài đặt đúng giao diện này — phần còn lại của app không phải sửa.
///
/// Giao diện chỉ gồm các phương thức JSON-RPC THÔ. Mọi logic chống lỗi (kiểm tra mạng, mô phỏng, ước
/// lượng gas, chờ xác nhận theo trạng thái…) nằm ở `giao_dich.dart` — kiểm thử được bằng một ví giả.
library;

import 'vi_khong_ho_tro.dart' if (dart.library.js_interop) 'vi_web.dart' as nen_tang;

/// Phân loại lỗi để giao diện phản ứng đúng (ví dụ: người chơi tự từ chối thì không hiện chữ đỏ).
enum LoaiLoiVi {
  khac,
  tuChoi, // 4001 — người chơi bấm Từ chối
  dangCho, // -32002 — MetaMask đang mở một yêu cầu khác
  chuaCoMang, // 4902
  hopDongTuChoi, // revert khi mô phỏng hoặc khi vào khối
  thieuEth, // không đủ ETH trả phí gas
  saiNonce, // thường gặp khi khởi động lại `npx hardhat node`
  doiTaiKhoan, // tài khoản trong ví đã đổi giữa chừng
  chuaXacNhan, // quá lâu chưa thấy giao dịch vào khối (KHÔNG có nghĩa là thất bại)
}

/// Lỗi từ ví, kèm câu đọc được cho người chơi.
class LoiVi implements Exception {
  final String thongBao;

  /// Mã lỗi EIP-1193 nếu có: 4001 từ chối, 4902 chưa có mạng, -32002 đang chờ, 3/-32603 revert…
  final int? ma;

  /// Trường `data` của lỗi gốc (đã chuyển sang Map/List/String của Dart) — chứa dữ liệu revert.
  final Object? duLieu;

  /// Thông điệp gốc (tiếng Anh) của ví/nút RPC — để dò "nonce", "insufficient funds"…
  final String? thongDiepGoc;

  final LoaiLoiVi loai;

  const LoiVi(this.thongBao, {this.ma, this.duLieu, this.thongDiepGoc, this.loai = LoaiLoiVi.khac});

  bool get nguoiDungTuChoi => loai == LoaiLoiVi.tuChoi || ma == 4001;

  @override
  String toString() => thongBao;
}

/// Biên lai giao dịch (`eth_getTransactionReceipt`).
class BienLai {
  final bool thanhCong;
  final int? soKhoi;

  const BienLai({required this.thanhCong, this.soKhoi});
}

/// Sự kiện từ ví: người chơi đổi tài khoản hoặc đổi mạng ngay trong MetaMask.
sealed class SuKienVi {
  const SuKienVi();
}

class DoiTaiKhoan extends SuKienVi {
  final List<String> taiKhoan; // rỗng = người chơi ngắt kết nối trang
  const DoiTaiKhoan(this.taiKhoan);
}

class DoiMang extends SuKienVi {
  final int chainId;
  const DoiMang(this.chainId);
}

abstract interface class Vi {
  /// Có ví trong trình duyệt không (đã cài MetaMask chưa).
  bool get coSan;

  /// Tên ví đã chọn (EIP-6963 `info.name`), ví dụ "MetaMask".
  String get ten;

  /// Đổi tài khoản / đổi mạng trong ví (EIP-1193 `accountsChanged`, `chainChanged`).
  Stream<SuKienVi> get suKien;

  /// Xin quyền và trả về địa chỉ ví đang chọn (`eth_requestAccounts` — có thể hiện hộp thoại).
  Future<String> ketNoi();

  /// Tài khoản trang đang được phép xem (`eth_accounts` — KHÔNG hiện hộp thoại).
  Future<List<String>> taiKhoan();

  Future<int> chainId();

  /// Yêu cầu ví chuyển sang mạng [chainId]; nếu ví chưa biết mạng thì đề nghị thêm vào.
  Future<void> chuyenMang(int chainId, {String? tenMang, String? rpcUrl});

  /// Lời gọi chỉ đọc (`eth_call`). Có [tu] = MÔ PHỎNG giao dịch của ví đó (để biết trước có revert không).
  Future<String> goi({required String toi, required String duLieu, String? tu});

  /// Mã byte của hợp đồng (`eth_getCode`). "0x" = địa chỉ này KHÔNG có hợp đồng.
  Future<String> maHopDong(String diaChi);

  Future<BigInt> uocLuongGas({required String tu, required String toi, required String duLieu});

  Future<BigInt> giaGas();

  /// Số dư ETH (wei) để trả phí.
  Future<BigInt> soDu(String diaChi);

  /// Gửi giao dịch qua ví (MetaMask hiện hộp thoại xác nhận). Trả về mã giao dịch.
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  });

  /// null = chưa vào khối (hoặc đã bị thay bằng giao dịch "tăng tốc" mang mã khác).
  Future<BienLai?> bienLai(String maGiaoDich);
}

/// Ví mặc định của nền tảng đang chạy.
Vi taoViMacDinh() => nen_tang.taoVi();
