import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/may_chu_nhan_vat.dart';
import '../auth/auth_controller.dart';
import '../blockchain/nhan_vat.dart';
import '../blockchain/phien_vi.dart';
import '../blockchain/vi.dart';
import '../components/ai/nhan_vat_ai_gallery.dart';
import '../components/ui/game_inventory_controls.dart';
import '../components/ui/gold_rush_top_bar.dart';
import '../giao_dien/khung_game.dart';
import '../giao_dien/mau_game.dart';
import '../kho_do/danh_sach_nhan_vat.dart';
import '../kho_do/luoi_vat_pham.dart';
import '../kho_do/nhan_vat_voi_trang_bi.dart';
import '../kho_do/the_vat_pham.dart';
import '../kho_do/vat_pham_hien_thi.dart';

enum TrangThaiKhoDo { dangTai, trong, loi, daTai }

/// Kho đồ nhận dữ liệu và hành động từ bên ngoài.
///
/// Không tự sửa trang bị, nhân vật đang dùng hoặc quyền sở hữu.
class ManHinhKhoDo extends StatefulWidget {
  final VoidCallback khiDong;
  final TrangThaiKhoDo trangThaiTrangBi;
  final TrangThaiKhoDo trangThaiNhanVat;
  final List<VatPhamHienThi> danhSachVatPham;

  final Future<void> Function(String itemId)? khiTrangBi;
  final Future<void> Function(String itemId)? khiThao;
  final Future<void> Function(
    VatPhamHienThi vatPham,
    String nguoiNhan,
    int soLuong,
  )?
  khiHoanDoiNFT;
  final int? Function(String itemId)? layTokenIdNFT;
  final Future<void> Function()? khiLamMoiKhoDo;

  /// Dùng phiên ví có sẵn của game, không tạo phiên ví mới.
  final PhienVi? phienVi;

  /// Tên sprite sheet, ví dụ george.png.
  /// Null nghĩa là chưa nhận được lựa chọn nhân vật.
  final String? tepNhanVatDangDung;

  /// Callback nhận ID dưới dạng chuỗi.
  /// Bên gọi kiểm tra, xác nhận và cập nhật lựa chọn thật.
  final Future<void> Function(String characterId)? khiChonNhanVat;

  final String? loiTrangBi;
  final String? loiNhanVat;
  final VoidCallback? khiThuLaiTrangBi;
  final VoidCallback? khiThuLaiNhanVat;
  final int tabBanDau;
  final AuthController? authController;
  final MayChuNhanVat? mayChuNhanVat;
  final Future<void> Function()? khiMoTaoNhanVat;
  final GoldRushTopBar? thanhTren;

  const ManHinhKhoDo({
    super.key,
    required this.khiDong,
    this.trangThaiTrangBi = TrangThaiKhoDo.dangTai,
    this.trangThaiNhanVat = TrangThaiKhoDo.dangTai,
    this.danhSachVatPham = const [],
    this.khiTrangBi,
    this.khiThao,
    this.khiHoanDoiNFT,
    this.layTokenIdNFT,
    this.khiLamMoiKhoDo,
    this.phienVi,
    this.tepNhanVatDangDung,
    this.khiChonNhanVat,
    this.loiTrangBi,
    this.loiNhanVat,
    this.khiThuLaiTrangBi,
    this.khiThuLaiNhanVat,
    this.tabBanDau = 0,
    this.authController,
    this.mayChuNhanVat,
    this.khiMoTaoNhanVat,
    this.thanhTren,
  });

  @override
  State<ManHinhKhoDo> createState() => _ManHinhKhoDoState();
}

class _ManHinhKhoDoState extends State<ManHinhKhoDo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hieuUngNen;
  String? _idVatPhamDangChon;
  DanhMucVatPham? _danhMucDangChon;
  bool _dangXuLyThaoTac = false;
  bool _dangLamMoiKhoDo = false;
  String? _loiThaoTac;
  String? _thongBaoThaoTac;

  bool get _daTaiVatPham => widget.trangThaiTrangBi == TrangThaiKhoDo.daTai;

  bool get _phienViBan =>
      (widget.phienVi?.dangXuLy ?? false) || (widget.phienVi?.dangHoi ?? false);

  VatPhamHienThi? get _vatPhamDangChon {
    if (!_daTaiVatPham) return null;

    for (final vp in widget.danhSachVatPham) {
      if (vp.id == _idVatPhamDangChon) return vp;
    }

    return null;
  }

  List<VatPhamHienThi> get _danhSachDaLoc {
    if (!_daTaiVatPham) return const [];

    final ketQua = widget.danhSachVatPham.where((vp) {
      final dungDanhMuc =
          _danhMucDangChon == null || vp.danhMucHienThi == _danhMucDangChon;
      return dungDanhMuc;
    }).toList();

    ketQua.sort((a, b) {
      final theoDoHiem = b.doHiem.index.compareTo(a.doHiem.index);
      return theoDoHiem != 0 ? theoDoHiem : a.ten.compareTo(b.ten);
    });

    return ketQua;
  }

  /// Chỉ lấy ảnh từ danh mục và quyền sở hữu hiện tại.
  /// Không tự coi nhân vật cửa hàng là đã sở hữu.
  NhanVatBan? get _nhanVatDangDung {
    if (widget.trangThaiNhanVat != TrangThaiKhoDo.daTai) {
      return null;
    }

    final tep = widget.tepNhanVatDangDung;

    if (tep == georgeGoc.tepAnh) return georgeGoc;

    final pv = widget.phienVi;
    if (pv == null || !pv.daKetNoi) return null;

    for (final nv in bangNhanVat) {
      if (nv.tepAnh == tep && pv.daCo.contains(nv.id)) {
        return nv;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _hieuUngNen = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (kIsWeb) _hieuUngNen.repeat();
  }

  @override
  void didUpdateWidget(covariant ManHinhKhoDo oldWidget) {
    super.didUpdateWidget(oldWidget);

    final conVatPham = widget.danhSachVatPham.any(
      (vp) => vp.id == _idVatPhamDangChon,
    );

    if (!_daTaiVatPham || !conVatPham) {
      _idVatPhamDangChon = null;
      _loiThaoTac = null;
      _thongBaoThaoTac = null;
    }
  }

  @override
  void dispose() {
    _hieuUngNen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pv = widget.phienVi;

    if (pv == null) return _manHinh();

    // Cập nhật cả danh sách và ảnh xem trước khi phiên ví thay đổi.
    return ListenableBuilder(
      listenable: pv,
      builder: (context, _) => _manHinh(),
    );
  }

  Widget _manHinh() {
    return KhungGame(
      tieuDe: 'KHO ĐỒ',
      chieuRongToiDa: double.infinity,
      nen: _NenKhoDo(animation: _hieuUngNen),
      thanhTren: widget.thanhTren,
      khiDong: () {
        if (_dangXuLyThaoTac) return;
        widget.khiDong();
      },
      child: DefaultTabController(
        length: 2,
        initialIndex: widget.tabBanDau.clamp(0, 1),
        child: Column(
          children: [
            Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 470),
                          child: Row(
                            children: [
                              Expanded(
                                child: GameTabButton(
                                  label: 'Trang bị',
                                  icon: Icons.shield_outlined,
                                  selected: controller.index == 0,
                                  onTap: () => controller.animateTo(0),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: GameTabButton(
                                  label: 'Nhân vật',
                                  icon: Icons.person_outline_rounded,
                                  selected: controller.index == 1,
                                  onTap: () => controller.animateTo(1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            if (_dangXuLyThaoTac)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Đang xử lý. Vui lòng chờ trước khi đóng Kho đồ.',
                  style: TextStyle(color: MauGame.chuPhu, fontSize: 12),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _BoCucKho(benTrai: _khungTrangBi(), benPhai: _khungVatPham()),
                  _BoCucKho(
                    benTrai: _khungXemNhanVat(),
                    benPhai: _khungDanhSachNhanVat(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tenTrangBiTai(OTrangBi o) {
    if (!_daTaiVatPham) return 'Chưa có dữ liệu';

    final cacVatPham = widget.danhSachVatPham
        .where((vp) => vp.oDangTrangBi == o)
        .toList();

    if (cacVatPham.isEmpty) return 'Chưa trang bị';
    if (cacVatPham.length > 1) {
      return 'Dữ liệu trang bị chưa nhất quán';
    }

    final vp = cacVatPham.single;
    return vp.laDuLieuMau ? '${vp.ten} · DEMO' : vp.ten;
  }

  VatPhamHienThi? _trangBiTai(OTrangBi o) {
    if (!_daTaiVatPham) return null;
    final cacVatPham = widget.danhSachVatPham
        .where((vp) => vp.oDangTrangBi == o)
        .toList();
    return cacVatPham.isNotEmpty ? cacVatPham.first : null;
  }

  Widget _khungTrangBi() {
    return _KhungMuc(
      tieuDe: 'TRANG BỊ ĐANG DÙNG',
      bieuTuong: Icons.shield_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _XemTruocNhanVat(
            nhanVat: _nhanVatDangDung,
            danhSachVatPham: widget.danhSachVatPham,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _OTrangBi(
                nhan: 'Vũ khí chính',
                loai: _LoaiOTrangBi.kiem,
                noiDung: _tenTrangBiTai(OTrangBi.vuKhiChinh),
                duongDanAnh: _trangBiTai(OTrangBi.vuKhiChinh)?.duongDanAnh,
                noiBat: true,
              ),
              _OTrangBi(
                nhan: 'Giày',
                loai: _LoaiOTrangBi.giay,
                noiDung: _tenTrangBiTai(OTrangBi.giay),
                duongDanAnh: _trangBiTai(OTrangBi.giay)?.duongDanAnh,
              ),
              _OTrangBi(
                nhan: 'Giáp',
                loai: _LoaiOTrangBi.giap,
                noiDung: _tenTrangBiTai(OTrangBi.giap),
                duongDanAnh: _trangBiTai(OTrangBi.giap)?.duongDanAnh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _GhiChu(
            noiDung:
                'Trang bị đang dùng được hiển thị '
                'theo dữ liệu hệ thống cung cấp.',
          ),
        ],
      ),
    );
  }

  Widget _khungVatPham() {
    final coDuLieu = _daTaiVatPham && widget.danhSachVatPham.isNotEmpty;
    final coDuLieuMau =
        coDuLieu && widget.danhSachVatPham.any((vp) => vp.laDuLieuMau);
    final danhSach = _danhSachDaLoc;

    return _KhungMuc(
      tieuDe: 'TÚI VẬT PHẨM',
      bieuTuong: Icons.backpack_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _thanhDanhMuc(),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _dangLamMoiKhoDo || widget.khiLamMoiKhoDo == null
                  ? null
                  : () async {
                      setState(() => _dangLamMoiKhoDo = true);
                      try {
                        await widget.khiLamMoiKhoDo!();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã làm mới Kho đồ theo Blockchain.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } on LoiVi catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.thongBao),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _dangLamMoiKhoDo = false);
                      }
                    },
              icon: _dangLamMoiKhoDo
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 17),
              label: Text(
                _dangLamMoiKhoDo ? 'Đang làm mới…' : 'LÀM MỚI KHO ĐỒ',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (coDuLieuMau) ...[
            const _GhiChu(
              noiDung:
                  'Có dữ liệu DEMO trong danh sách. '
                  'Đây không phải bằng chứng sở hữu '
                  'vật phẩm của người chơi.',
            ),
            const SizedBox(height: 12),
          ],
          if (coDuLieu)
            LayoutBuilder(
              builder: (context, constraints) {
                final hienSidebar = constraints.maxWidth >= 720;
                final luoi = _noiDungLuoi(danhSach);

                if (!hienSidebar) return luoi;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 166,
                      child: _DanhMucBenTrai(
                        danhSach: widget.danhSachVatPham,
                        dangChon: _danhMucDangChon,
                        khiChon: _chonDanhMuc,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: luoi),
                  ],
                );
              },
            )
          else
            _TrangThaiDuLieu(
              trangThai: widget.trangThaiTrangBi,
              thongBaoTrong: 'Túi vật phẩm đang trống',
              moTaTrong:
                  'Vật phẩm sẽ xuất hiện tại đây '
                  'khi hệ thống cung cấp dữ liệu kho đồ.',
              thongBaoLoi: widget.loiTrangBi ?? 'Không tải được kho đồ.',
              khiThuLai: widget.khiThuLaiTrangBi,
            ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x55728AA5)),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: MauGame.chinh, size: 20),
              SizedBox(width: 8),
              Text(
                'CHI TIẾT VẬT PHẨM',
                style: TextStyle(
                  color: MauGame.chinh,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_idVatPhamDangChon),
              child: _chiTietVatPham(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thanhDanhMuc() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _TabDanhMuc(
          nhan: 'Tất cả',
          bieuTuong: Icons.grid_view_rounded,
          dangChon: _danhMucDangChon == null,
          khiBam: () => _chonDanhMuc(null),
        ),
        for (final danhMuc in const [
          DanhMucVatPham.vuKhi,
          DanhMucVatPham.giap,
          DanhMucVatPham.giay,
        ])
          _TabDanhMuc(
            nhan: _tenDanhMuc(danhMuc),
            bieuTuong: _iconDanhMuc(danhMuc),
            dangChon: _danhMucDangChon == danhMuc,
            khiBam: () => _chonDanhMuc(danhMuc),
          ),
      ],
    );
  }

  Widget _noiDungLuoi(List<VatPhamHienThi> danhSach) {
    if (danhSach.isEmpty) {
      return const _TrangTrongDanhMuc(coTimKiem: false);
    }

    return LuoiVatPham(
      danhSach: danhSach,
      idDangChon: _idVatPhamDangChon,
      khiChon: _dangXuLyThaoTac
          ? null
          : (vp) {
              setState(() {
                _idVatPhamDangChon = vp.id;
                _loiThaoTac = null;
                _thongBaoThaoTac = null;
              });
            },
    );
  }

  void _chonDanhMuc(DanhMucVatPham? danhMuc) {
    setState(() {
      _danhMucDangChon = danhMuc;
      if (_vatPhamDangChon != null &&
          danhMuc != null &&
          _vatPhamDangChon!.danhMucHienThi != danhMuc) {
        _idVatPhamDangChon = null;
      }
    });
  }

  Widget _chiTietVatPham() {
    final vp = _vatPhamDangChon;

    if (vp == null) {
      return const Text(
        'Chọn một vật phẩm trong danh sách để xem thông tin.',
        style: TextStyle(color: MauGame.chuPhu, fontSize: 13, height: 1.5),
      );
    }

    final mau = mauDoHiem(vp.doHiem);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B192A),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: mau.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(color: mau.withValues(alpha: 0.12), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: mau.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: mau.withValues(alpha: 0.5)),
                ),
                child: vp.duongDanAnh != null && vp.duongDanAnh!.isNotEmpty
                    ? HinhTrangBiFrame(
                        asset: vp.duongDanAnh!,
                        kichThuoc: 48,
                        fallback: Icon(
                          _iconDanhMuc(vp.danhMucHienThi),
                          color: mau,
                          size: 36,
                        ),
                      )
                    : Icon(
                        _iconDanhMuc(vp.danhMucHienThi),
                        color: mau,
                        size: 36,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vp.ten,
                      style: const TextStyle(
                        color: MauGame.chu,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tenDoHiem(vp.doHiem),
                      style: TextStyle(
                        color: mau,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (vp.nguon == NguonVatPham.nft)
                OutlinedButton.icon(
                  onPressed: () => _moDialogHoanDoi(vp),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                  label: const Text('Hoán đổi'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (vp.laDuLieuMau) ...[
            const Text(
              'DEMO — dữ liệu minh họa',
              style: TextStyle(
                color: MauGame.chinh,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _DongChiTiet(nhan: 'ID', giaTri: vp.id),
          _DongChiTiet(nhan: 'Loại', giaTri: _tenDanhMuc(vp.danhMucHienThi)),
          _DongChiTiet(nhan: 'Số lượng', giaTri: '${vp.soLuong}'),
          _DongChiTiet(
            nhan: 'Nguồn',
            giaTri: vp.nguon == NguonVatPham.nft ? 'NFT' : 'Trong game',
          ),
          _DongChiTiet(nhan: 'Trang bị', giaTri: _tenOTrangBi(vp.oDangTrangBi)),
          if (vp.moTa.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              vp.moTa,
              style: const TextStyle(
                color: MauGame.chuPhu,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'THUỘC TÍNH',
            style: TextStyle(
              color: MauGame.chinh,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (vp.thuocTinh.isEmpty)
            const Text(
              'Chưa có thông tin thuộc tính.',
              style: TextStyle(color: MauGame.chuPhu, fontSize: 13),
            )
          else
            for (final tt in vp.thuocTinh.entries)
              _DongChiTiet(nhan: tt.key, giaTri: tt.value),
          if (vp.nguon == NguonVatPham.nft) ...[
            const SizedBox(height: 14),
            _DongChiTiet(nhan: 'Chain ID', giaTri: '${vp.chainId}'),
            _DongChiTiet(nhan: 'Hợp đồng', giaTri: vp.diaChiHopDong ?? ''),
            _DongChiTiet(nhan: 'Token ID', giaTri: vp.tokenId ?? ''),
            const SizedBox(height: 8),
            const _GhiChu(
              noiDung:
                  'Thông tin NFT chỉ để hiển thị. '
                  'Quyền sở hữu phải được module Blockchain xác nhận.',
            ),
          ],
          const SizedBox(height: 16),
          _hanhDongVatPham(vp),
        ],
      ),
    );
  }

  Future<void> _moDialogHoanDoi(VatPhamHienThi vp) async {
    final contextManHinh = context;
    final tokenId = widget.layTokenIdNFT?.call(vp.id);
    final diaChiViGui =
        widget.phienVi?.diaChi ??
        widget.authController?.walletAddress ??
        'Chưa kết nối MetaMask';
    final controllerViNhan = TextEditingController();
    var dangXacNhan = false;
    var dangXuLy = false;
    String? loiChuyen;
    var soLuong = 1;
    final soLuongToiDa = vp.soLuong < 1 ? 1 : vp.soLuong;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, capNhat) {
            final mau = mauDoHiem(vp.doHiem);
            final anh = vp.duongDanAnh;
            final noiDung = dangXacNhan
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'XÁC NHẬN THÔNG TIN',
                        style: TextStyle(
                          color: MauGame.chinh,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DongChiTiet(nhan: 'Vật phẩm', giaTri: vp.ten),
                      _DongChiTiet(nhan: 'Từ', giaTri: diaChiViGui),
                      _DongChiTiet(
                        nhan: 'Đến',
                        giaTri: controllerViNhan.text.trim().isEmpty
                            ? 'Chưa nhập địa chỉ'
                            : controllerViNhan.text.trim(),
                      ),
                      _DongChiTiet(nhan: 'Số lượng', giaTri: '$soLuong NFT'),
                      if (loiChuyen != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          loiChuyen!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => capNhat(() {
                                dangXacNhan = false;
                              }),
                              child: const Text('Quay lại'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: dangXuLy
                                  ? null
                                  : () async {
                                      final to = controllerViNhan.text.trim();
                                      if (!RegExp(r'^0x[0-9a-fA-F]{40}$')
                                              .hasMatch(to) ||
                                          RegExp(r'^0x0{40}$').hasMatch(to)) {
                                        capNhat(() {
                                          loiChuyen = 'Địa chỉ ví người nhận không hợp lệ.';
                                        });
                                        return;
                                      }
                                      final khiHoanDoi = widget.khiHoanDoiNFT;
                                      if (khiHoanDoi == null) {
                                        capNhat(() {
                                          loiChuyen =
                                              'Chưa kết nối xử lý chuyển NFT.';
                                        });
                                        return;
                                      }
                                      capNhat(() {
                                        dangXuLy = true;
                                        loiChuyen = null;
                                      });
                                      try {
                                        await khiHoanDoi(vp, to, soLuong);
                                        if (!context.mounted) return;
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.maybeOf(
                                          contextManHinh,
                                        )?.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Đã chuyển ${vp.ten} ×$soLuong NFT thành công.',
                                            ),
                                            backgroundColor: const Color(
                                              0xFF142B38,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      } on LoiVi catch (e) {
                                        if (!context.mounted) return;
                                        capNhat(() {
                                          dangXuLy = false;
                                          loiChuyen = e.thongBao;
                                        });
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        capNhat(() {
                                          dangXuLy = false;
                                          loiChuyen = 'Chuyển NFT thất bại: $e';
                                        });
                                      }
                                    },
                              icon: dangXuLy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.swap_horiz_rounded),
                              label: Text(
                                dangXuLy ? 'Đang chuyển…' : 'Xác nhận chuyển',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _DongTieuDeDialog(nhan: 'FROM · VÍ NGƯỜI GỬI'),
                      _DongThongTinDialog(
                        icon: Icons.account_balance_wallet_outlined,
                        noiDung: diaChiViGui,
                        nhanPhu: 'CỦA BẠN',
                      ),
                      const SizedBox(height: 14),
                      const _DongTieuDeDialog(
                        nhan: 'TO · ĐỊA CHỈ VÍ NGƯỜI NHẬN',
                      ),
                      TextField(
                        controller: controllerViNhan,
                        style: const TextStyle(color: MauGame.chu),
                        decoration: const InputDecoration(
                          hintText: '0x...',
                          helperText:
                              'Nhập địa chỉ ví Ethereum 0x... của người nhận.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _DongTieuDeDialog(nhan: 'SỐ LƯỢNG NFT MUỐN CHUYỂN'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10263A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF46627A)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: soLuong > 1
                                  ? () => capNhat(() => soLuong--)
                                  : null,
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            Text(
                              '$soLuong',
                              style: const TextStyle(
                                color: MauGame.chu,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              onPressed: soLuong < soLuongToiDa
                                  ? () => capNhat(() => soLuong++)
                                  : null,
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sở hữu: ${vp.soLuong} NFT · Tối đa chuyển: $soLuongToiDa',
                        style: const TextStyle(
                          color: MauGame.chuPhu,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _GhiChu(
                        noiDung:
                            'Phí giao dịch: Hardhat ETH thử nghiệm. '
                            'Phí gas thực tế sẽ được ví hiển thị khi gửi giao dịch.',
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () => capNhat(() {
                          dangXacNhan = true;
                        }),
                        child: const Text('Tiếp tục'),
                      ),
                    ],
                  );

            return Dialog(
              backgroundColor: const Color(0xFF162E45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: MauGame.chinh, width: 2),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '✦ CHUYỂN NFT',
                              style: TextStyle(
                                color: Color(0xFFFFD77A),
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const Divider(color: Color(0x55728AA5)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF164B5A),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '● HARDHAT LOCAL',
                              style: TextStyle(
                                color: Color(0xFFBFE0E9),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Chain ID: 31337',
                              style: TextStyle(
                                color: Color(0xFFE7F2F5),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!dangXacNhan) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B3047),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: mau.withValues(alpha: 0.7),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: anh == null || anh.isEmpty
                                    ? Icon(
                                        _iconDanhMuc(vp.danhMucHienThi),
                                        color: mau,
                                        size: 34,
                                      )
                                    : HinhTrangBiFrame(
                                        asset: anh,
                                        kichThuoc: 52,
                                        fallback: Icon(
                                          _iconDanhMuc(vp.danhMucHienThi),
                                          color: mau,
                                          size: 34,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'VẬT PHẨM NFT · ERC-1155',
                                      style: TextStyle(
                                        color: mau,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      vp.ten,
                                      style: const TextStyle(
                                        color: MauGame.chu,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Token ID: ${tokenId ?? vp.tokenId ?? vp.id} · Đang sở hữu ×${vp.soLuong}',
                                      style: const TextStyle(
                                        color: MauGame.chuPhu,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      noiDung,
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    controllerViNhan.dispose();
  }

  Widget _hanhDongVatPham(VatPhamHienThi vp) {
    final coTheTrangBi =
        vp.loai == LoaiVatPham.vuKhi ||
        vp.loai == LoaiVatPham.giap ||
        vp.loai == LoaiVatPham.giay;

    if (!coTheTrangBi) {
      return const _GhiChu(
        noiDung:
            'Vật phẩm này không thuộc nhóm vũ khí, giáp hoặc giày. '
            'Chưa tích hợp thao tác sử dụng vật phẩm.',
      );
    }

    final thaoTac = vp.dangTrangBi ? widget.khiThao : widget.khiTrangBi;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _dangXuLyThaoTac || _phienViBan || thaoTac == null
              ? null
              : () => _guiThaoTac(vp),
          icon: _dangXuLyThaoTac
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  vp.dangTrangBi
                      ? Icons.remove_circle_outline_rounded
                      : Icons.add_circle_outline_rounded,
                ),
          label: Text(
            _dangXuLyThaoTac
                ? 'Đang xử lý…'
                : vp.dangTrangBi
                ? 'Tháo trang bị'
                : 'Trang bị',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: MauGame.chinh,
            foregroundColor: MauGame.chuTrenVang,
          ),
        ),
        if (thaoTac == null) ...[
          const SizedBox(height: 8),
          const _GhiChu(
            noiDung:
                'Chưa kết nối xử lý trang bị. '
                'Nút sẽ hoạt động khi module nghiệp vụ '
                'cung cấp callback.',
          ),
        ],
        if (_phienViBan) ...[
          const SizedBox(height: 8),
          const _GhiChu(noiDung: 'Phiên ví đang xử lý thao tác khác.'),
        ],
        if (_loiThaoTac != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _loiThaoTac!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
        if (_thongBaoThaoTac != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _thongBaoThaoTac!,
              style: const TextStyle(
                color: MauGame.chuPhu,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _guiThaoTac(VatPhamHienThi vp) async {
    if (_dangXuLyThaoTac || !_daTaiVatPham || _phienViBan) {
      return;
    }

    final hienTai = _vatPhamDangChon;
    if (hienTai == null || hienTai.id != vp.id) return;

    if (hienTai.loai != LoaiVatPham.vuKhi &&
        hienTai.loai != LoaiVatPham.giap &&
        hienTai.loai != LoaiVatPham.giay) {
      return;
    }

    final thaoTac = hienTai.dangTrangBi ? widget.khiThao : widget.khiTrangBi;

    if (thaoTac == null) return;

    setState(() {
      _dangXuLyThaoTac = true;
      _loiThaoTac = null;
      _thongBaoThaoTac = null;
    });

    try {
      await thaoTac(hienTai.id);
      if (!mounted) return;

      setState(() {
        _dangXuLyThaoTac = false;

        if (_vatPhamDangChon?.id == hienTai.id) {
          _thongBaoThaoTac =
              'Yêu cầu đã được xác nhận. '
              'Trạng thái hiển thị theo dữ liệu '
              'cập nhật từ hệ thống.';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _dangXuLyThaoTac = false;

        if (_vatPhamDangChon?.id == hienTai.id) {
          _loiThaoTac =
              'Thao tác không thành công. '
              'Giao diện không tự thay đổi trang bị; '
              'bạn có thể thử lại.';
        }
      });
    }
  }

  String _tenOTrangBi(OTrangBi? o) {
    switch (o) {
      case OTrangBi.vuKhiChinh:
        return 'Vũ khí chính';
      case OTrangBi.vuKhiPhu:
        return 'Vũ khí phụ';
      case OTrangBi.giap:
        return 'Giáp';
      case OTrangBi.giay:
        return 'Giày';
      case null:
        return 'Chưa trang bị';
    }
  }

  Widget _khungXemNhanVat() {
    final nv = _nhanVatDangDung;
    final daTai = widget.trangThaiNhanVat == TrangThaiKhoDo.daTai;

    return _KhungMuc(
      tieuDe: 'NHÂN VẬT ĐANG DÙNG',
      bieuTuong: Icons.person_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _XemTruocNhanVat(
            nhanVat: nv,
            danhSachVatPham: widget.danhSachVatPham,
          ),
          const SizedBox(height: 18),
          Text(
            nv?.ten ??
                (daTai
                    ? 'Chưa xác nhận được nhân vật đang dùng'
                    : 'Chưa có dữ liệu nhân vật'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MauGame.chu,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nv?.moTa ??
                'Lựa chọn được đọc từ hệ thống. '
                    'Nhân vật cửa hàng cần được phiên ví '
                    'xác nhận quyền sở hữu.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MauGame.chuPhu,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _khungDanhSachNhanVat() {
    final daTai = widget.trangThaiNhanVat == TrangThaiKhoDo.daTai;

    return _KhungMuc(
      tieuDe: 'BỘ SƯU TẬP NHÂN VẬT',
      bieuTuong: Icons.groups_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (daTai)
            DanhSachNhanVat(
              phienVi: widget.phienVi,
              tepNhanVatDangDung: widget.tepNhanVatDangDung ?? '',
              khiChonNhanVat: _dangXuLyThaoTac || widget.khiChonNhanVat == null
                  ? null
                  : _chonNhanVat,
            )
          else
            _TrangThaiDuLieu(
              trangThai: widget.trangThaiNhanVat,
              thongBaoTrong: 'Chưa có danh sách nhân vật',
              moTaTrong:
                  'George và nhân vật cửa hàng sẽ '
                  'hiển thị khi nguồn dữ liệu sẵn sàng.',
              thongBaoLoi:
                  widget.loiNhanVat ?? 'Không tải được danh sách nhân vật.',
              khiThuLai: widget.khiThuLaiNhanVat,
            ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: MauGame.chinh.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MauGame.chinh.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      color: MauGame.chinh,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'NHÂN VẬT AI',
                        style: TextStyle(
                          color: MauGame.chinh,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Khu vực dành cho nhân vật do AI tạo.',
                  style: TextStyle(color: MauGame.chu, fontSize: 13),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Danh sách được tải từ Backend theo phiên SIWE hiện tại. '
                  'Nhân vật AI không tự động được coi là NFT.',
                  style: TextStyle(
                    color: MauGame.chuPhu,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                NhanVatAiGallery(
                  authController: widget.authController,
                  mayChu: widget.mayChuNhanVat,
                  khiMoTaoNhanVat: widget.khiMoTaoNhanVat,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chonNhanVat(String characterId) async {
    final callback = widget.khiChonNhanVat;

    if (_dangXuLyThaoTac ||
        _phienViBan ||
        callback == null ||
        widget.trangThaiNhanVat != TrangThaiKhoDo.daTai) {
      throw StateError('Chưa thể chọn nhân vật lúc này.');
    }

    final id = int.tryParse(characterId);

    final coTrongDanhMuc =
        id == georgeGoc.id || bangNhanVat.any((nv) => nv.id == id);

    if (id == null || !coTrongDanhMuc) {
      throw StateError('Nhân vật không thuộc danh mục hiện tại.');
    }

    final pv = widget.phienVi;

    if (id != georgeGoc.id &&
        (pv == null || !pv.daKetNoi || !pv.daCo.contains(id))) {
      throw StateError('Chưa xác nhận quyền sở hữu nhân vật.');
    }

    setState(() {
      _dangXuLyThaoTac = true;
    });

    try {
      // Bên gọi cập nhật lựa chọn thật sau khi xác nhận.
      // Widget không tự gán tepNhanVatDangDung.
      await callback(characterId);
    } finally {
      if (mounted) {
        setState(() {
          _dangXuLyThaoTac = false;
        });
      }
    }
  }
}

String _tenDanhMuc(DanhMucVatPham danhMuc) {
  switch (danhMuc) {
    case DanhMucVatPham.vuKhi:
      return 'Vũ khí';
    case DanhMucVatPham.giap:
      return 'Giáp';
    case DanhMucVatPham.giay:
      return 'Giày';
    case DanhMucVatPham.phuKien:
      return 'Phụ kiện';
    case DanhMucVatPham.tieuHao:
      return 'Tiêu hao';
    case DanhMucVatPham.nguyenLieu:
      return 'Nguyên liệu';
    case DanhMucVatPham.nhiemVu:
      return 'Nhiệm vụ';
  }
}

IconData _iconDanhMuc(DanhMucVatPham danhMuc) {
  switch (danhMuc) {
    case DanhMucVatPham.vuKhi:
      return Icons.hardware_rounded;
    case DanhMucVatPham.giap:
      return Icons.shield_outlined;
    case DanhMucVatPham.giay:
      return Icons.directions_run_rounded;
    case DanhMucVatPham.phuKien:
      return Icons.circle_outlined;
    case DanhMucVatPham.tieuHao:
      return Icons.science_outlined;
    case DanhMucVatPham.nguyenLieu:
      return Icons.diamond_outlined;
    case DanhMucVatPham.nhiemVu:
      return Icons.assignment_outlined;
  }
}

class _TabDanhMuc extends StatelessWidget {
  final String nhan;
  final IconData bieuTuong;
  final bool dangChon;
  final VoidCallback khiBam;

  const _TabDanhMuc({
    required this.nhan,
    required this.bieuTuong,
    required this.dangChon,
    required this.khiBam,
  });

  @override
  Widget build(BuildContext context) {
    return GameSegmentButton(
      label: nhan,
      icon: bieuTuong,
      selected: dangChon,
      onTap: khiBam,
    );
  }
}

class _DanhMucBenTrai extends StatelessWidget {
  final List<VatPhamHienThi> danhSach;
  final DanhMucVatPham? dangChon;
  final ValueChanged<DanhMucVatPham?> khiChon;

  const _DanhMucBenTrai({
    required this.danhSach,
    required this.dangChon,
    required this.khiChon,
  });

  int _dem(DanhMucVatPham? danhMuc) => danhMuc == null
      ? danhSach.length
      : danhSach.where((vp) => vp.danhMucHienThi == danhMuc).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF102035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF314B68)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 3, 6, 8),
            child: Text(
              'DANH MỤC',
              style: TextStyle(
                color: MauGame.chinh,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          _MucBenTrai(
            nhan: 'Tất cả',
            soLuong: _dem(null),
            bieuTuong: Icons.grid_view_rounded,
            dangChon: dangChon == null,
            khiBam: () => khiChon(null),
          ),
          for (final danhMuc in const [
            DanhMucVatPham.vuKhi,
            DanhMucVatPham.giap,
            DanhMucVatPham.giay,
          ])
            _MucBenTrai(
              nhan: _tenDanhMuc(danhMuc),
              soLuong: _dem(danhMuc),
              bieuTuong: _iconDanhMuc(danhMuc),
              dangChon: dangChon == danhMuc,
              khiBam: () => khiChon(danhMuc),
            ),
        ],
      ),
    );
  }
}

class _MucBenTrai extends StatelessWidget {
  final String nhan;
  final int soLuong;
  final IconData bieuTuong;
  final bool dangChon;
  final VoidCallback khiBam;

  const _MucBenTrai({
    required this.nhan,
    required this.soLuong,
    required this.bieuTuong,
    required this.dangChon,
    required this.khiBam,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: dangChon
            ? MauGame.chinh.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: khiBam,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
            child: Row(
              children: [
                Icon(
                  bieuTuong,
                  size: 17,
                  color: dangChon ? MauGame.chinh : MauGame.chuPhu,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    nhan,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dangChon ? MauGame.chinh : MauGame.chu,
                      fontSize: 11,
                      fontWeight: dangChon ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1626),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$soLuong', style: const TextStyle(fontSize: 9)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrangTrongDanhMuc extends StatelessWidget {
  final bool coTimKiem;

  const _TrangTrongDanhMuc({required this.coTimKiem});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0B192A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF314B68)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            coTimKiem ? Icons.search_off_rounded : Icons.inventory_2_outlined,
            color: MauGame.chinh,
            size: 38,
          ),
          const SizedBox(height: 10),
          Text(
            coTimKiem
                ? 'Không tìm thấy vật phẩm phù hợp'
                : 'Không có vật phẩm trong danh mục này',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MauGame.chu,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DongTieuDeDialog extends StatelessWidget {
  final String nhan;

  const _DongTieuDeDialog({required this.nhan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        nhan,
        style: const TextStyle(
          color: Color(0xFFFFD77A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DongThongTinDialog extends StatelessWidget {
  final IconData icon;
  final String noiDung;
  final String nhanPhu;

  const _DongThongTinDialog({
    required this.icon,
    required this.noiDung,
    required this.nhanPhu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF10263A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF46627A)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MauGame.chuPhu, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              noiDung,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MauGame.chuPhu, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            nhanPhu,
            style: const TextStyle(
              color: Color(0xFF65D9A4),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DongChiTiet extends StatelessWidget {
  final String nhan;
  final String giaTri;

  const _DongChiTiet({required this.nhan, required this.giaTri});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$nhan: $giaTri',
        style: const TextStyle(
          color: MauGame.chuPhu,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

class _NenKhoDo extends StatelessWidget {
  final Animation<double> animation;

  const _NenKhoDo({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/inventory_cave_bg_v1.png',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.15, 0.55, 1],
              colors: [
                Color(0x15000000),
                Color(0x48030C18),
                Color(0x70030B16),
                Color(0x22000000),
              ],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: animation,
          builder: (_, _) =>
              CustomPaint(painter: _HatBuiKhoDo(animation.value)),
        ),
      ],
    );
  }
}

class _HatBuiKhoDo extends CustomPainter {
  final double tienTrinh;

  const _HatBuiKhoDo(this.tienTrinh);

  @override
  void paint(Canvas canvas, Size size) {
    final vang = Paint()..style = PaintingStyle.fill;
    final xanh = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 24; i++) {
      final seedX = ((i * 71) % 101) / 101;
      final seedY = ((i * 43 + 17) % 97) / 97;
      final daoDong = math.sin((tienTrinh * math.pi * 2) + i * 0.83);
      final x = seedX * size.width + daoDong * 13;
      final y =
          ((seedY - tienTrinh * (0.08 + (i % 4) * 0.012)) % 1) * size.height;
      final alpha = 0.18 + ((daoDong + 1) * 0.09);
      final radius = 0.8 + (i % 3) * 0.55;

      if (i.isEven) {
        vang.color = const Color(0xFFFFD76A).withValues(alpha: alpha);
        canvas.drawCircle(Offset(x, y), radius, vang);
      } else {
        xanh.color = const Color(0xFF36BFFF).withValues(alpha: alpha * 0.75);
        canvas.drawCircle(Offset(x, y), radius, xanh);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HatBuiKhoDo oldDelegate) {
    return oldDelegate.tienTrinh != tienTrinh;
  }
}

class _VienKhungKhoDo extends CustomPainter {
  const _VienKhungKhoDo();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 30 || size.height < 30) return;

    final phatSang = Paint()
      ..color = const Color(0x66F5B829)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final vang = Paint()
      ..color = const Color(0xFFFFD76A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    void veGoc(Path path) {
      canvas.drawPath(path, phatSang);
      canvas.drawPath(path, vang);
    }

    const d = 20.0;
    const le = 5.0;
    veGoc(
      Path()
        ..moveTo(le, d)
        ..lineTo(le, 10)
        ..quadraticBezierTo(le, le, 10, le)
        ..lineTo(d, le)
        ..moveTo(le + 5, d - 2)
        ..lineTo(le + 5, 12)
        ..quadraticBezierTo(le + 5, le + 5, 12, le + 5),
    );
    veGoc(
      Path()
        ..moveTo(size.width - d, le)
        ..lineTo(size.width - 10, le)
        ..quadraticBezierTo(size.width - le, le, size.width - le, 10)
        ..lineTo(size.width - le, d),
    );
    veGoc(
      Path()
        ..moveTo(le, size.height - d)
        ..lineTo(le, size.height - 10)
        ..quadraticBezierTo(le, size.height - le, 10, size.height - le)
        ..lineTo(d, size.height - le),
    );
    veGoc(
      Path()
        ..moveTo(size.width - d, size.height - le)
        ..lineTo(size.width - 10, size.height - le)
        ..quadraticBezierTo(
          size.width - le,
          size.height - le,
          size.width - le,
          size.height - 10,
        )
        ..lineTo(size.width - le, size.height - d),
    );
  }

  @override
  bool shouldRepaint(covariant _VienKhungKhoDo oldDelegate) => false;
}

class _BoCucKho extends StatelessWidget {
  final Widget benTrai;
  final Widget benPhai;

  const _BoCucKho({required this.benTrai, required this.benPhai});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final le = constraints.maxHeight < 450 ? 8.0 : 14.0;

        if (constraints.maxWidth >= 700) {
          final rongTrai = (constraints.maxWidth * 0.3)
              .clamp(230.0, 330.0)
              .toDouble();

          return Padding(
            padding: EdgeInsets.all(le),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: rongTrai,
                  child: SingleChildScrollView(child: benTrai),
                ),
                SizedBox(width: le),
                Expanded(child: SingleChildScrollView(child: benPhai)),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(le),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              benTrai,
              SizedBox(height: le),
              benPhai,
            ],
          ),
        );
      },
    );
  }
}

class _KhungMuc extends StatelessWidget {
  final String tieuDe;
  final IconData bieuTuong;
  final Widget child;

  const _KhungMuc({
    required this.tieuDe,
    required this.bieuTuong,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _VienKhungKhoDo(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF01A2D43), Color(0xE80A1727)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xB9D38A20), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: MauGame.chinh.withValues(alpha: 0.18),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            const BoxShadow(
              color: Color(0xCC020711),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    MauGame.chinh.withValues(alpha: 0.24),
                    const Color(0x66182739),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  bottom: BorderSide(
                    color: MauGame.chinh.withValues(alpha: 0.38),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1626),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: MauGame.chinh),
                      boxShadow: [
                        BoxShadow(
                          color: MauGame.chinh.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Icon(bieuTuong, color: MauGame.chinh, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tieuDe,
                      style: const TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                        shadows: [
                          Shadow(color: Color(0x99FF9D00), blurRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _XemTruocNhanVat extends StatelessWidget {
  final NhanVatBan? nhanVat;
  final List<VatPhamHienThi> danhSachVatPham;

  const _XemTruocNhanVat({this.nhanVat, this.danhSachVatPham = const []});

  @override
  Widget build(BuildContext context) {
    final nv = nhanVat;

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MauGame.chinh.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: MauGame.chinh.withValues(alpha: 0.22),
            blurRadius: 16,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.05),
                radius: 1.15,
                colors: [
                  Color(0xFF132A48),
                  Color(0xFF0A1A30),
                  Color(0xFF071120),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 148,
              height: 148,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD76A).withValues(alpha: 0.24),
                    const Color(0xFF27C6FF).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: nv != null
                  ? NhanVatVoiTrangBi(
                      tepAnh: nv.tepAnh,
                      kichThuoc: 96,
                      danhSachVatPham: danhSachVatPham,
                    )
                  : Container(
                      width: 66,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MauGame.nen.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: MauGame.chu.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        size: 48,
                        color: MauGame.chuPhu,
                      ),
                    ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: MauGame.nen.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                nv == null
                    ? 'CHƯA CÓ DỮ LIỆU NHÂN VẬT HỢP LỆ'
                    : '${nv.ten} · ĐANG DÙNG',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MauGame.chuPhu,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LoaiOTrangBi { kiem, cung, giap, giay }

class _OTrangBi extends StatelessWidget {
  final String nhan;
  final _LoaiOTrangBi loai;
  final String noiDung;
  final bool noiBat;
  final String? duongDanAnh;

  const _OTrangBi({
    required this.nhan,
    required this.loai,
    required this.noiDung,
    this.noiBat = false,
    this.duongDanAnh,
  });

  @override
  Widget build(BuildContext context) {
    final coAnh = duongDanAnh != null && duongDanAnh!.trim().isNotEmpty;

    return SizedBox(
      width: 90,
      child: Column(
        children: [
          GameEquipmentSlot(
            selected: noiBat,
            icon: coAnh
                ? HinhTrangBiFrame(
                    asset: duongDanAnh!,
                    kichThuoc: 34,
                    fallback: CustomPaint(painter: _HinhLoaiTrangBi(loai)),
                  )
                : ExcludeSemantics(
                    child: CustomPaint(painter: _HinhLoaiTrangBi(loai)),
                  ),
          ),
          const SizedBox(height: 7),
          Text(
            nhan,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameInventoryStyle.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            noiDung,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameInventoryStyle.textMuted,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _GhiChu extends StatelessWidget {
  final String noiDung;

  const _GhiChu({required this.noiDung});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: MauGame.chuPhu, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            noiDung,
            style: const TextStyle(
              color: MauGame.chuPhu,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrangThaiDuLieu extends StatelessWidget {
  final TrangThaiKhoDo trangThai;
  final String thongBaoTrong;
  final String moTaTrong;
  final String thongBaoLoi;
  final VoidCallback? khiThuLai;

  const _TrangThaiDuLieu({
    required this.trangThai,
    required this.thongBaoTrong,
    required this.moTaTrong,
    required this.thongBaoLoi,
    this.khiThuLai,
  });

  @override
  Widget build(BuildContext context) {
    final dangTai = trangThai == TrangThaiKhoDo.dangTai;
    final coLoi = trangThai == TrangThaiKhoDo.loi;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MauGame.nen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MauGame.chu.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          if (dangTai)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                color: MauGame.chinh,
                strokeWidth: 2,
              ),
            )
          else
            Icon(
              coLoi ? Icons.error_outline_rounded : Icons.inventory_2_outlined,
              color: MauGame.chinh,
              size: 32,
            ),
          const SizedBox(height: 12),
          Text(
            dangTai
                ? 'Đang tải dữ liệu…'
                : coLoi
                ? thongBaoLoi
                : thongBaoTrong,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MauGame.chu,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!dangTai && !coLoi) ...[
            const SizedBox(height: 8),
            Text(
              moTaTrong,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MauGame.chuPhu,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (coLoi && khiThuLai != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: khiThuLai,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: OutlinedButton.styleFrom(foregroundColor: MauGame.chinh),
            ),
          ],
        ],
      ),
    );
  }
}

class _HinhLoaiTrangBi extends CustomPainter {
  final _LoaiOTrangBi loai;

  const _HinhLoaiTrangBi(this.loai);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);

    final vang = Paint()
      ..color = MauGame.chinh
      ..isAntiAlias = false;

    final thep = Paint()
      ..color = MauGame.chuPhu
      ..isAntiAlias = false;

    switch (loai) {
      case _LoaiOTrangBi.kiem:
        canvas.drawRect(const Rect.fromLTWH(14, 4, 5, 17), thep);
        canvas.drawRect(const Rect.fromLTWH(15, 1, 3, 4), thep);
        canvas.drawRect(const Rect.fromLTWH(9, 20, 15, 4), vang);
        canvas.drawRect(const Rect.fromLTWH(14, 24, 5, 6), vang);
        break;

      case _LoaiOTrangBi.cung:
        final cung = Path()
          ..moveTo(10, 3)
          ..lineTo(18, 7)
          ..lineTo(23, 16)
          ..lineTo(18, 25)
          ..lineTo(10, 29);

        canvas.drawPath(
          cung,
          Paint()
            ..color = MauGame.chinh
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.miter,
        );
        canvas.drawLine(
          const Offset(10, 3),
          const Offset(10, 29),
          Paint()
            ..color = MauGame.chuPhu
            ..strokeWidth = 1,
        );
        canvas.drawRect(const Rect.fromLTWH(4, 15, 23, 2), thep);
        canvas.drawRect(const Rect.fromLTWH(25, 13, 3, 6), thep);
        break;

      case _LoaiOTrangBi.giap:
        final giap = Path()
          ..moveTo(9, 3)
          ..lineTo(13, 7)
          ..lineTo(19, 7)
          ..lineTo(23, 3)
          ..lineTo(30, 10)
          ..lineTo(25, 15)
          ..lineTo(23, 13)
          ..lineTo(23, 29)
          ..lineTo(9, 29)
          ..lineTo(9, 13)
          ..lineTo(7, 15)
          ..lineTo(2, 10)
          ..close();

        canvas.drawPath(giap, thep);
        canvas.drawRect(const Rect.fromLTWH(14, 10, 4, 16), vang);
        break;

      case _LoaiOTrangBi.giay:
        canvas.drawRect(const Rect.fromLTWH(10, 5, 8, 18), thep);
        canvas.drawRect(const Rect.fromLTWH(15, 20, 11, 5), thep);
        canvas.drawRect(const Rect.fromLTWH(9, 24, 18, 4), vang);
        break;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HinhLoaiTrangBi oldDelegate) {
    return oldDelegate.loai != loai;
  }
}
