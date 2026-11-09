import 'package:flutter/material.dart';

import '../blockchain/phien_vi.dart';
import '../giao_dien/mau_game.dart';
import '../gold_rush_game.dart';
import '../man_choi.dart';
import '../world_map/ban_do_the_gioi.dart';
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
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.only(left: 16, right: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF202D24),
                  border: Border(bottom: BorderSide(color: Color(0xFF6C6747))),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.explore_outlined,
                      size: 20,
                      color: Color(0xFFCBB583),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'WORLD MAP',
                      style: TextStyle(
                        color: Color(0xFFE7D9B2),
                        fontSize: 16,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Quay lại Menu',
                      onPressed: game.dongChonMan,
                      color: const Color(0xFFD3C5A4),
                      iconSize: 20,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: pv == null
                    ? _noiDung(null)
                    : ListenableBuilder(
                        listenable: pv,
                        builder: (context, _) => _noiDung(pv),
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
          child: Text(
            'Chưa có dữ liệu màn chơi. '
            'Hãy quay lại Menu và thử lại.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MauGame.chu),
          ),
        ),
      );
    }

    // Ưu tiên ô đang xem; khi mới mở, ưu tiên màn từ tiến trình.
    final idUuTien = _idManDangChon ?? tienTrinh?.manHienTai;
    var manDangChon = danhSach.first;

    for (final man in danhSach) {
      if (man.id == idUuTien) {
        manDangChon = man;
        break;
      }
    }

    // Chưa có tiến trình: giữ cách chọn màn của bản gốc.
    final trangThaiCacMan = <int, TrangThaiMan>{
      for (final man in danhSach)
        man.id: tienTrinh?.trangThaiCuaMan(man.id) ?? TrangThaiMan.daMo,
    };

    final banDo = BanDoTheGioi(
      danhSachMan: danhSach,
      trangThaiCacMan: trangThaiCacMan,
      manDangChon: manDangChon.id,
      khiChonMan: (man) {
        setState(() {
          _idManDangChon = man.id;
        });
      },
    );

    final thongTin = _bangThongTin(pv, manDangChon);

    return LayoutBuilder(
      builder: (context, constraints) {
        final namNgang = constraints.maxWidth > constraints.maxHeight;

        final hienThiHaiCot =
            constraints.maxWidth >= 850 ||
            (namNgang && constraints.maxWidth >= 600);

        if (hienThiHaiCot) {
          final chieuRongThongTin = constraints.maxWidth >= 1000
              ? 280.0
              : 256.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: banDo),
              const VerticalDivider(width: 1, color: MauGame.vien),
              SizedBox(width: chieuRongThongTin, child: thongTin),
            ],
          );
        }

        // Màn hình hẹp: bản đồ trên, thông tin cuộn bên dưới.
        return Column(
          children: [
            SizedBox(
              height: (constraints.maxWidth / (1465 / 980) + 36).clamp(
                0.0,
                constraints.maxHeight * 0.58,
              ),
              child: banDo,
            ),
            const Divider(height: 1, color: MauGame.vien),
            Expanded(child: thongTin),
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
      decoration: const BoxDecoration(
        color: Color(0xFF283329),
        border: Border(left: BorderSide(color: Color(0xFF7E7655))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ĐỊA ĐIỂM ĐANG CHỌN',
              style: TextStyle(
                color: Color(0xFFAFA980),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _TheMan(game: game, man: man, pv: pv, duocVaoMan: duocVaoMan),
            const SizedBox(height: 12),
            if (trangThai != null)
              Text('Trạng thái: ${_nhanTrangThai(trangThai)}', style: chuPhu)
            else
              const Text(
                'Tiến trình mở khóa chưa được kết nối. '
                'Hiện giữ quyền chọn màn như phiên bản gốc.',
                style: chuPhu,
              ),
            if (tienTrinh != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Thắng để mở màn kế tiếp. Tiến trình được lưu trên máy.',
                style: chuPhu,
              ),
            ],
            if (widget.loiLuuTienTrinh != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.loiLuuTienTrinh!,
                style: chuPhu.copyWith(color: const Color(0xFFF2C77C)),
              ),
            ],
            const SizedBox(height: 10),
            if (pv == null)
              const Text(
                'Màn có cọc cần cấu hình máy chủ và kết nối ví.',
                style: chuPhu,
              )
            else if (!pv.daKetNoi)
              FilledButton.icon(
                onPressed: pv.dangXuLy || pv.dangHoi ? null : pv.ketNoi,
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 17,
                ),
                label: const Text('Kết nối MetaMask'),
              )
            else
              Text(
                'Vàng: ${pv.vang}'
                '${pv.phieuCho.isEmpty ? '' : '\nChờ nhận: ${pv.vangChoNhan} (tự gộp vào giao dịch)'}',
                style: chuPhu,
              ),
            if (pv != null && (pv.thongBao ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
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
      nut = const FilledButton(onPressed: null, child: Text('Màn chưa mở'));
      lyDoKhongVaoDuoc =
          'Hoàn thành màn trước để mở khóa màn này. '
          'Tiến trình được lưu trên máy.';
    } else if (man.mienPhi) {
      nut = FilledButton(
        onPressed: banKhoa ? null : () => _choiLuyenTap(p),
        child: const Text('Chơi'),
      );

      if (banKhoa) {
        lyDoKhongVaoDuoc = 'Vui lòng hoàn tất thao tác đang xử lý.';
      }
    } else {
      final duVang =
          p != null &&
          p.daKetNoi &&
          (p.vang + p.vangChoNhan >= BigInt.from(man.coc) ||
              (p.ve.dangMo && p.ve.man == man.id));

      nut = FilledButton(
        onPressed: (p == null || !p.daKetNoi || banKhoa || !duVang)
            ? null
            : () => _vaoManCoCoc(context, p),
        child: Text('Cọc ${man.coc}'),
      );

      if (banKhoa) {
        lyDoKhongVaoDuoc = 'Vui lòng hoàn tất thao tác đang xử lý.';
      } else if (p == null) {
        lyDoKhongVaoDuoc =
            'Cần cấu hình máy chủ và kết nối ví để vào màn có cọc.';
      } else if (!p.daKetNoi) {
        lyDoKhongVaoDuoc = 'Hãy kết nối MetaMask để vào màn có cọc.';
      } else if (!duVang) {
        lyDoKhongVaoDuoc = 'Chưa đủ vàng để đặt cọc ${man.coc} vàng.';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MÀN ${man.id.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: Color(0xFFC7A76A),
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          man.ten,
          style: const TextStyle(
            color: Color(0xFFF1E4C4),
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          man.chiChoiLocal
              ? 'Màn phiêu lưu local'
              : man.mienPhi
              ? 'Màn luyện tập'
              : 'Màn có đặt cọc',
          style: const TextStyle(color: Color(0xFFB5BE9A), fontSize: 12),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Độ khó ${man.sao} trên 5',
          child: ExcludeSemantics(
            child: Text(
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
          giaTri: man.mienPhi ? 'Miễn phí' : '${man.coc} vàng',
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
          Text(
            lyDoKhongVaoDuoc,
            style: const TextStyle(
              color: Color(0xFFCCB891),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          man.moTa,
          style: const TextStyle(
            color: Color(0xFFD0CFB3),
            fontSize: 12,
            height: 1.5,
          ),
        ),
        if (!man.mienPhi) ...[
          const SizedBox(height: 10),
          Text(
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

    if (!await game.choiMan(man)) {
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
      p.baoLoi(
        'Không mở được màn ${man.id}. '
        'Vé số ${kq.ve} đã đăng ký với máy chủ nên cọc của vé '
        'này không lấy lại được — báo giảng viên kèm '
        'thông báo lỗi trong console.',
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
        title: Text('Vào màn ${man.id} · ${man.ten}?'),
        content: Text(
          '${dungLai ? '• Dùng lại vé số ${p.ve.so} đã đặt cọc ${p.ve.coc} vàng — KHÔNG trừ thêm, không cần MetaMask.\n' : '• Trừ ngay ${man.coc} vàng tiền cọc (một giao dịch MetaMask).\n'}'
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
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(dungLai ? 'Vào màn' : 'Đặt cọc ${man.coc}'),
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
            child: Text(
              nhan,
              style: const TextStyle(color: MauGame.chuPhu, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
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
