import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ngon_ngu/ngon_ngu.dart';

import '../../ai/may_chu_nhan_vat.dart';
import '../../ai/nhan_vat_ai_models.dart';
import '../../auth/auth_controller.dart';

/// Danh sách nhân vật AI bền vững của đúng phiên SIWE hiện tại.
/// Ảnh AI là tài sản ứng dụng riêng và không được tự xem như NFT.
class NhanVatAiGallery extends StatefulWidget {
  final AuthController? authController;
  final MayChuNhanVat? mayChu;
  final Future<void> Function()? khiMoTaoNhanVat;

  const NhanVatAiGallery({
    super.key,
    this.authController,
    this.mayChu,
    this.khiMoTaoNhanVat,
  });

  @override
  State<NhanVatAiGallery> createState() => _NhanVatAiGalleryState();
}

class _NhanVatAiGalleryState extends State<NhanVatAiGallery> {
  late MayChuNhanVat _api;
  late bool _tuQuanLyApi;
  List<ThongTinNhanVat> _danhSach = const [];
  final Map<String, Uint8List> _anh = {};
  final Set<String> _anhLoi = {};
  bool _dangTai = false;
  String? _loi;
  int _phien = 0;

  bool get _daDangNhap {
    if (widget.mayChu != null) return true;
    final auth = widget.authController;
    return auth != null && auth.canEnterGame && auth.user != null;
  }

  @override
  void initState() {
    super.initState();
    _ganApi();
    widget.authController?.addListener(_khiAuthDoi);
    if (_daDangNhap) unawaited(_tai());
  }

  @override
  void didUpdateWidget(covariant NhanVatAiGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authController, widget.authController)) {
      oldWidget.authController?.removeListener(_khiAuthDoi);
      widget.authController?.addListener(_khiAuthDoi);
    }
    if (!identical(oldWidget.mayChu, widget.mayChu)) {
      if (_tuQuanLyApi) _api.dong();
      _ganApi();
      _xoaDuLieuCu();
      if (_daDangNhap) unawaited(_tai());
    }
  }

  void _ganApi() {
    _tuQuanLyApi = widget.mayChu == null;
    _api = widget.mayChu ?? MayChuNhanVat();
  }

  void _khiAuthDoi() {
    if (!mounted) return;
    _xoaDuLieuCu();
    if (_daDangNhap) unawaited(_tai());
  }

  void _xoaDuLieuCu() {
    _phien++;
    if (!mounted) return;
    setState(() {
      _danhSach = const [];
      _anh.clear();
      _anhLoi.clear();
      _dangTai = false;
      _loi = null;
    });
  }

  Future<void> _tai() async {
    if (_dangTai || !_daDangNhap) return;
    final phien = ++_phien;
    setState(() {
      _dangTai = true;
      _loi = null;
    });
    try {
      final kq = await _api.layDanhSach().timeout(const Duration(seconds: 20));
      if (!mounted || phien != _phien) return;
      if (!kq.thanhCong) {
        setState(() {
          _dangTai = false;
          _loi = _moTaLoi(kq.maHttp);
        });
        return;
      }
      setState(() {
        _danhSach = kq.danhSach;
        _dangTai = false;
      });
      await Future.wait(kq.danhSach.map((nv) => _taiAnh(nv, phien)));
    } on TimeoutException {
      if (mounted && phien == _phien) {
        setState(() {
          _dangTai = false;
          _loi = 'Máy chủ phản hồi quá lâu. Hãy thử làm mới.';
        });
      }
    } on Exception {
      if (mounted && phien == _phien) {
        setState(() {
          _dangTai = false;
          _loi = 'Không tải được danh sách nhân vật AI.';
        });
      }
    }
  }

  Future<void> _moTaoNhanVat() async {
    final moTao = widget.khiMoTaoNhanVat;
    if (moTao == null) return;
    await moTao();
    if (mounted && _daDangNhap) await _tai();
  }

  Future<void> _taiAnh(ThongTinNhanVat nv, int phien) async {
    try {
      final kq = await _api
          .taiAnhDaLuu(nv.characterId)
          // Ảnh đã lưu nằm trong SQLite nên phải phản hồi nhanh; tránh spinner
          // kéo dài khi phiên Auth/backend bị treo.
          .timeout(const Duration(seconds: 8));
      if (!mounted || phien != _phien) return;
      if (kq.png == null) {
        setState(() => _anhLoi.add(nv.characterId));
        return;
      }
      setState(() {
        _anh[nv.characterId] = kq.png!;
        _anhLoi.remove(nv.characterId);
      });
    } on Exception {
      if (mounted && phien == _phien) {
        setState(() => _anhLoi.add(nv.characterId));
      }
    }
  }

  String _moTaLoi(int? status) => switch (status) {
    401 => 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
    403 => 'Phiên hiện tại không có quyền xem danh sách này.',
    _ => 'Không tải được danh sách nhân vật AI.',
  };

  @override
  void dispose() {
    _phien++;
    widget.authController?.removeListener(_khiAuthDoi);
    if (_tuQuanLyApi) _api.dong();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_daDangNhap) {
      return const ChuGame(
        'Đăng nhập ví MetaMask SIWE để xem nhân vật AI đã lưu.',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      );
    }
    if (_dangTai && _danhSach.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_loi != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChuGame(_loi!, style: const TextStyle(color: Colors.redAccent)),
          TextButton.icon(
            onPressed: _tai,
            icon: const Icon(Icons.refresh_rounded),
            label: const ChuGame('Thử lại'),
          ),
        ],
      );
    }
    if (_danhSach.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ChuGame(
            'Bạn chưa tạo nhân vật AI nào. Hãy tạo nhân vật đầu tiên.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Wrap(
            spacing: 8,
            children: [
              if (widget.khiMoTaoNhanVat != null)
                TextButton.icon(
                  onPressed: _moTaoNhanVat,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const ChuGame('Tạo nhân vật AI'),
                ),
              TextButton.icon(
                onPressed: _dangTai ? null : _tai,
                icon: const Icon(Icons.refresh_rounded),
                label: const ChuGame('Làm mới'),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _dangTai ? null : _tai,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const ChuGame('Làm mới'),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final nv in _danhSach) _theNhanVat(nv)],
        ),
      ],
    );
  }

  Widget _theNhanVat(ThongTinNhanVat nv) {
    final png = _anh[nv.characterId];
    final anhLoi = _anhLoi.contains(nv.characterId);
    return Container(
      width: 126,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF081827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x99E0A100)),
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: ColoredBox(
                color: Colors.black26,
                child: anhLoi
                    ? const Center(child: Icon(Icons.broken_image_outlined))
                    : png == null
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Image.memory(
                        png,
                        key: ValueKey('ai-image-${nv.characterId}'),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        semanticLabel: PhamViNgonNgu.of(context).dich('Ảnh nhân vật AI ${nv.name}'),
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          ChuGame(
            nv.name, dichNoiDung: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 3),
          const ChuGame(
            'Đã lưu · PNG tĩnh',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 9),
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: () => _moChiTiet(nv, png),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
            ),
            child: const ChuGame('Xem chi tiết', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Future<void> _moChiTiet(ThongTinNhanVat nv, Uint8List? png) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: ChuGame(nv.name, dichNoiDung: false),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (png != null)
                  Center(
                    child: Image.memory(
                      png,
                      width: 128,
                      height: 128,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      semanticLabel: PhamViNgonNgu.of(context).dich('Ảnh chi tiết nhân vật AI ${nv.name}'),
                    ),
                  ),
                const SizedBox(height: 12),
                const ChuGame('Trạng thái: Đã lưu trong Backend'),
                const ChuGame('Loại tài sản: Nhân vật AI, không phải NFT'),
                const ChuGame('Gameplay: Chưa có sprite sheet 4×4 để trang bị'),
                ChuGame('Mã: ${nv.idRutGon}'),
                ChuGame('Ngày tạo: ${nv.createdAt.toLocal()}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const ChuGame('Đóng'),
            ),
          ],
        ),
      );
}
