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
  final String? tepNhanVatDangDung;
  final Future<void> Function(ThongTinNhanVat nhanVat, Uint8List spriteSheet)?
  khiTrangBi;

  const NhanVatAiGallery({
    super.key,
    this.authController,
    this.mayChu,
    this.khiMoTaoNhanVat,
    this.tepNhanVatDangDung,
    this.khiTrangBi,
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
  String? _dangTrangBi;
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
          // Dùng sprite 4x4 đã chuẩn hóa để card chỉ hiển thị một frame,
          // đồng nhất với nhân vật George mặc định.
          .taiSpriteSheetDaLuu(nv.characterId)
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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.khiMoTaoNhanVat != null)
              TextButton.icon(
                onPressed: _moTaoNhanVat,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const ChuGame('Thêm nhân vật'),
              ),
            TextButton.icon(
              onPressed: _dangTai ? null : _tai,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const ChuGame('Làm mới'),
            ),
          ],
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
    final dangDung = widget.tepNhanVatDangDung == 'ai:${nv.characterId}';
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
                    : _KhungNhanVatAi(
                        png: png,
                        key: ValueKey('ai-image-${nv.characterId}'),
                        semanticLabel: PhamViNgonNgu.of(context)
                            .dich('Ảnh nhân vật AI ${nv.name}'),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          ChuGame(
            nv.name,
            dichNoiDung: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 3),
          const ChuGame(
            'Đã lưu · sprite 4×4',
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
            child: const ChuGame(
              'Xem chi tiết',
              style: TextStyle(fontSize: 10),
            ),
          ),
          if (widget.khiTrangBi != null)
            FilledButton.icon(
              onPressed: png == null || _dangTrangBi != null
                  ? null
                  : () => _trangBi(nv),
              icon: _dangTrangBi == nv.characterId
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(dangDung ? Icons.check : Icons.play_arrow, size: 14),
              label: ChuGame(dangDung ? 'Đang dùng' : 'Trang bị'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                minimumSize: const Size(0, 28),
                textStyle: const TextStyle(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _trangBi(ThongTinNhanVat nv) async {
    final callback = widget.khiTrangBi;
    if (callback == null || _dangTrangBi != null) return;
    setState(() => _dangTrangBi = nv.characterId);
    try {
      final kq = await _api
          .taiSpriteSheetDaLuu(nv.characterId)
          .timeout(const Duration(seconds: 12));
      if (kq.png == null) {
        throw StateError('Không tải được sprite nhân vật AI.');
      }
      await callback(nv, kq.png!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ChuGame(
              'Đã trang bị ${nv.name}. Sẽ dùng ở ván tiếp theo.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: ChuGame('Không thể trang bị nhân vật AI: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _dangTrangBi = null);
    }
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
                    child: SizedBox(
                      width: 128,
                      height: 128,
                      child: _KhungNhanVatAi(
                        png: png,
                        semanticLabel: PhamViNgonNgu.of(context)
                            .dich('Ảnh chi tiết nhân vật AI ${nv.name}'),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const ChuGame('Trạng thái: Đã lưu trong Backend'),
                const ChuGame('Loại tài sản: Nhân vật AI gắn với ví hiện tại'),
                const ChuGame(
                  'Gameplay: Sprite sheet 4×4, có thể trang bị ở ván tiếp theo',
                ),
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

class _KhungNhanVatAi extends StatelessWidget {
  final Uint8List png;
  final String semanticLabel;

  const _KhungNhanVatAi({
    super.key,
    required this.png,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 440,
          maxWidth: 440,
          minHeight: 440,
          maxHeight: 440,
          child: Image.memory(
            png,
            width: 440,
            height: 440,
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            filterQuality: FilterQuality.none,
            semanticLabel: PhamViNgonNgu.of(context).dich(semanticLabel),
            errorBuilder: (_, _, _) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}
