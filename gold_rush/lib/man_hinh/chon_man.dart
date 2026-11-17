import 'package:flutter/material.dart';

import '../ngon_ngu/ngon_ngu.dart';

import '../blockchain/phien_vi.dart';
import '../giao_dien/mau_game.dart';
import '../gold_rush_game.dart';
import '../man_choi.dart';
import '../world_map/ban_do_the_gioi.dart';
import '../world_map/canh_quan_world_map.dart';
import '../world_map/nut_man_choi.dart';
import '../world_map/tien_trinh_world_map.dart';

/// Chọn màn qua World Map.
///
/// Tiến trình được truyền từ bên ngoài.
/// Widget không tự mở khóa màn hoặc lưu kết quả chơi.
class ManHinhChonMan extends StatefulWidget {
  final GoldRushGame game;
  final TienTrinhWorldMap? tienTrinh;
  final String? loiLuuTienTrinh;

  const ManHinhChonMan({
    super.key,
    required this.game,
    this.tienTrinh,
    this.loiLuuTienTrinh,
  });

  @override
  State<ManHinhChonMan> createState() => _ManHinhChonManState();
}

class _ManHinhChonManState extends State<ManHinhChonMan> {
  int? _idManDangChon;

  GoldRushGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final pv = game.phienVi;

    return Theme(
      data: Theme.of(context).copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFBFA16B),
            foregroundColor: const Color(0xFF242B20),
            minimumSize: const Size.fromHeight(44),
            textStyle: TextStyle(
              fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
            shape: const BeveledRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ),
      ),
      child: Material(
        color: const Color(0xFF18261F),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: pv == null
                    ? _noiDung(null)
                    : ListenableBuilder(
                        listenable: pv,
                        builder: (context, _) => _noiDung(pv),
                      ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xD914221B),
                    border: Border.all(color: const Color(0x887E7655)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: IconButton(
                    tooltip: PhamViNgonNgu.of(context).dich('Quay lại Menu'),
                    onPressed: game.dongChonMan,
                    color: const Color(0xFFD3C5A4),
                    iconSize: 20,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noiDung(PhienVi? pv) {
    final danhSach = game.danhSachMan;
    final tienTrinh = widget.tienTrinh;

    if (danhSach.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: ChuGame(
            'Chưa có dữ liệu màn chơi. '
            'Hãy quay lại Menu và thử lại.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MauGame.chu),
          ),
        ),
      );
    }

    ManChoi? manDangChon;
    for (final man in danhSach) {
      if (man.id == _idManDangChon) manDangChon = man;
    }

    // Chưa có tiến trình: giữ cách chọn màn của bản gốc.
    final trangThaiCacMan = <int, TrangThaiMan>{
      for (final man in danhSach)
        man.id: tienTrinh?.trangThaiCuaMan(man.id) ?? TrangThaiMan.daMo,
    };

    final banDo = BanDoTheGioi(
      danhSachMan: danhSach,
      trangThaiCacMan: trangThaiCacMan,
      manDangChon: manDangChon?.id,
      khiChonMan: (man) {
        setState(() {
          _idManDangChon = man.id;
        });
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final rongBang = constraints.maxWidth < 700
            ? constraints.maxWidth - 24
            : 300.0;
        return Stack(
          children: [
            Positioned.fill(child: banDo),
            if (manDangChon != null)
              Positioned(
                key: const ValueKey('bang-thong-tin-man'),
                right: 12,
                top: 70,
                bottom: 70,
                width: rongBang,
                child: Material(
                  elevation: 10,
                  color: Colors.transparent,
                  child: _bangThongTin(pv, manDangChon),
                ),
              ),
          ],
        );
      },
    );
  }

  String _nhanTrangThai(TrangThaiMan trangThai) {
    switch (trangThai) {
      case TrangThaiMan.chuaMo:
        return 'Chưa mở';
      case TrangThaiMan.daMo:
        return 'Đã mở';
      case TrangThaiMan.hoanThanh:
        return 'Đã hoàn thành';
    }
  }

  Widget _bangThongTin(PhienVi? pv, ManChoi man) {
    final tienTrinh = widget.tienTrinh;
    final trangThai = tienTrinh?.trangThaiCuaMan(man.id);
    final duocVaoMan = tienTrinh?.daMoMan(man.id) ?? true;

    const chuPhu = TextStyle(
      color: Color(0xFFC6C3A7),
      fontSize: 11,
      height: 1.5,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2283329),
        border: Border.all(color: const Color(0xFF7E7655)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: ChuGame(
                    'ĐỊA ĐIỂM ĐANG CHỌN',
                    style: TextStyle(
                      color: Color(0xFFAFA980),
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: PhamViNgonNgu.of(context).dich('Đóng thông tin màn'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _idManDangChon = null),
                  color: const Color(0xFFD3C5A4),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TheMan(game: game, man: man, pv: pv, duocVaoMan: duocVaoMan),
            const SizedBox(height: 12),
            if (trangThai != null)
              ChuGame('Trạng thái: ${_nhanTrangThai(trangThai)}', style: chuPhu)
            else
              const ChuGame(
                'Tiến trình mở khóa chưa được kết nối. '
                'Hiện giữ quyền chọn màn như phiên bản gốc.',
                style: chuPhu,
              ),
            if (tienTrinh != null) ...[
              const SizedBox(height: 8),
              const ChuGame(
                'Thắng để mở màn kế tiếp. Tiến trình được lưu trên máy.',
                style: chuPhu,
              ),
            ],
            if (widget.loiLuuTienTrinh != null) ...[
              const SizedBox(height: 8),
              ChuGame(
                widget.loiLuuTienTrinh!,
                style: chuPhu.copyWith(color: const Color(0xFFF2C77C)),
              ),
            ],
            const SizedBox(height: 10),
            if (pv == null)
              const ChuGame(
                'Màn có cọc cần cấu hình máy chủ và kết nối ví.',
                style: chuPhu,
              )
            else
              ChuGame(
                'Vàng: ${pv.vangDinhDang}'
                '${pv.phieuCho.isEmpty ? '' : '\nChờ nhận: ${pv.vangChoNhan} (tự gộp vào giao dịch)'}',
                style: chuPhu,
              ),
            if (pv != null && (pv.thongBao ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              ChuGame(
                pv.thongBao!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: pv.thongBaoLaLoi
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xFFE6DEC7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Thông tin màn và quy trình vào màn có sẵn.
class _TheMan extends StatelessWidget {
  final GoldRushGame game;
  final ManChoi man;
  final PhienVi? pv;
  final bool duocVaoMan;

  const _TheMan({
    required this.game,
    required this.man,
    required this.pv,
    required this.duocVaoMan,
  });

  @override
  Widget build(BuildContext context) {
    final p = pv;
    final Widget nut;
    String? lyDoKhongVaoDuoc;

    final banKhoa = (p?.dangXuLy ?? false) || (p?.dangHoi ?? false);

    if (!duocVaoMan) {
      nut = const FilledButton(onPressed: null, child: ChuGame('Màn chưa mở'));
      lyDoKhongVaoDuoc =
          'Hoàn thành màn trước để mở khóa màn này. '
          'Tiến trình được lưu trên máy.';
    } else if (man.mienPhi) {
      nut = FilledButton(
        onPressed: banKhoa ? null : () => _choiLuyenTap(p),
        child: const ChuGame('Chơi'),
      );

      if (banKhoa) {
        lyDoKhongVaoDuoc = 'Vui lòng hoàn tất thao tác đang xử lý.';
      }
    } else {
      final duVang =
          p != null &&
          (p.vang + p.vangChoNhan >= BigInt.from(man.coc) ||
              (p.ve.dangMo && p.ve.man == man.id));

      nut = FilledButton(
        onPressed: (p == null || banKhoa || !duVang)
            ? null
            : () => _vaoManCoCoc(context, p),
        child: ChuGame('Cọc ${man.coc}'),
      );

      if (banKhoa) {
        lyDoKhongVaoDuoc = 'Vui lòng hoàn tất thao tác đang xử lý.';
      } else if (p == null) {
        lyDoKhongVaoDuoc =
            'Cần cấu hình máy chủ và kết nối ví để vào màn có cọc.';
      } else if (!duVang) {
        lyDoKhongVaoDuoc = 'Chưa đủ vàng để đặt cọc ${man.coc} vàng.';
      }
    }

    final vung = BoCucWorldMap.vungCuaMan(man.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChuGame(
          'MÀN ${man.id.toString().padLeft(2, '0')} · ${PhamViNgonNgu.of(context).dich(vung.ten).toUpperCase()}',
          style: const TextStyle(
            color: Color(0xFFC7A76A),
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        ChuGame(
          man.ten,
          style: const TextStyle(
            color: Color(0xFFF1E4C4),
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        ChuGame(
          man.chiChoiLocal
              ? 'Màn phiêu lưu local · ${vung.diaDanh}'
              : 'Màn chính thức · ${vung.diaDanh}',
          style: const TextStyle(color: Color(0xFFB5BE9A), fontSize: 12),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: PhamViNgonNgu.of(context).dich('Độ khó ${man.sao} trên 5'),
          child: ExcludeSemantics(
            child: ChuGame(
              '${'★' * man.sao}${'☆' * (5 - man.sao)}',
              style: const TextStyle(
                color: Color(0xFFD1B777),
                fontSize: 18,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: Color(0xFF6B7053)),
        ),
        _DongThongSoMan(
          bieuTuong: Icons.monetization_on_outlined,
          nhan: 'Cần thu thập',
          giaTri: '${man.soXu} xu',
        ),
        _DongThongSoMan(
          bieuTuong: Icons.timer_outlined,
          nhan: 'Thời gian',
          giaTri: man.gioiHanGiay == 0
              ? 'Không giới hạn'
              : dinhDangGiay(man.gioiHanGiay),
        ),
        _DongThongSoMan(
          bieuTuong: Icons.account_balance_wallet_outlined,
          nhan: 'Đặt cọc',
          giaTri: man.mienPhi ? 'Không đặt cọc' : '${man.coc} vàng',
        ),
        if (!man.mienPhi)
          _DongThongSoMan(
            bieuTuong: Icons.card_giftcard_outlined,
            nhan: 'Thưởng thêm',
            giaTri: '${man.thuong} vàng',
          ),
        const SizedBox(height: 14),
        nut,
        if (lyDoKhongVaoDuoc != null) ...[
          const SizedBox(height: 8),
          ChuGame(
            lyDoKhongVaoDuoc,
            style: const TextStyle(
              color: Color(0xFFCCB891),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 14),
        ChuGame(
          man.moTa,
          style: const TextStyle(
            color: Color(0xFFD0CFB3),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        if (!man.mienPhi) ...[
          const SizedBox(height: 10),
          ChuGame(
            'Hoàn thành hợp lệ: ${man.nhanVeKhiHoanThanh} vàng '
            '= ${man.coc} hoàn cọc + ${man.soXu} xu + ${man.thuong} thưởng. '
            'Chết, hết giờ hoặc bỏ ván sẽ mất cọc.',
            style: const TextStyle(
              color: Color(0xFFB6B997),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _choiLuyenTap(PhienVi? p) async {
    if (!duocVaoMan) return;

    String? maVan;
    DateTime? luc;
    if (!man.chiChoiLocal &&
        (game.auth?.canEnterGame != true || game.auth?.walletAddress == null)) {
      p?.baoLoi('Cần đăng nhập và xác thực ví để nhận vàng từ ván chơi.');
      return;
    }
    // Luôn đồng bộ phiên ví trước khi đăng ký màn miễn phí. Trước đây nếu
    // AuthGate vừa xác thực xong nhưng PhienVi chưa kịp tải cửa hàng, app vẫn
    // cho vào chơi local và mã ván không có ticket SoVe để trọng tài ký vàng.
    final auth = game.auth;
    if (p != null &&
        auth?.canEnterGame == true &&
        auth?.walletAddress != null &&
        !p.daKetNoi) {
      final daKetNoi = await p.ketNoiDaXacThuc(auth!.walletAddress!);
      if (!daKetNoi) return;
    }
    if (p != null && p.daKetNoi && p.diaChi != null) {
      maVan = game.nhatKy.sinhMaVan();
      luc = DateTime.now();
      try {
        await p.mayChu.batDauMan(
          maVan: maVan,
          vi: p.diaChi!,
          man: man.id,
          ve: 0,
        );
      } catch (e) {
        p.baoLoi('Không đăng ký được màn chơi với máy chủ: $e');
        return;
      }
    }

    if (!await game.choiMan(man, maVan: maVan, ve: 0, batDauThat: luc)) {
      p?.baoLoi('Không nạp được bản đồ ${man.tep}.');
    }
  }

  Future<void> _vaoManCoCoc(BuildContext context, PhienVi p) async {
    if (!duocVaoMan) return;
    if (!p.giuCho()) return;

    final bool? dongY;

    try {
      dongY = await _hoiXacNhan(context, p);
    } finally {
      p.thaCho();
    }

    if (dongY != true) return;

    final maVan = game.nhatKy.sinhMaVan();
    final kq = await p.chuanBiMan(man, maVan);

    if (kq == null) return;

    if (!await game.choiMan(man, maVan: maVan, ve: kq.ve, batDauThat: kq.luc)) {
      if (!p.daKetNoi) {
        await p.congVang(BigInt.from(man.coc));
      }
      p.baoLoi(
        'Không mở được màn ${man.id}. '
        '${p.daKetNoi ? 'Vé số ${kq.ve} đã đăng ký với máy chủ nên cọc của vé này không lấy lại được — báo giảng viên kèm thông báo lỗi trong console.' : 'Đã hoàn lại ${man.coc} vàng cọc.'}',
      );
    }
  }

  Future<bool?> _hoiXacNhan(BuildContext context, PhienVi p) async {
    if (!await game.napTruocBanDo(man)) {
      p.baoLoi('Không nạp được bản đồ ${man.tep} — chưa trừ vàng.');
      return false;
    }

    final dungLai = await p.coTheDungLaiVe(man);

    final veCungManDaDung =
        p.ve.dangMo && p.ve.man == man.id && !p.veDangMoDaCoPhieu && !dungLai;

    final boVeCu = p.ve.dangMo && p.ve.man != man.id && !p.veDangMoDaCoPhieu;

    if (!context.mounted) return false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: ChuGame(
          'Vào màn ${man.id} · ${PhamViNgonNgu.of(context).dich(man.ten)}?',
        ),
        content: ChuGame(
          '${dungLai ? '• Dùng lại vé số ${p.ve.so} đã đặt cọc ${p.ve.coc} vàng — KHÔNG trừ thêm, không cần MetaMask.\n' : (p.daKetNoi ? '• Trừ ngay ${man.coc} vàng tiền cọc (một giao dịch MetaMask).\n' : '• Trừ ngay ${man.coc} vàng tiền cọc từ ví.\n')}'
          '${veCungManDaDung ? '• Vé số ${p.ve.so} của màn này đã dùng cho một ván không hoàn thành — cần vé mới.\n' : ''}'
          '• Nhặt đủ ${man.soXu} xu trong '
          '${dinhDangGiay(man.gioiHanGiay)}: nhận lại '
          '${man.coc} cọc + ${man.soXu} xu + '
          '${man.thuong} thưởng = '
          '${man.nhanVeKhiHoanThanh} vàng.\n'
          '• Chết, hết giờ, thoát ván hoặc đóng trình duyệt: '
          'mất ${man.coc} vàng cọc.\n'
          '${p.phieuCho.isEmpty ? '' : '• ${p.phieuCho.length} phiếu vàng đang chờ sẽ được nhận trong CÙNG giao dịch.\n'}'
          '${boVeCu ? '• Vé màn ${p.ve.man} đang mở (chưa hoàn thành) sẽ bị bỏ — cọc ${p.ve.coc} của vé đó mất.\n' : ''}'
          'Vàng chỉ dùng trong game, không chuyển nhượng, '
          'không quy đổi ra tiền.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const ChuGame('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: ChuGame(dungLai ? 'Vào màn' : 'Đặt cọc ${man.coc}'),
          ),
        ],
      ),
    );
  }
}

/// Một dòng thông số trong bảng chi tiết màn.
class _DongThongSoMan extends StatelessWidget {
  final IconData bieuTuong;
  final String nhan;
  final String giaTri;

  const _DongThongSoMan({
    required this.bieuTuong,
    required this.nhan,
    required this.giaTri,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bieuTuong, size: 18, color: MauGame.chinh),
          const SizedBox(width: 8),
          Expanded(
            child: ChuGame(
              nhan,
              style: const TextStyle(color: MauGame.chuPhu, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ChuGame(
              giaTri,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: MauGame.chu,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
