import 'package:gold_rush/blockchain/abi.dart';
import 'package:gold_rush/blockchain/giao_dich.dart';
import 'package:gold_rush/blockchain/vi.dart';

const String hopDongThu = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
final String viThu = '0x${'a' * 40}';

/// Ví giả trong bộ nhớ — đóng vai MetaMask + nút RPC. Mỗi trường là một "núm vặn" để dựng tình huống lỗi.
class ViGia implements Vi {
  /// calldata → kết quả eth_call (hex). Không có → "0x" + 3 từ 0.
  final Map<String, String> ketQuaGoi = {};

  /// Mô phỏng (eth_call có `from`) / ước lượng gas ném lỗi này nếu khác null — giống nút RPC báo revert.
  LoiVi? loiMoPhong;

  List<String> danhSachTaiKhoan;
  int mang;

  /// Mạng sau khi người chơi "đồng ý" chuyển (đặt khác `mangCanChuyen` = người chơi bấm Huỷ).
  int? mangSauKhiChuyen;
  String maByte = '0x6080604052';
  BigInt gas = BigInt.from(100000);
  BigInt giaMoiGas = BigInt.from(1000000000);
  BigInt soDuEth = BigInt.from(10).pow(18);
  LoiVi? loiKhiGui;

  /// Biên lai trả về lần lượt mỗi lần hỏi; hết danh sách thì lặp phần tử cuối.
  List<BienLai?> bienLaiLanLuot = [const BienLai(thanhCong: true, soKhoi: 1)];

  /// Gọi khi gửi giao dịch — để test "đổi trạng thái chuỗi".
  void Function(String duLieu)? khiGui;

  final List<String> daGui = [];
  final List<BigInt?> gasDaGui = [];
  int soLanChuyenMang = 0;
  int soLanHoiBienLai = 0;

  ViGia({List<String>? taiKhoan, this.mang = 31337})
      : danhSachTaiKhoan = taiKhoan ?? [viThu];

  void datSo(String calldata, BigInt giaTri) => ketQuaGoi[calldata] = '0x${tu(giaTri)}';

  void datVe(String vi, {required int man, required int so, required int coc}) =>
      ketQuaGoi[maHoaVe(vi)] = '0x${tu(BigInt.from(man))}${tu(BigInt.from(so))}${tu(BigInt.from(coc))}';

  @override
  bool get coSan => true;

  @override
  String get ten => 'Ví giả';

  @override
  Stream<SuKienVi> get suKien => const Stream.empty();

  @override
  Future<String> ketNoi() async => danhSachTaiKhoan.first;

  @override
  Future<List<String>> taiKhoan() async => danhSachTaiKhoan;

  @override
  Future<int> chainId() async => mang;

  @override
  Future<void> chuyenMang(int chainId, {String? tenMang, String? rpcUrl}) async {
    soLanChuyenMang++;
    mang = mangSauKhiChuyen ?? chainId;
  }

  @override
  Future<String> goi({required String toi, required String duLieu, String? tu}) async {
    if (tu != null && loiMoPhong != null) throw loiMoPhong!;
    return ketQuaGoi[duLieu] ?? '0x${'0' * 192}';
  }

  @override
  Future<String> maHopDong(String diaChi) async => maByte;

  @override
  Future<BigInt> uocLuongGas({required String tu, required String toi, required String duLieu}) async {
    if (loiMoPhong != null) throw loiMoPhong!;
    return gas;
  }

  @override
  Future<BigInt> giaGas() async => giaMoiGas;

  @override
  Future<BigInt> soDu(String diaChi) async => soDuEth;

  @override
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  }) async {
    if (loiKhiGui != null) throw loiKhiGui!;
    daGui.add(duLieu);
    gasDaGui.add(gas);
    khiGui?.call(duLieu);
    return '0x${'f' * 64}';
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    final i = soLanHoiBienLai++;
    return bienLaiLanLuot[i < bienLaiLanLuot.length ? i : bienLaiLanLuot.length - 1];
  }
}

/// Bộ giao dịch chạy NHANH trong test: không ngủ thật.
BoGiaoDich boThu(ViGia vi, {Duration choToiDa = const Duration(seconds: 6)}) => BoGiaoDich(
      vi: vi,
      chainId: 31337,
      hopDong: hopDongThu,
      rpcUrl: 'http://127.0.0.1:8545',
      choToiDa: choToiDa,
      nhipKiemTra: const Duration(seconds: 1),
      ngu: (_) async {},
    );
