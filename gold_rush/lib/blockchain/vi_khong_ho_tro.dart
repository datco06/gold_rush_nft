import 'vi.dart';

/// Android, iOS, máy tính: chưa có ví. Xem đề xuất dùng `reown_appkit` trong tài liệu.
class _ViKhongHoTro implements Vi {
  const _ViKhongHoTro();

  static const _loi = LoiVi(
      'Bản này chỉ kết nối MetaMask trên trình duyệt. Hãy chạy: flutter run -d chrome');

  @override
  bool get coSan => false;

  @override
  String get ten => 'Không có ví';

  @override
  Stream<SuKienVi> get suKien => const Stream.empty();

  @override
  Future<String> ketNoi() => Future.error(_loi);

  @override
  Future<List<String>> taiKhoan() async => const [];

  @override
  Future<int> chainId() => Future.error(_loi);

  @override
  Future<void> chuyenMang(int chainId, {String? tenMang, String? rpcUrl}) => Future.error(_loi);

  @override
  Future<String> goi({required String toi, required String duLieu, String? tu}) => Future.error(_loi);

  @override
  Future<String> maHopDong(String diaChi) => Future.error(_loi);

  @override
  Future<BigInt> uocLuongGas({required String tu, required String toi, required String duLieu}) =>
      Future.error(_loi);

  @override
  Future<BigInt> giaGas() => Future.error(_loi);

  @override
  Future<BigInt> soDu(String diaChi) => Future.error(_loi);

  @override
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  }) =>
      Future.error(_loi);

  @override
  Future<BienLai?> bienLai(String maGiaoDich) => Future.error(_loi);
}

Vi taoVi() => const _ViKhongHoTro();
