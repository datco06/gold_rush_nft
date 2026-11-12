import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../blockchain/nhan_vat.dart';
import '../blockchain/phien_vi.dart';
import '../components/ui/game_inventory_controls.dart';
import '../giao_dien/khung_game.dart';
import '../giao_dien/mau_game.dart';
import '../kho_do/danh_sach_nhan_vat.dart';
import '../kho_do/luoi_vat_pham.dart';
import '../kho_do/the_vat_pham.dart';
import '../kho_do/vat_pham_hien_thi.dart';

enum TrangThaiKhoDo { dangTai, trong, loi, daTai }

enum _SapXepKho { doHiem, ten, loai, soLuong }

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

  const ManHinhKhoDo({
    super.key,
    required this.khiDong,
    this.trangThaiTrangBi = TrangThaiKhoDo.dangTai,
    this.trangThaiNhanVat = TrangThaiKhoDo.dangTai,
    this.danhSachVatPham = const [],
    this.khiTrangBi,
    this.khiThao,
    this.phienVi,
    this.tepNhanVatDangDung,
    this.khiChonNhanVat,
    this.loiTrangBi,
    this.loiNhanVat,
    this.khiThuLaiTrangBi,
    this.khiThuLaiNhanVat,
  });

  @override
  State<ManHinhKhoDo> createState() => _ManHinhKhoDoState();
}

class _ManHinhKhoDoState extends State<ManHinhKhoDo>
    with SingleTickerProviderStateMixin {
  final TextEditingController _timKiem = TextEditingController();
  late final AnimationController _hieuUngNen;
  String? _idVatPhamDangChon;
  DanhMucVatPham? _danhMucDangChon;
  DoHiemVatPham? _doHiemDangLoc;
  _SapXepKho _sapXep = _SapXepKho.doHiem;
  bool _chiDangTrangBi = false;
  bool _dangXuLyThaoTac = false;
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

    final tuKhoa = _boDau(_timKiem.text.trim().toLowerCase());
    final ketQua = widget.danhSachVatPham.where((vp) {
      final dungDanhMuc =
          _danhMucDangChon == null || vp.danhMucHienThi == _danhMucDangChon;
      final dungDoHiem = _doHiemDangLoc == null || vp.doHiem == _doHiemDangLoc;
      final dungTrangBi = !_chiDangTrangBi || vp.dangTrangBi;
      final dungTuKhoa =
          tuKhoa.isEmpty ||
          _boDau(vp.ten.toLowerCase()).contains(tuKhoa) ||
          _boDau(vp.moTa.toLowerCase()).contains(tuKhoa);
      return dungDanhMuc && dungDoHiem && dungTrangBi && dungTuKhoa;
    }).toList();

    ketQua.sort((a, b) {
      switch (_sapXep) {
        case _SapXepKho.doHiem:
          final theoDoHiem = b.doHiem.index.compareTo(a.doHiem.index);
          return theoDoHiem != 0 ? theoDoHiem : a.ten.compareTo(b.ten);
        case _SapXepKho.ten:
          return a.ten.toLowerCase().compareTo(b.ten.toLowerCase());
        case _SapXepKho.loai:
          final theoLoai = a.danhMucHienThi.index.compareTo(
            b.danhMucHienThi.index,
          );
          return theoLoai != 0 ? theoLoai : a.ten.compareTo(b.ten);
        case _SapXepKho.soLuong:
          final theoSoLuong = b.soLuong.compareTo(a.soLuong);
          return theoSoLuong != 0 ? theoSoLuong : a.ten.compareTo(b.ten);
      }
    });

    return ketQua;
  }

  static String _boDau(String value) {
    const coDau =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const khongDau =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var ketQua = value;
    for (var i = 0; i < coDau.length; i++) {
      ketQua = ketQua.replaceAll(coDau[i], khongDau[i]);
    }
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
    _timKiem.dispose();
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
      khiDong: () {
        if (_dangXuLyThaoTac) return;
        widget.khiDong();
      },
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
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
                              const SizedBox(width: 12),
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

  Widget _khungTrangBi() {
    return _KhungMuc(
      tieuDe: 'TRANG BỊ ĐANG DÙNG',
      bieuTuong: Icons.shield_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _XemTruocNhanVat(nhanVat: _nhanVatDangDung),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _OTrangBi(
                nhan: 'Vũ khí chính',
                loai: _LoaiOTrangBi.kiem,
                noiDung: _tenTrangBiTai(OTrangBi.vuKhiChinh),
                noiBat: true,
              ),
              _OTrangBi(
                nhan: 'Vũ khí phụ',
                loai: _LoaiOTrangBi.cung,
                noiDung: _tenTrangBiTai(OTrangBi.vuKhiPhu),
              ),
              _OTrangBi(
                nhan: 'Giáp',
                loai: _LoaiOTrangBi.giap,
                noiDung: _tenTrangBiTai(OTrangBi.giap),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          _thanhCongCu(),
          const SizedBox(height: 14),
          _thanhDanhMuc(),
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0x55728AA5)),
          const SizedBox(height: 16),
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
          const SizedBox(height: 10),
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

  Widget _thanhCongCu() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final timKiem = TextField(
          controller: _timKiem,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
            color: GameInventoryStyle.textPrimary,
            fontSize: 15,
          ),
          decoration: GameInventoryStyle.searchDecoration(
            suffixIcon: _timKiem.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    onPressed: () {
                      _timKiem.clear();
                      setState(() {});
                    },
                    color: GameInventoryStyle.textMuted,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
          ),
        );

        final boLoc = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _NutBoLoc<DoHiemVatPham>(
              nhan: _doHiemDangLoc == null
                  ? 'Độ hiếm'
                  : tenDoHiem(_doHiemDangLoc!),
              bieuTuong: Icons.tune_rounded,
              dangBat: _doHiemDangLoc != null,
              menu: [
                const PopupMenuItem(value: null, child: Text('Mọi độ hiếm')),
                for (final doHiem in DoHiemVatPham.values)
                  PopupMenuItem(value: doHiem, child: Text(tenDoHiem(doHiem))),
              ],
              khiChon: (giaTri) => setState(() => _doHiemDangLoc = giaTri),
            ),
            _NutBoLoc<_SapXepKho>(
              nhan: _tenSapXep(_sapXep),
              bieuTuong: Icons.sort_rounded,
              menu: const [
                PopupMenuItem(value: _SapXepKho.doHiem, child: Text('Độ hiếm')),
                PopupMenuItem(value: _SapXepKho.ten, child: Text('Tên')),
                PopupMenuItem(value: _SapXepKho.loai, child: Text('Loại')),
                PopupMenuItem(
                  value: _SapXepKho.soLuong,
                  child: Text('Số lượng'),
                ),
              ],
              khiChon: (giaTri) {
                if (giaTri != null) setState(() => _sapXep = giaTri);
              },
            ),
            GameToggleButton(
              label: 'Đang trang bị',
              icon: Icons.check_circle_outline_rounded,
              selected: _chiDangTrangBi,
              onChanged: (value) => setState(() => _chiDangTrangBi = value),
            ),
          ],
        );

        if (constraints.maxWidth < 650) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [timKiem, const SizedBox(height: 10), boLoc],
          );
        }

        return Row(
          children: [
            Expanded(child: timKiem),
            const SizedBox(width: 10),
            Flexible(child: boLoc),
          ],
        );
      },
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
        for (final danhMuc in DanhMucVatPham.values)
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
      return _TrangTrongDanhMuc(
        coTimKiem:
            _timKiem.text.trim().isNotEmpty ||
            _doHiemDangLoc != null ||
            _chiDangTrangBi,
      );
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

  String _tenSapXep(_SapXepKho sapXep) {
    switch (sapXep) {
      case _SapXepKho.doHiem:
        return 'Độ hiếm';
      case _SapXepKho.ten:
        return 'Tên';
      case _SapXepKho.loai:
        return 'Loại';
      case _SapXepKho.soLuong:
        return 'Số lượng';
    }
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
                child: Icon(
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

  Widget _hanhDongVatPham(VatPhamHienThi vp) {
    final coTheTrangBi =
        vp.loai == LoaiVatPham.vuKhi || vp.loai == LoaiVatPham.giap;

    if (!coTheTrangBi) {
      return const _GhiChu(
        noiDung:
            'Vật phẩm này không thuộc nhóm vũ khí hoặc giáp. '
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

    if (hienTai.loai != LoaiVatPham.vuKhi && hienTai.loai != LoaiVatPham.giap) {
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
          _XemTruocNhanVat(nhanVat: nv),
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
          const _GhiChu(
            noiDung:
                'Đổi nhân vật chỉ thay ngoại hình '
                'và áp dụng từ ván chơi tiếp theo.',
          ),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                SizedBox(height: 10),
                Text(
                  'Khu vực dành cho nhân vật do AI tạo.',
                  style: TextStyle(color: MauGame.chu, fontSize: 13),
                ),
                SizedBox(height: 6),
                Text(
                  'Chưa kết nối module AI. '
                  'Nhân vật AI được quản lý riêng, '
                  'không tự động được coi là NFT.',
                  style: TextStyle(
                    color: MauGame.chuPhu,
                    fontSize: 12,
                    height: 1.5,
                  ),
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

class _NutBoLoc<T> extends StatelessWidget {
  final String nhan;
  final IconData bieuTuong;
  final bool dangBat;
  final List<PopupMenuEntry<T?>> menu;
  final ValueChanged<T?> khiChon;

  const _NutBoLoc({
    required this.nhan,
    required this.bieuTuong,
    required this.menu,
    required this.khiChon,
    this.dangBat = false,
  });

  @override
  Widget build(BuildContext context) {
    return GameMenuButton<T>(
      label: nhan,
      icon: bieuTuong,
      active: dangBat,
      items: menu,
      onSelected: khiChon,
    );
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
          for (final danhMuc in DanhMucVatPham.values)
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
        final le = constraints.maxHeight < 450 ? 10.0 : 20.0;

        if (constraints.maxWidth >= 700) {
          final rongTrai = (constraints.maxWidth * 0.34)
              .clamp(250.0, 380.0)
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
        padding: const EdgeInsets.all(18),
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
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
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
                    width: 34,
                    height: 34,
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
                    child: Icon(bieuTuong, color: MauGame.chinh, size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tieuDe,
                      style: const TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 15,
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

  const _XemTruocNhanVat({this.nhanVat});

  @override
  Widget build(BuildContext context) {
    final nv = nhanVat;

    return Container(
      height: 220,
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
          const CustomPaint(painter: _NenTraiNhanVat()),
          Center(
            child: Container(
              width: 150,
              height: 78,
              margin: const EdgeInsets.only(top: 78),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD76A).withValues(alpha: 0.6),
                    const Color(0xFFF5B829).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: MauGame.chinh.withValues(alpha: 0.38),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: nv != null
                ? AnhNhanVat(tepAnh: nv.tepAnh, kichThuoc: 100)
                : Container(
                    width: 76,
                    height: 100,
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
                      size: 58,
                      color: MauGame.chuPhu,
                    ),
                  ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

enum _LoaiOTrangBi { kiem, cung, giap }

class _OTrangBi extends StatelessWidget {
  final String nhan;
  final _LoaiOTrangBi loai;
  final String noiDung;
  final bool noiBat;

  const _OTrangBi({
    required this.nhan,
    required this.loai,
    required this.noiDung,
    this.noiBat = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          GameEquipmentSlot(
            selected: noiBat,
            icon: ExcludeSemantics(
              child: CustomPaint(painter: _HinhLoaiTrangBi(loai)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            nhan,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameInventoryStyle.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            noiDung,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameInventoryStyle.textMuted,
              fontSize: 11,
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

/// Cảnh trang trí, không phải bản đồ gameplay.
class _NenTraiNhanVat extends CustomPainter {
  const _NenTraiNhanVat();

  static const _co = Color(0xFF416C36);
  static const _coSang = Color(0xFF4A793C);
  static const _coToi = Color(0xFF385E31);
  static const _ngonCo = Color(0xFF7CA758);
  static const _la = Color(0xFF285337);
  static const _laSang = Color(0xFF3B7042);
  static const _than = Color(0xFF77523A);
  static const _dat = Color(0xFF967044);
  static const _datSang = Color(0xFFB28D58);
  static const _bong = Color(0x440F2316);
  static const _hoa = Color(0xFFE8CB77);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _co);

    const o = 24.0;

    for (var hang = 0; hang < size.height / o; hang++) {
      for (var cot = 0; cot < size.width / o; cot++) {
        final giaTri = (cot * 7 + hang * 13) % 9;

        if (giaTri < 3 || giaTri > 6) {
          canvas.drawRect(
            Rect.fromLTWH(cot * o, hang * o, o, o),
            Paint()..color = giaTri < 3 ? _coSang : _coToi,
          );
        }

        if (giaTri == 4) {
          final x = cot * o + 8;
          final y = hang * o + 12;
          final but = Paint()..color = _ngonCo;

          canvas.drawRect(Rect.fromLTWH(x, y, 2, 5), but);
          canvas.drawRect(Rect.fromLTWH(x + 4, y - 2, 2, 7), but);
        }

        if (giaTri == 6) {
          canvas.drawRect(
            Rect.fromLTWH(cot * o + 16, hang * o + 10, 3, 3),
            Paint()..color = _hoa,
          );
        }
      }
    }

    _veCay(canvas, Offset(size.width * 0.14, 52));
    _veCay(canvas, Offset(size.width * 0.86, 66));

    final tam = Offset(size.width / 2, size.height * 0.69);

    canvas.drawOval(
      Rect.fromCenter(center: tam + const Offset(0, 6), width: 132, height: 38),
      Paint()..color = _bong,
    );
    canvas.drawRect(
      Rect.fromCenter(center: tam, width: 108, height: 28),
      Paint()..color = _dat,
    );
    canvas.drawRect(
      Rect.fromCenter(center: tam - const Offset(0, 7), width: 124, height: 16),
      Paint()..color = _datSang,
    );

    canvas.restore();
  }

  void _veCay(Canvas canvas, Offset diem) {
    canvas.drawOval(
      Rect.fromCenter(
        center: diem + const Offset(0, 28),
        width: 40,
        height: 12,
      ),
      Paint()..color = _bong,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 4, diem.dy, 8, 30),
      Paint()..color = _than,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 21, diem.dy - 20, 42, 28),
      Paint()..color = _la,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 14, diem.dy - 34, 28, 30),
      Paint()..color = _laSang,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 8, diem.dy - 42, 16, 12),
      Paint()..color = _laSang,
    );
  }

  @override
  bool shouldRepaint(covariant _NenTraiNhanVat oldDelegate) {
    return false;
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
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HinhLoaiTrangBi oldDelegate) {
    return oldDelegate.loai != loai;
  }
}
