import 'vi.dart';

/// Kết quả một lần gửi.
enum KetQuaGui {
  /// Giao dịch đã vào khối và thành công.
  thanhCong,

  /// Không cần gửi: trạng thái mong muốn ĐÃ có sẵn trên chuỗi (ví dụ lần trước đã nhận phiếu này
  /// nhưng app hết giờ chờ). Không bao giờ trả phí hai lần cho cùng một việc.
  daXongTuTruoc,
}

typedef BaoTienDo = void Function(String buoc);

/// BỘ GIAO DỊCH — mọi giao dịch của app đi qua đây để tránh lỗi MetaMask tối đa.
///
/// Mỗi lần [gui] chạy đủ 9 bước; bước nào phát hiện vấn đề thì dừng TRƯỚC khi làm phiền người chơi:
///
///  1. Một lúc một giao dịch (single-flight) — bấm hai lần không mở hai hộp thoại (lỗi -32002).
///  2. Tài khoản trong ví vẫn là tài khoản app đang hiển thị (`eth_accounts`, không hiện hộp thoại).
///  3. Đúng mạng; sai thì xin chuyển, rồi KIỂM TRA LẠI (người chơi có thể bấm Huỷ).
///  4. Địa chỉ hợp đồng có mã (`eth_getCode`) — bắt lỗi kinh điển "khởi động lại hardhat node, hợp
///     đồng biến mất, app vẫn gửi vào địa chỉ cũ".
///  5. Đã xong từ trước chưa ([daXong]) — chống trả phí hai lần.
///  6. MÔ PHỎNG (`eth_call` với `from`): sẽ revert thì dịch lý do sang tiếng Việt, không mở MetaMask.
///  7. Ước lượng gas + 20% biên an toàn; kiểm số dư ETH đủ trả phí.
///  8. Gửi (`eth_sendTransaction`), MetaMask hiện hộp thoại DUY NHẤT.
///  9. Chờ: đọc biên lai, ĐỒNG THỜI kiểm trạng thái bằng [daXong] — khi người chơi bấm "Tăng tốc"
///     trong MetaMask, giao dịch mới mang mã KHÁC và mã cũ không bao giờ có biên lai.
class BoGiaoDich {
  final Vi vi;
  final int chainId;
  final String hopDong;
  final String? tenMang;
  final String? rpcUrl;
  final Duration choToiDa;
  final Duration nhipKiemTra;
  final Future<void> Function(Duration) _ngu;

  bool _dangGui = false;

  BoGiaoDich({
    required this.vi,
    required this.chainId,
    required this.hopDong,
    this.tenMang,
    this.rpcUrl,
    this.choToiDa = const Duration(minutes: 2),
    this.nhipKiemTra = const Duration(milliseconds: 1500),
    Future<void> Function(Duration)? ngu,
  }) : _ngu = ngu ?? Future<void>.delayed;

  /// Mạng Hardhat cục bộ: app tự đề nghị thêm vào MetaMask nếu ví chưa có.
  factory BoGiaoDich.choMang({required Vi vi, required int chainId, required String hopDong}) =>
      BoGiaoDich(
        vi: vi,
        chainId: chainId,
        hopDong: hopDong,
        tenMang: chainId == 31337 ? 'Hardhat cục bộ' : null,
        rpcUrl: chainId == 31337 ? 'http://127.0.0.1:8545' : null,
      );

  bool get dangGui => _dangGui;

  /// Bước 3: đúng mạng. Gọi cả lúc kết nối lẫn trước mỗi giao dịch.
  Future<void> damBaoMang() async {
    if (await vi.chainId() == chainId) return;
    await vi.chuyenMang(chainId, tenMang: tenMang, rpcUrl: rpcUrl);
    final sau = await vi.chainId();
    if (sau != chainId) {
      throw LoiVi('Ví đang ở mạng $sau, game cần mạng $chainId. Chọn lại mạng trong MetaMask.');
    }
  }

  /// Bước 2.
  Future<void> kiemTaiKhoan(String tu) async {
    final ds = await vi.taiKhoan();
    if (!ds.any((x) => x.toLowerCase() == tu.toLowerCase())) {
      throw LoiVi(
        ds.isEmpty
            ? 'Ví đã ngắt kết nối với trang — bấm "Kết nối MetaMask" lại.'
            : 'Tài khoản trong ví đã đổi (${rutGon(ds.first)}). Bấm "Kết nối MetaMask" lại để tải đúng ví.',
        loai: LoaiLoiVi.doiTaiKhoan,
      );
    }
  }

  /// Bước 4.
  Future<void> kiemHopDong() async {
    final ma = await vi.maHopDong(hopDong);
    if (ma == '0x' || ma.isEmpty || RegExp(r'^0x0*$').hasMatch(ma)) {
      throw LoiVi(
        'Không thấy hợp đồng ở ${rutGon(hopDong)} trên mạng $chainId. Nếu vừa khởi động lại '
        '"npx hardhat node": chạy lại lệnh ignition deploy, khởi động lại máy chủ, rồi tải lại trang.',
      );
    }
  }

  Future<KetQuaGui> gui({
    required String tu,
    required String duLieu,
    required String moTa,
    Future<bool> Function()? daXong,
    BaoTienDo? baoTienDo,
  }) async {
    if (_dangGui) {
      throw const LoiVi('Đang có một giao dịch chờ xác nhận — đợi xong rồi thử lại.',
          loai: LoaiLoiVi.dangCho);
    }
    _dangGui = true;
    void bao(String s) => baoTienDo?.call(s);
    try {
      bao('Kiểm tra ví, mạng và hợp đồng…');
      await kiemTaiKhoan(tu);
      await damBaoMang();
      await kiemHopDong();
      if (daXong != null && await daXong()) return KetQuaGui.daXongTuTruoc;

      bao('Mô phỏng giao dịch…');
      await vi.goi(toi: hopDong, duLieu: duLieu, tu: tu);
      final uoc = await vi.uocLuongGas(tu: tu, toi: hopDong, duLieu: duLieu);
      final gas = uoc * BigInt.from(12) ~/ BigInt.from(10); // +20% biên an toàn
      final phi = gas * await vi.giaGas();
      final coEth = await vi.soDu(tu);
      if (coEth < phi) {
        final goiY = chainId == 31337
            ? 'Nhập tài khoản thử của Hardhat (có sẵn 10 000 ETH ảo).'
            : 'Lấy ETH thử từ một faucet.';
        throw LoiVi(
          'Ví không đủ ETH trả phí: cần khoảng ${dinhDangEth(phi)} ETH, '
          'ví có ${dinhDangEth(coEth)} ETH. $goiY',
          loai: LoaiLoiVi.thieuEth,
        );
      }

      bao('Mở ${vi.ten}: xem phí rồi bấm Xác nhận — $moTa');
      final ma = await vi.guiGiaoDich(tu: tu, toi: hopDong, duLieu: duLieu, gas: gas);
      bao('Đã gửi ${rutGon(ma)} — chờ vào khối…');
      return await _choXacNhan(ma, tu, duLieu, daXong);
    } finally {
      _dangGui = false;
    }
  }

  Future<KetQuaGui> _choXacNhan(
    String ma,
    String tu,
    String duLieu,
    Future<bool> Function()? daXong,
  ) async {
    final soLan = (choToiDa.inMilliseconds / nhipKiemTra.inMilliseconds).ceil();
    for (var i = 0; i < soLan; i++) {
      BienLai? bl;
      try {
        bl = await vi.bienLai(ma);
      } on LoiVi {
        bl = null; // RPC chập chờn: thử lại ở nhịp sau
      }
      if (bl != null) {
        if (bl.thanhCong) return KetQuaGui.thanhCong;
        // Trạng thái đổi giữa lúc mô phỏng và lúc vào khối → mô phỏng lại để biết lý do.
        var lyDo = 'Giao dịch bị hợp đồng từ chối khi vào khối.';
        try {
          await vi.goi(toi: hopDong, duLieu: duLieu, tu: tu);
        } on LoiVi catch (e) {
          if (e.loai == LoaiLoiVi.hopDongTuChoi) lyDo = e.thongBao;
        }
        throw LoiVi(lyDo, loai: LoaiLoiVi.hopDongTuChoi);
      }
      if (daXong != null && i.isOdd) {
        try {
          if (await daXong()) return KetQuaGui.thanhCong; // giao dịch "tăng tốc" đã vào khối
        } on LoiVi {
          // bỏ qua, nhịp sau kiểm lại
        }
      }
      await _ngu(nhipKiemTra);
    }
    throw LoiVi(
      'Sau ${choToiDa.inSeconds} giây vẫn chưa thấy giao dịch vào khối. ĐỪNG gửi lại — mở MetaMask '
      'xem trạng thái; khi giao dịch xong, bấm "Làm mới".',
      loai: LoaiLoiVi.chuaXacNhan,
    );
  }
}

String rutGon(String hex) =>
    hex.length > 12 ? '${hex.substring(0, 6)}…${hex.substring(hex.length - 4)}' : hex;

/// wei → "0.000123" ETH (6 chữ số thập phân, đủ cho phí gas).
String dinhDangEth(BigInt wei) {
  final phanTrieu = wei * BigInt.from(1000000) ~/ BigInt.from(10).pow(18);
  final nguyen = phanTrieu ~/ BigInt.from(1000000);
  final le = (phanTrieu % BigInt.from(1000000)).toString().padLeft(6, '0');
  return '$nguyen.$le';
}
