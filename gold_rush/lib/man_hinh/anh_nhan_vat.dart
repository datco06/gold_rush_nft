import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/anh_nhan_vat.dart';
import '../ai/may_chu_nhan_vat.dart';
import '../ai/may_chu_tien_trinh.dart';
import '../ai/nhan_vat_ai_models.dart';
import '../ai/tien_trinh_controller.dart';
import '../auth/auth_controller.dart';
import '../blockchain/abi_dang_ky_nhan_vat.dart';
import '../blockchain/vi.dart';
import '../cau_hinh.dart';
import '../components/ui/gold_rush_top_bar.dart';

class ManHinhAnhNhanVat extends StatefulWidget {
  final MayChuNhanVat mayChu;
  final Vi? vi;
  final bool kiemTraPhienTuDong;
  final AuthController? authController;
  final TienTrinhController? tienTrinhController;
  final MayChuTienTrinh? mayChuTienTrinh;
  final VoidCallback? onRungRuong;
  final bool tuDongLuuSauKhiTao;

  const ManHinhAnhNhanVat({
    super.key,
    required this.mayChu,
    this.vi,
    this.kiemTraPhienTuDong = false,
    this.authController,
    this.tienTrinhController,
    this.mayChuTienTrinh,
    this.onRungRuong,
    this.tuDongLuuSauKhiTao = false,
  });

  @override
  State<ManHinhAnhNhanVat> createState() => _ManHinhAnhNhanVatState();
}

class _ManHinhAnhNhanVatState extends State<ManHinhAnhNhanVat> {
  final _form = GlobalKey<FormState>();
  final _formLuu = GlobalKey<FormState>();
  final _moTa = TextEditingController();
  final _tenNhanVat = TextEditingController(text: 'Thợ mỏ vàng AI');

  late final Vi _vi;
  StreamSubscription<SuKienVi>? _ngheVi;

  KetQuaAnhNhanVat? _ketQua;
  AnhNhanVat? _anh;
  String? _maYeuCau;
  String? _moTaDaGui;

  bool _dangTai = false;
  bool _dangTao = false;
  bool _dangLuu = false;
  bool _dangKetNoiAuth = false;
  bool _dangDangKyOnchain = false;
  int _phienTai = 0;
  Timer? _boDemTaoAnh;

  // Trạng thái phiên SIWE & CSRF
  NguoiDungAuth? _nguoiDung;
  bool _dangKiemTraPhien = false;

  // Danh sách nhân vật thuộc tài khoản
  List<ThongTinNhanVat> _danhSachNhanVat = const [];
  bool _dangTaiDanhSach = false;
  ThongTinNhanVat? _nhanVatVuaLuu;
  final Map<String, Uint8List> _anhNhanVatDaLuu = {};
  final Set<String> _anhNhanVatLoi = {};
  int _phienDanhSach = 0;

  // Trạng thái tiến trình chơi màn AI
  TienTrinhController? _tienTrinh;
  bool _tienTrinhOwned = false;

  @override
  void initState() {
    super.initState();
    _vi = widget.vi ?? taoViMacDinh();
    _ngheVi = _vi.suKien.listen(_xuLySuKienVi);
    _khoiTaoTienTrinh();
    if (widget.authController != null) {
      widget.authController!.addListener(_khiAuthDoi);
      _dongBoTuAuthController();
    } else if (widget.kiemTraPhienTuDong) {
      _kiemTraPhien();
    }
  }

  void _khoiTaoTienTrinh() {
    if (widget.tienTrinhController != null) {
      _tienTrinh = widget.tienTrinhController;
      _tienTrinhOwned = false;
    } else if (widget.authController != null) {
      _tienTrinh = TienTrinhController(
        mayChu:
            widget.mayChuTienTrinh ??
            MayChuTienTrinh(
              mayChu:
                  widget.mayChu.mayChu?.toString() ??
                  const String.fromEnvironment(
                    'GOLD_RUSH_API',
                    defaultValue: 'http://localhost:8000',
                  ),
            ),
        authController: widget.authController,
      );
      _tienTrinhOwned = true;
    }
    _tienTrinh?.addListener(_khiTienTrinhDoi);
    if (_tienTrinh != null &&
        _tienTrinh!.tienTrinh == null &&
        !_tienTrinh!.dangTai) {
      unawaited(_tienTrinh!.taiTienTrinh());
    }
  }

  void _khiTienTrinhDoi() {
    if (mounted) setState(() {});
  }

  void _dongBoTuAuthController() {
    final auth = widget.authController;
    if (auth != null && auth.canEnterGame && auth.user != null) {
      _nguoiDung = NguoiDungAuth(
        userId: auth.user!.id,
        walletAddress: auth.user!.walletAddress,
        username: auth.user!.username,
        csrfToken: auth.csrfToken,
      );
      unawaited(_taiDanhSachNhanVat());
    } else {
      _phienDanhSach++;
      _nguoiDung = null;
      _danhSachNhanVat = const [];
      _nhanVatVuaLuu = null;
      _anhNhanVatDaLuu.clear();
      _anhNhanVatLoi.clear();
    }
  }

  void _khiAuthDoi() {
    if (!mounted) return;
    final auth = widget.authController;
    if (auth == null) return;

    if (!auth.canEnterGame) {
      setState(() {
        _phienDanhSach++;
        _nguoiDung = null;
        _danhSachNhanVat = const [];
        _nhanVatVuaLuu = null;
        _anhNhanVatDaLuu.clear();
        _anhNhanVatLoi.clear();
      });
      return;
    }

    final currentUser = auth.user;
    if (currentUser != null &&
        (_nguoiDung == null ||
            _nguoiDung!.walletAddress.toLowerCase() !=
                currentUser.walletAddress.toLowerCase() ||
            _nguoiDung!.csrfToken != auth.csrfToken)) {
      setState(() {
        _nguoiDung = NguoiDungAuth(
          userId: currentUser.id,
          walletAddress: currentUser.walletAddress,
          username: currentUser.username,
          csrfToken: auth.csrfToken,
        );
      });
      unawaited(_taiDanhSachNhanVat());
    }
  }

  void _xuLySuKienVi(SuKienVi sk) {
    if (sk is DoiTaiKhoan) {
      final taiKhoanMoi = sk.taiKhoan.isEmpty
          ? null
          : sk.taiKhoan.first.toLowerCase();
      final taiKhoanHienTai = _nguoiDung?.walletAddress.toLowerCase();
      if (taiKhoanMoi != taiKhoanHienTai) {
        setState(() {
          _phienDanhSach++;
          _nguoiDung = null;
          _danhSachNhanVat = const [];
          _nhanVatVuaLuu = null;
          _anhNhanVatDaLuu.clear();
          _anhNhanVatLoi.clear();
        });
        _thongBao(
          'Tài khoản ví MetaMask đã thay đổi. Vui lòng đăng nhập lại SIWE.',
        );
        if (widget.authController != null) {
          _dongBoTuAuthController();
        } else if (widget.kiemTraPhienTuDong) {
          _kiemTraPhien();
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant ManHinhAnhNhanVat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authController, widget.authController)) {
      oldWidget.authController?.removeListener(_khiAuthDoi);
      widget.authController?.addListener(_khiAuthDoi);
      _dongBoTuAuthController();
    }
    if (!identical(oldWidget.tienTrinhController, widget.tienTrinhController) ||
        !identical(oldWidget.authController, widget.authController)) {
      _tienTrinh?.removeListener(_khiTienTrinhDoi);
      if (_tienTrinhOwned) {
        _tienTrinh?.dispose();
      }
      _khoiTaoTienTrinh();
    }
    if (!identical(oldWidget.mayChu, widget.mayChu)) {
      _phienTai++;
      _ketQua = null;
      _anh = null;
      _maYeuCau = null;
      _moTaDaGui = null;
      _dangTai = false;
      _dangTao = false;
      _dangLuu = false;
      _form.currentState?.reset();
      _moTa.clear();
      if (widget.authController != null) {
        _dongBoTuAuthController();
      } else if (widget.kiemTraPhienTuDong) {
        _kiemTraPhien();
      }
    }
  }

  @override
  void dispose() {
    _boDemTaoAnh?.cancel();
    _tienTrinh?.removeListener(_khiTienTrinhDoi);
    if (_tienTrinhOwned) {
      _tienTrinh?.dispose();
    }
    widget.authController?.removeListener(_khiAuthDoi);
    _ngheVi?.cancel();
    _moTa.dispose();
    _tenNhanVat.dispose();
    super.dispose();
  }

  void _thongBao(String msg, {bool loi = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: loi ? Colors.red.shade900 : CauHinh.mauChinh,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Quản lý Phiên SIWE & CSRF
  // --------------------------------------------------------------------------

  Future<void> _kiemTraPhien() async {
    setState(() => _dangKiemTraPhien = true);
    final kq = await widget.mayChu.kiemTraPhien();
    if (!mounted) return;
    setState(() {
      _dangKiemTraPhien = false;
      _nguoiDung = kq.nguoiDung;
    });
    if (_nguoiDung != null) {
      await _taiDanhSachNhanVat();
    }
  }

  Future<void> _dangNhapSiwe() async {
    if (_dangKetNoiAuth) return;
    setState(() => _dangKetNoiAuth = true);

    if (widget.authController != null) {
      try {
        await widget.authController!.connectAndSignIn();
        if (!mounted) return;
        _dongBoTuAuthController();
        if (_nguoiDung != null) {
          _thongBao('Đăng nhập MetaMask SIWE thành công!');
        }
      } catch (e) {
        _thongBao('Không thể hoàn tất đăng nhập: $e', loi: true);
      } finally {
        if (mounted) setState(() => _dangKetNoiAuth = false);
      }
      return;
    }

    try {
      if (!_vi.coSan) {
        _thongBao(
          'Chưa tìm thấy tiện ích MetaMask trên trình duyệt.',
          loi: true,
        );
        return;
      }

      final diaChi = await _vi.ketNoi();
      final chainId = await _vi.chainId();

      // 1. Tạo challenge EIP-4361 từ Backend
      final chal = await widget.mayChu.taoChallenge(
        diaChiVi: diaChi,
        chainId: chainId,
      );
      if (chal.loi != null ||
          chal.challengeId == null ||
          chal.message == null) {
        _thongBao('Không thể khởi tạo thử thách SIWE từ máy chủ.', loi: true);
        return;
      }

      // 2. Ký thông điệp qua MetaMask (personal_sign)
      final signature = await _vi.kyThongDiep(
        diaChi: diaChi,
        thongDiep: chal.message!,
      );

      // 3. Xác minh chữ ký với Backend (nhận cookie gr_session & csrf_token)
      final ver = await widget.mayChu.xacMinhSiwe(
        challengeId: chal.challengeId!,
        message: chal.message!,
        signature: signature,
      );

      if (ver.nguoiDung != null) {
        setState(() => _nguoiDung = ver.nguoiDung);
        _thongBao('Đăng nhập MetaMask SIWE thành công!');
        await _taiDanhSachNhanVat();
      } else {
        _thongBao(ver.thongBao ?? 'Xác thực chữ ký SIWE thất bại.', loi: true);
      }
    } on LoiVi catch (e) {
      _thongBao(
        e.nguoiDungTuChoi
            ? 'Bạn đã hủy ký xác thực SIWE.'
            : 'Lỗi ví: ${e.thongBao}',
        loi: !e.nguoiDungTuChoi,
      );
    } catch (e) {
      _thongBao('Không thể hoàn tất đăng nhập: $e', loi: true);
    } finally {
      if (mounted) setState(() => _dangKetNoiAuth = false);
    }
  }

  Future<void> _dangXuat() async {
    if (widget.authController != null) {
      await widget.authController!.logout();
      if (!mounted) return;
      setState(() {
        _phienDanhSach++;
        _nguoiDung = null;
        _danhSachNhanVat = const [];
        _nhanVatVuaLuu = null;
        _anhNhanVatDaLuu.clear();
        _anhNhanVatLoi.clear();
      });
      _thongBao('Đã đăng xuất phiên MetaMask an toàn.');
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final csrf = _nguoiDung?.csrfToken;
    await widget.mayChu.dangXuat(csrfToken: csrf);
    if (!mounted) return;
    setState(() {
      _phienDanhSach++;
      _nguoiDung = null;
      _danhSachNhanVat = const [];
      _nhanVatVuaLuu = null;
      _anhNhanVatDaLuu.clear();
      _anhNhanVatLoi.clear();
    });
    _thongBao('Đã đăng xuất phiên MetaMask an toàn.');
  }

  Future<void> _taiDanhSachNhanVat() async {
    if (_nguoiDung == null) return;
    final phien = ++_phienDanhSach;
    setState(() => _dangTaiDanhSach = true);
    final kq = await widget.mayChu.layDanhSach();
    if (!mounted || phien != _phienDanhSach) return;
    setState(() {
      _dangTaiDanhSach = false;
      if (kq.loi == null) {
        _danhSachNhanVat = kq.danhSach;
        final ids = kq.danhSach.map((e) => e.characterId).toSet();
        _anhNhanVatDaLuu.removeWhere((id, _) => !ids.contains(id));
        _anhNhanVatLoi.removeWhere((id) => !ids.contains(id));
      }
    });
    if (kq.loi == null) {
      await _taiAnhDanhSach(kq.danhSach, phien);
    }
  }

  Future<void> _taiAnhDanhSach(
    List<ThongTinNhanVat> danhSach,
    int phien,
  ) async {
    await Future.wait(
      danhSach.map((nv) async {
        if (_anhNhanVatDaLuu.containsKey(nv.characterId)) return;
        final kq = await widget.mayChu.taiAnhDaLuu(nv.characterId);
        if (!mounted || phien != _phienDanhSach) return;
        setState(() {
          if (kq.png != null) {
            _anhNhanVatDaLuu[nv.characterId] = kq.png!;
            _anhNhanVatLoi.remove(nv.characterId);
          } else {
            _anhNhanVatLoi.add(nv.characterId);
          }
        });
      }),
    );
  }

  // --------------------------------------------------------------------------
  // Tạo & Xem Trước Ảnh Nhân Vật AI
  // --------------------------------------------------------------------------

  void _doiMoTa(String _) {
    setState(() {
      _ketQua = null;
      _anh = null;
      _maYeuCau = null;
      _moTaDaGui = null;
      _nhanVatVuaLuu = null;
    });
  }

  Future<void> _tao({bool thuLai = false}) async {
    if (_dangTai || !(_form.currentState?.validate() ?? false)) return;
    if (_tienTrinh != null && !_tienTrinh!.isCharacterUnlocked) {
      _thongBao(
        'Cần hoàn thành đủ 6 màn chơi để mở khóa tạo nhân vật AI (${_tienTrinh!.tongManHoanThanh}/6).',
        loi: true,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    if (!thuLai) {
      _maYeuCau = _taoMaYeuCau();
      _moTaDaGui = _moTa.text.trim();
    }
    final ma = _maYeuCau;
    final moTa = _moTaDaGui;
    if (ma == null || moTa == null) return;
    final api = widget.mayChu;
    final phien = ++_phienTai;
    setState(() {
      _dangTai = true;
      _dangTao = true;
      _anh = null;
      _ketQua = null;
      _nhanVatVuaLuu = null;
    });
    _batDauBoDemTaoAnh(phien);
    try {
      final kq = await api
          .tao(moTa: moTa, maYeuCau: ma)
          .timeout(const Duration(seconds: 65));
      if (!mounted || phien != _phienTai) return;
      if (kq.loi != null) {
        setState(() {
          _ketQua = kq;
        });
        return;
      }
      final anh = kq.anh;
      if (anh == null) {
        setState(() {
          _ketQua = const KetQuaAnhNhanVat.thatBai(
            LoiAnhNhanVat.phanHoiKhongHopLe,
          );
        });
        return;
      }
      _anh = anh;
      await _taiVaHienThi(api, anh, phien);
    } on TimeoutException {
      _ketThucVoiLoi(phien, LoiAnhNhanVat.hetThoiGian);
    } catch (_) {
      _ketThucVoiLoi(phien, LoiAnhNhanVat.ketNoi);
    } finally {
      // Luôn mở khóa nút tạo khi model/API trả lỗi bất ngờ hoặc payload sai.
      _ketThucLoading(phien);
    }
  }

  Future<void> _taiLai() async {
    final anh = _anh;
    if (_dangTai || anh == null) return;
    final phien = ++_phienTai;
    setState(() {
      _dangTai = true;
      _ketQua = null;
    });
    _batDauBoDemTaoAnh(phien);
    await _taiVaHienThi(widget.mayChu, anh, phien);
  }

  Future<void> _taiVaHienThi(
    MayChuNhanVat api,
    AnhNhanVat anh,
    int phien,
  ) async {
    if (mounted && phien == _phienTai) {
      setState(() => _dangTao = false);
    }
    try {
      // Ảnh đã được cache ở backend sau bước tạo; nếu endpoint tải ảnh
      // không phản hồi nhanh thì kết thúc trạng thái loading để người dùng
      // có thể thử lại, không khóa màn hình theo timeout tạo ảnh 60 giây.
      final kq = await api.tai(anh).timeout(const Duration(seconds: 10));
      if (!mounted || phien != _phienTai) return;
      setState(() {
        _dangTai = false;
        _dangTao = false;
        _ketQua = kq;
      });
      if (kq.png != null && widget.tuDongLuuSauKhiTao && _nguoiDung != null) {
        await _luuNhanVat(tuDong: true);
      }
    } on TimeoutException {
      _ketThucVoiLoi(phien, LoiAnhNhanVat.hetThoiGian);
    } catch (_) {
      _ketThucVoiLoi(phien, LoiAnhNhanVat.ketNoi);
    } finally {
      _ketThucLoading(phien);
    }
  }

  void _ketThucLoading(int phien) {
    if (!mounted || phien != _phienTai || (!_dangTai && !_dangTao)) return;
    _boDemTaoAnh?.cancel();
    _boDemTaoAnh = null;
    setState(() {
      _dangTai = false;
      _dangTao = false;
    });
  }

  void _ketThucVoiLoi(int phien, LoiAnhNhanVat loi) {
    if (!mounted || phien != _phienTai) return;
    _boDemTaoAnh?.cancel();
    _boDemTaoAnh = null;
    setState(() {
      _dangTai = false;
      _dangTao = false;
      _ketQua = KetQuaAnhNhanVat.thatBai(loi);
    });
  }

  void _batDauBoDemTaoAnh(int phien) {
    _boDemTaoAnh?.cancel();
    // API tạo ảnh tối đa 45 giây, tải/giải mã preview tối đa 10 giây.
    // Watchdog này là lớp bảo vệ cuối cùng cho Flutter Web khi stream bị treo.
    _boDemTaoAnh = Timer(const Duration(seconds: 60), () {
      if (!mounted || phien != _phienTai || !_dangTai) return;
      _ketThucVoiLoi(phien, LoiAnhNhanVat.hetThoiGian);
    });
  }

  // --------------------------------------------------------------------------
  // Lưu Nhân Vật Chính Thức & Đăng Ký On-Chain
  // --------------------------------------------------------------------------

  Future<void> _luuNhanVat({bool tuDong = false}) async {
    final anh = _anh;
    if (anh == null || _dangLuu) return;
    if (_nguoiDung == null) {
      _thongBao(
        'Cần đăng nhập MetaMask SIWE trước khi lưu nhân vật.',
        loi: true,
      );
      return;
    }
    final ten = _tenNhanVat.text.trim();
    if (ten.isEmpty || ten.runes.length > 32) {
      if (!tuDong) {
        _thongBao('Tên nhân vật phải từ 1 đến 32 ký tự.', loi: true);
      }
      return;
    }

    setState(() => _dangLuu = true);
    final kq = await widget.mayChu.luu(
      imageId: anh.maAnh,
      ten: ten,
      csrfToken: _nguoiDung?.csrfToken,
    );

    if (!mounted) return;
    setState(() => _dangLuu = false);

    if (kq.thanhCong) {
      setState(() => _nhanVatVuaLuu = kq.nhanVat);
      _thongBao(
        tuDong
            ? 'Ảnh đã tạo xong và được tự động lưu vào tài khoản!'
            : 'Đã lưu nhân vật "${kq.nhanVat!.name}" thành công vào tài khoản!',
      );
      await _taiDanhSachNhanVat();
    } else {
      _thongBao(
        kq.chiTietLoi ??
            'Lưu nhân vật thất bại (${kq.maHttp ?? 'Lỗi kết nối'}).',
        loi: true,
      );
    }
  }

  Future<void> _dangKyOnchain(ThongTinNhanVat nv) async {
    if (_dangDangKyOnchain) return;
    if (_nguoiDung == null) {
      _thongBao('Cần đăng nhập MetaMask SIWE để đăng ký on-chain.', loi: true);
      return;
    }

    setState(() => _dangDangKyOnchain = true);

    try {
      // 1. Yêu cầu Backend cấp EIP-712 Voucher
      final phieuKq = await widget.mayChu.xinKyVoucher(
        characterId: nv.characterId,
        csrfToken: _nguoiDung?.csrfToken,
      );

      if (!phieuKq.thanhCong || phieuKq.phieu == null) {
        _thongBao(
          phieuKq.chiTietLoi ?? 'Máy chủ từ chối cấp Voucher EIP-712.',
          loi: true,
        );
        return;
      }

      final phieu = phieuKq.phieu!;

      // 2. Kiểm tra đúng chainId
      final currentChain = await _vi.chainId();
      if (currentChain != phieu.chainId) {
        await _vi.chuyenMang(phieu.chainId);
      }

      // 3. Mã hoá calldata registerCharacter theo ABI
      final calldata = maHoaDangKyNhanVat(phieu.voucher, phieu.signature);

      // 4. Người chơi xác nhận giao dịch bằng MetaMask
      final txHash = await _vi.guiGiaoDich(
        tu: phieu.voucher.owner,
        toi: phieu.contractAddress,
        duLieu: calldata,
      );

      _thongBao('Đã gửi giao dịch on-chain! Tx: ${txHash.substring(0, 10)}…');

      // 5. Gửi transaction hash để Backend RPC Verifier đối soát
      final xacMinhKq = await widget.mayChu.xacMinhOnchain(
        characterId: nv.characterId,
        transactionHash: txHash,
        csrfToken: _nguoiDung?.csrfToken,
      );

      if (xacMinhKq.thanhCong) {
        final trangThai = xacMinhKq.nhanVat!.onchainStatus;
        if (trangThai == TrangThaiOnchain.registered) {
          _thongBao('Xác minh thành công! Nhân vật đã được ghi nhận On-Chain.');
        } else {
          _thongBao(
            'Giao dịch đang chờ xác nhận trên blockchain (${trangThai.nhan}).',
          );
        }
        await _taiDanhSachNhanVat();
      } else {
        _thongBao(
          xacMinhKq.chiTietLoi ?? 'Chưa xác minh được giao dịch với Backend.',
          loi: true,
        );
      }
    } on LoiVi catch (e) {
      _thongBao(
        e.nguoiDungTuChoi
            ? 'Bạn đã hủy xác nhận giao dịch trên MetaMask.'
            : 'Lỗi MetaMask: ${e.thongBao}',
        loi: !e.nguoiDungTuChoi,
      );
    } catch (e) {
      _thongBao('Đăng ký on-chain gặp sự cố: $e', loi: true);
    } finally {
      if (mounted) setState(() => _dangDangKyOnchain = false);
    }
  }

  void _saoChepHash(String fullHash) {
    Clipboard.setData(ClipboardData(text: fullHash));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép SHA-256 Character Hash vào bộ nhớ tạm!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Build Giao Diện
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final kq = _ketQua;
    final png = kq?.png;
    final anh = _anh;
    final nhanCho = _dangTao ? 'Đang tạo ảnh…' : 'Đang tải ảnh…';

    return Scaffold(
      backgroundColor: const Color(0xFF07121D),
      body: SafeArea(
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: GoldRushTopBar(
                    activeItem: GoldRushTopBarItem.xuongAi,
                    onSanhCho: () => Navigator.of(context).maybePop(),
                    onCuaHang: () => Navigator.of(context).maybePop(),
                    onRungRuong: widget.onRungRuong,
                    onKhoDo: () => Navigator.of(context).maybePop(),
                    onClose: () => Navigator.of(context).maybePop(),
                    showClose: true,
                    onSettings: null,
                  ),
                );
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'XƯỞNG AI',
                        style: TextStyle(
                          color: Color(0xFFB68CFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tạo nhân vật',
                        style: TextStyle(
                          color: Color(0xFFEAF2F8),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_nguoiDung != null) ...[
                        _xayDungAuthBar(),
                        const SizedBox(height: 16),
                      ],

                      // 2. Thẻ Tiến Trình Chơi Màn
                      if (_tienTrinh != null) ...[
                        _xayDungCardTienTrinh(),
                        const SizedBox(height: 16),
                      ],

                      // 3. Form Nhập Mô Tả và Tạo Ảnh (Giữ nguyên toàn bộ cấu trúc & text của bản cũ)
                      Form(
                        key: _form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Mô tả nhân vật bạn muốn xem, như một thợ mỏ đội mũ vàng.',
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _moTa,
                              enabled: !_dangTai,
                              minLines: 3,
                              maxLines: 5,
                              keyboardType: TextInputType.multiline,
                              decoration: const InputDecoration(
                                labelText: 'Mô tả nhân vật',
                                helperText: 'Tối đa 500 ký tự.',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) {
                                  return 'Hãy nhập mô tả nhân vật.';
                                }
                                if (text.runes.length > 500) {
                                  return 'Mô tả tối đa 500 ký tự.';
                                }
                                return null;
                              },
                              onChanged: _doiMoTa,
                            ),
                            const SizedBox(height: 20),
                            if (_dangTai) ...[
                              LinearProgressIndicator(semanticsLabel: nhanCho),
                              const SizedBox(height: 12),
                              Text(nhanCho, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                            ],
                            if (png != null && anh != null) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Text(
                                        anh.nguonSinh == 'demo'
                                            ? 'Ảnh mẫu demo'
                                            : 'Ảnh từ mô hình AI',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        anh.nguonNguCanh == 'demo'
                                            ? 'Phiên demo'
                                            : 'Phiên đã xác minh',
                                      ),
                                      if (anh.nguonSinh == 'demo')
                                        const Text(
                                          'Ảnh mẫu được chọn theo mô tả.',
                                        ),
                                      const SizedBox(height: 12),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 256,
                                        ),
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: Image.memory(
                                            png,
                                            filterQuality: FilterQuality.none,
                                            fit: BoxFit.contain,
                                            semanticLabel:
                                                'Ảnh xem trước nhân vật',
                                            errorBuilder: (_, _, _) =>
                                                const Center(
                                                  child: Text(
                                                    'Chưa hiển thị được ảnh.',
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('Ảnh tĩnh để xem trước.'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Thẻ Lưu Nhân Vật & Disclaimer
                              _xayDungCardLuuNhanVat(anh),
                              const SizedBox(height: 16),
                            ],
                            if (kq?.loi != null) ...[
                              Text(
                                _thongBaoLoi(kq!, daTao: anh != null),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (!_dangTai && (kq?.coTheThuLai ?? false)) ...[
                              OutlinedButton.icon(
                                onPressed: anh == null
                                    ? () => _tao(thuLai: true)
                                    : _taiLai,
                                icon: const Icon(Icons.refresh),
                                label: Text(
                                  anh == null ? 'Thử lại' : 'Tải lại ảnh',
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            FilledButton.icon(
                              onPressed:
                                  (_dangTai ||
                                      (_tienTrinh != null &&
                                          !_tienTrinh!.isCharacterUnlocked))
                                  ? null
                                  : () => _tao(),
                              icon: Icon(
                                _tienTrinh != null &&
                                        !_tienTrinh!.isCharacterUnlocked
                                    ? Icons.lock
                                    : Icons.auto_awesome,
                              ),
                              label: Text(
                                _dangTai
                                    ? 'Đang xử lý…'
                                    : (_tienTrinh != null &&
                                          !_tienTrinh!.isCharacterUnlocked)
                                    ? 'Khóa (Cần hoàn thành 6 màn)'
                                    : _maYeuCau == null
                                    ? 'Tạo ảnh'
                                    : 'Tạo ảnh mới',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. Danh Sách Nhân Vật Thuộc Tài Khoản
                      _xayDungDanhSachNhanVat(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Giữ helper xác thực để tương thích các luồng cũ; thanh TopBar hiện thay
  // thế phần hiển thị này trong màn Xưởng AI.
  // ignore: unused_element
  Widget _xayDungAuthBar() {
    if (_dangKiemTraPhien) {
      return const LinearProgressIndicator();
    }

    final user = _nguoiDung;
    if (user != null) {
      return Card(
        color: const Color(0xFF14221A),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF2E7D32)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified,
                    color: Colors.greenAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ví: ${user.viRutGon}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.greenAccent,
                        ),
                      ),
                      if (user.username.isNotEmpty)
                        Text(
                          'Người chơi: ${user.username}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _dangKetNoiAuth ? null : _dangXuat,
                icon: const Icon(
                  Icons.logout,
                  size: 16,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Đăng xuất',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFF1C222A),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF37474F)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text(
              'MetaMask SIWE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9D2DB),
              ),
            ),
            OutlinedButton(
              onPressed: _dangKetNoiAuth ? null : _dangNhapSiwe,
              style: OutlinedButton.styleFrom(
                foregroundColor: CauHinh.mauChinh,
                side: const BorderSide(color: CauHinh.mauChinh),
                visualDensity: VisualDensity.compact,
              ),
              child: _dangKetNoiAuth
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'ĐĂNG NHẬP SIWE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _xayDungCardTienTrinh() {
    final tt = _tienTrinh;
    if (tt == null) return const SizedBox.shrink();

    final daMoKhoa = tt.isCharacterUnlocked;
    final tongXong = tt.tongManHoanThanh;

    return Card(
      key: const ValueKey('card_tien_trinh_ai'),
      color: daMoKhoa ? const Color(0xFF14241B) : const Color(0xFF241C14),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: daMoKhoa ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  daMoKhoa ? Icons.lock_open : Icons.lock,
                  color: daMoKhoa ? Colors.greenAccent : Colors.orangeAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'TIẾN TRÌNH: $tongXong/6 MÀN HOÀN THÀNH',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: daMoKhoa
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tải lại tiến trình',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: tt.dangTai ? null : () => tt.taiTienTrinh(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              daMoKhoa
                  ? 'Chúc mừng! Bạn đã hoàn thành 6 màn chơi và mở khóa tính năng tạo nhân vật AI.'
                  : 'Cần hoàn thành đủ 6 màn chơi (hiện tại: $tongXong/6) để mở khóa tạo nhân vật AI.',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: List.generate(6, (index) {
                final stageId = index + 1;
                final done = tt.daHoanThanhMan(stageId);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: done
                        ? const Color(0xFF1B5E20)
                        : Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: done ? Colors.greenAccent : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done ? Icons.check : Icons.lock_outline,
                        size: 12,
                        color: done ? Colors.greenAccent : Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Màn $stageId',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: done
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: done ? Colors.white : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            if (tt.dangTai) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (tt.thongBaoLoi != null) ...[
              const SizedBox(height: 8),
              Text(
                'Lỗi đồng bộ: ${tt.thongBaoLoi}',
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _xayDungCardLuuNhanVat(AnhNhanVat anh) {
    final daLuu = _nhanVatVuaLuu;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cảnh báo quan trọng: ảnh preview chưa phải sprite sheet chơi được trong Flame
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LƯU Ý: Ảnh preview 128×128 pixel-art là ảnh tĩnh minh hoạ, CHƯA PHẢI sprite sheet điều khiển được trong game Flame.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF90A4AE),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (daLuu != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF14241B),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đã lưu: ${daLuu.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${daLuu.characterId}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Hash: ${daLuu.hashRutGon}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.cyanAccent,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 14),
                          tooltip: 'Sao chép SHA-256',
                          onPressed: () => _saoChepHash(daLuu.characterHash),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nhân vật đã nằm trong Kho đồ > Nhân vật AI. '
                      'Ảnh hiện là PNG tĩnh 128×128; chưa phải sprite sheet '
                      '4×4 để điều khiển trong gameplay.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: Navigator.of(context).canPop()
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('VỀ KHO ĐỒ XEM NHÂN VẬT'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Form(
                key: _formLuu,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _tenNhanVat,
                      enabled: !_dangLuu,
                      decoration: const InputDecoration(
                        labelText: 'Tên nhân vật',
                        helperText: 'Tối đa 32 ký tự để lưu vào CSDL Backend.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: (_dangLuu || _nguoiDung == null)
                          ? null
                          : _luuNhanVat,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.black,
                      ),
                      icon: _dangLuu
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        _nguoiDung == null
                            ? 'CẦN ĐĂNG NHẬP ĐỂ LƯU'
                            : (_dangLuu
                                  ? 'Đang lưu…'
                                  : 'LƯU NHÂN VẬT VÀO TÀI KHOẢN'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _xayDungDanhSachNhanVat() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'NHÂN VẬT (${_danhSachNhanVat.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (_dangTaiDanhSach)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_nguoiDung != null)
                  TextButton.icon(
                    onPressed: _taiDanhSachNhanVat,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text(
                      'Làm mới',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const Divider(),
            if (_nguoiDung == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Đăng nhập ví MetaMask SIWE để xem danh sách nhân vật đã lưu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else if (_danhSachNhanVat.isEmpty && !_dangTaiDanhSach)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Bạn chưa lưu nhân vật AI nào. Hãy tạo ảnh và bấm "LƯU NHÂN VẬT"!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _danhSachNhanVat.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, index) =>
                    _xayDungItemNhanVat(_danhSachNhanVat[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _xayDungItemNhanVat(ThongTinNhanVat nv) {
    final png = _anhNhanVatDaLuu[nv.characterId];
    final anhLoi = _anhNhanVatLoi.contains(nv.characterId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
            ),
            child: png != null
                ? Image.memory(
                    png,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  )
                : anhLoi
                ? const Icon(Icons.broken_image_outlined, color: Colors.grey)
                : const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        nv.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _xayDungHuyHieuTrangThai(nv.onchainStatus),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${nv.characterId}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Hash: ${nv.hashRutGon}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.cyan,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 13),
                      tooltip: 'Sao chép SHA-256',
                      onPressed: () => _saoChepHash(nv.characterHash),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                if (nv.transactionHash != null)
                  Text(
                    'Tx: ${nv.transactionHash!.substring(0, 10)}…',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                if (!nv.daDangKy) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _dangDangKyOnchain
                          ? null
                          : () => _dangKyOnchain(nv),
                      icon: const Icon(Icons.app_registration, size: 14),
                      label: Text(
                        nv.dangChoXacNhan
                            ? 'Kiểm tra lại trạng thái'
                            : 'Đăng ký On-Chain (EIP-712)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _xayDungHuyHieuTrangThai(TrangThaiOnchain st) {
    Color color;
    IconData icon;
    switch (st) {
      case TrangThaiOnchain.registered:
        color = Colors.green;
        icon = Icons.check_circle;
      case TrangThaiOnchain.pending:
        color = Colors.amber;
        icon = Icons.hourglass_top;
      case TrangThaiOnchain.failed:
        color = Colors.red;
        icon = Icons.error_outline;
      case TrangThaiOnchain.notRegistered:
        color = Colors.grey;
        icon = Icons.cloud_off;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          st.nhan,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

String _taoMaYeuCau() {
  final random = Random.secure();
  return 'imgreq_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

String _thongBaoLoi(KetQuaAnhNhanVat kq, {required bool daTao}) {
  if (kq.maHttp == 401) return 'Máy chủ cần xác minh người chơi.';
  if (kq.maHttp == 403) return 'Bạn chưa có quyền sử dụng ảnh này.';
  if (kq.maHttp == 404 && daTao) {
    return 'Ảnh đã hết hạn hoặc không còn khả dụng. Hãy tạo ảnh mới.';
  }
  if (kq.maHttp == 409) {
    return 'Yêu cầu này đã dùng cho mô tả khác. Hãy tạo ảnh mới.';
  }
  if (kq.maHttp == 429) return 'Đang có nhiều yêu cầu. Bạn có thể thử lại sau.';
  return switch (kq.loi) {
    LoiAnhNhanVat.chuaCauHinh => 'Chưa cấu hình máy chủ AI.',
    LoiAnhNhanVat.yeuCauKhongHopLe => 'Mô tả nhân vật chưa hợp lệ.',
    LoiAnhNhanVat.hetThoiGian =>
      'Máy chủ phản hồi quá lâu. Bạn có thể thử lại.',
    LoiAnhNhanVat.ketNoi =>
      'Không kết nối được máy chủ. Hãy kiểm tra mạng và thử lại.',
    LoiAnhNhanVat.biTuChoi =>
      'Máy chủ chưa chấp nhận yêu cầu ảnh (${kq.maHttp}).',
    LoiAnhNhanVat.mayChu =>
      'Dịch vụ ảnh chưa sẵn sàng. Bạn có thể thử lại sau.',
    _ =>
      daTao
          ? 'Ảnh nhận được không hợp lệ. Hãy tạo ảnh mới.'
          : 'Phản hồi tạo ảnh không hợp lệ. Hãy tạo ảnh mới.',
  };
}
