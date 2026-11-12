import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_controller.dart';
import 'may_chu_tien_trinh.dart';
import 'tien_trinh_models.dart';

/// Quản lý trạng thái tiến trình người chơi gắn với phiên SIWE của AuthController.
class TienTrinhController extends ChangeNotifier {
  final MayChuTienTrinh mayChu;
  final AuthController? authController;

  PhanHoiTienTrinh? _tienTrinh;
  bool _dangTai = false;
  String? _thongBao;
  bool _thongBaoLaLoi = false;
  String? _lastLoadedUserId;
  String? _lastLoadedWallet;
  bool _disposed = false;

  TienTrinhController({
    required this.mayChu,
    this.authController,
  }) {
    if (authController != null) {
      authController!.addListener(_khiAuthThayDoi);
      if (authController!.canEnterGame) {
        unawaited(taiTienTrinh());
      }
    }
  }

  PhanHoiTienTrinh? get tienTrinh => _tienTrinh;
  bool get dangTai => _dangTai;
  String? get thongBao => _thongBao;
  bool get thongBaoLaLoi => _thongBaoLaLoi;

  /// Đã mở khóa tính năng tạo nhân vật AI (hoàn thành đủ cả 6 màn).
  bool get isCharacterUnlocked => _tienTrinh?.isCharacterUnlocked ?? false;

  /// Bí danh kiểm tra đã hoàn thành đủ cả 6 màn chơi.
  bool get daHoanThanhDuSauMan => isCharacterUnlocked;

  /// Tổng số màn 1–6 đã hoàn thành (0–6).
  int get totalCompleted => _tienTrinh?.totalCompleted ?? 0;

  /// Bí danh tiếng Việt cho tổng số màn đã hoàn thành.
  int get tongManHoanThanh => totalCompleted;

  /// Thông báo lỗi nếu có lỗi xảy ra.
  String? get thongBaoLoi => _thongBaoLaLoi ? _thongBao : null;

  /// Danh sách các stage_id (1–6) đã hoàn thành.
  List<int> get completedStageIds => _tienTrinh?.completedStageIds ?? const [];

  /// Kiểm tra một màn chơi cụ thể đã hoàn thành chưa.
  bool daHoanThanhMan(int stageId) => completedStageIds.contains(stageId);

  /// Dành riêng cho Unit/Widget Test: gán trực tiếp dữ liệu tiến trình.
  @visibleForTesting
  void datTienTrinhChoKiemThu(PhanHoiTienTrinh tt) {
    _tienTrinh = tt;
    _thongBao = null;
    _thongBaoLaLoi = false;
    notifyListeners();
  }

  void _khiAuthThayDoi() {
    if (_disposed) return;
    final auth = authController;
    if (auth == null) return;

    if (!auth.canEnterGame) {
      // Khi logout hoặc session mất: Xóa ngay lập tức dữ liệu tiến trình nhạy cảm
      if (_tienTrinh != null || _thongBao != null) {
        _tienTrinh = null;
        _thongBao = null;
        _thongBaoLaLoi = false;
        _lastLoadedUserId = null;
        _lastLoadedWallet = null;
        notifyListeners();
      }
      return;
    }

    final currentUserId = auth.user?.id;
    final currentWallet = auth.walletAddress?.toLowerCase();

    // Nếu đổi sang tài khoản hoặc ví MetaMask mới: xóa tiến trình cũ và tải tiến trình tài khoản mới
    if (currentUserId != _lastLoadedUserId || currentWallet != _lastLoadedWallet) {
      _tienTrinh = null;
      _lastLoadedUserId = currentUserId;
      _lastLoadedWallet = currentWallet;
      notifyListeners();
      unawaited(taiTienTrinh());
    }
  }

  int _taiEpoch = 0;

  /// Tải tiến trình mới nhất từ Backend (GET /api/ai/tien-trinh).
  Future<void> taiTienTrinh({bool imLang = false}) async {
    if (_disposed) return;
    if (authController != null && !authController!.canEnterGame) {
      _tienTrinh = null;
      notifyListeners();
      return;
    }

    final epoch = ++_taiEpoch;

    if (!imLang) {
      _dangTai = true;
      _thongBao = null;
      _thongBaoLaLoi = false;
      notifyListeners();
    }

    final kq = await mayChu.layTienTrinh();
    if (_disposed || epoch != _taiEpoch) return;

    _dangTai = false;
    if (kq.thanhCong) {
      _tienTrinh = kq.tienTrinh;
      _lastLoadedUserId = authController?.user?.id ?? _tienTrinh?.ownerUserId;
      _lastLoadedWallet = authController?.walletAddress?.toLowerCase() ??
          _tienTrinh?.verifiedWalletAddress.toLowerCase();
      _thongBao = null;
      _thongBaoLaLoi = false;
    } else {
      if (kq.hetPhien) {
        _tienTrinh = null;
        _thongBao = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
        _thongBaoLaLoi = true;
      } else if (kq.chuaSanSang) {
        _thongBao = 'Dịch vụ tiến trình tạm thời chưa sẵn sàng (503).';
        _thongBaoLaLoi = true;
      } else if (kq.matMang) {
        _thongBao = 'Không thể kết nối máy chủ để tải tiến trình.';
        _thongBaoLaLoi = true;
      } else {
        _thongBao = kq.chiTietLoi ?? 'Lỗi không xác định khi tải tiến trình.';
        _thongBaoLaLoi = true;
      }
    }
    notifyListeners();
  }

  /// Xác nhận hoàn thành màn chơi sau khi có bằng chứng (referee_log hoặc blockchain_tx).
  ///
  /// Quy tắc an ninh:
  /// - Nếu Backend đã tự động ghi nhận màn qua `cap_phieu`, không gửi trùng vô ích.
  /// - Nếu bị 409 (Replay), kiểm tra lại tiến trình từ Backend trước khi kết luận.
  /// - Không tự đánh dấu `completed` trên UI nếu Backend chưa xác nhận.
  Future<bool> xacNhanHoanThanhMan({
    required int stageId,
    required String evidenceType,
    required String evidence,
  }) async {
    if (_disposed) return false;
    if (stageId < 1 || stageId > 6) return false;

    // 1. Kiểm tra nếu màn này đã hoàn thành trên Backend từ trước -> không cần nộp lại
    if (daHoanThanhMan(stageId)) {
      return true;
    }

    // 2. Tải lại tiến trình trước (vì Backend `cap_phieu` có thể đã tự động ghi nhận)
    await taiTienTrinh(imLang: true);
    if (daHoanThanhMan(stageId)) {
      return true;
    }

    // 3. Nếu chưa có trên Backend, thực hiện gọi xác minh POST /api/ai/tien-trinh/xac-minh
    final csrfToken = authController?.csrfToken;
    final kq = await mayChu.xacMinhManChoi(
      stageId: stageId,
      evidenceType: evidenceType,
      evidence: evidence,
      csrfToken: csrfToken,
    );

    if (_disposed) return false;

    if (kq.thanhCong) {
      // Xác minh thành công -> tải lại tiến trình chính thức
      await taiTienTrinh(imLang: true);
      return daHoanThanhMan(stageId);
    }

    // Xử lý trường hợp 409 (Replay Key): Có thể do cap_phieu vừa ghi nhận hoặc đã có bản ghi
    if (kq.trungBangChung) {
      await taiTienTrinh(imLang: true);
      if (daHoanThanhMan(stageId)) {
        return true;
      }
      _thongBao = 'Bằng chứng ván chơi đã được sử dụng trước đó (409).';
      _thongBaoLaLoi = true;
      notifyListeners();
      return false;
    }

    // Các lỗi khác (401, 403, 422, 503, mất mạng)
    if (kq.hetPhien) {
      _thongBao = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại SIWE.';
    } else if (kq.chuaSanSang) {
      _thongBao = 'Hệ thống xác minh tạm thời chưa sẵn sàng (503).';
    } else {
      _thongBao = kq.chiTietLoi ?? 'Không thể xác minh tiến trình màn $stageId.';
    }
    _thongBaoLaLoi = true;
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    authController?.removeListener(_khiAuthThayDoi);
    super.dispose();
  }
}
