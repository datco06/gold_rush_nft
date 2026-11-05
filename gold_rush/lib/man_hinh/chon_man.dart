import 'package:flutter/material.dart';

import '../blockchain/phien_vi.dart';
import '../giao_dien/khung_game.dart';
import '../giao_dien/mau_game.dart';
import '../gold_rush_game.dart';
import '../man_choi.dart';
import '../world_map/ban_do_the_gioi.dart';
import '../world_map/nut_man_choi.dart';

/// Chọn màn qua World Map, giữ quy trình vào màn của game gốc.
class ManHinhChonMan extends StatefulWidget {
  final GoldRushGame game;

  const ManHinhChonMan({super.key, required this.game});

  @override
  State<ManHinhChonMan> createState() => _ManHinhChonManState();
}

class _ManHinhChonManState extends State<ManHinhChonMan> {
  int? _idManDangChon;

  GoldRushGame get game => widget.game;

  @override
  Widget build(BuildContext context) {
    final pv = game.phienVi;

    return KhungGame(
      tieuDe: 'WORLD MAP',
      chieuRongToiDa: double.infinity,
      khiDong: game.dongChonMan,
      child: pv == null
          ? _noiDung(null)
          : ListenableBuilder(
              listenable: pv,
              builder: (context, _) => _noiDung(pv),
            ),
    );
  }

  Widget _noiDung(PhienVi? pv) {
    final danhSach = game.danhSachMan;

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

    var manDangChon = danhSach.first;

    for (final man in danhSach) {
      if (man.id == _idManDangChon) {
        manDangChon = man;
        break;
      }
    }

    // Giữ quyền chọn màn như bản gốc.
    // Chưa phải dữ liệu tiến trình mở khóa từ Backend.
    final trangThaiCacMan = <int, TrangThaiMan>{
      for (final man in danhSach) man.id: TrangThaiMan.daMo,
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
        if (constraints.maxWidth >= 850) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: banDo),
              const VerticalDivider(width: 1, color: MauGame.vien),
              SizedBox(width: 300, child: thongTin),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 3, child: banDo),
            const Divider(height: 1, color: MauGame.vien),
            Expanded(flex: 2, child: thongTin),
          ],
        );
      },
    );
  }

  Widget _bangThongTin(PhienVi? pv, ManChoi man) {
    const chuPhu = TextStyle(color: MauGame.chuPhu, fontSize: 13, height: 1.5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'THÔNG TIN MÀN',
            style: TextStyle(
              color: MauGame.chinh,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chạm ô trên bản đồ để xem thông tin. '
            'Việc xem thông tin không trừ vàng.',
            style: chuPhu,
          ),
          const SizedBox(height: 8),
          const Text(
            'Tiến trình mở khóa chưa được kết nối. '
            'Hiện giữ quyền chọn màn như phiên bản gốc.',
            style: chuPhu,
          ),
          const SizedBox(height: 16),
          _TheMan(game: game, man: man, pv: pv),
          const SizedBox(height: 12),
          const Text(
            'Màn có cọc: vàng bị trừ khi xác nhận vào màn. '
            'Hoàn thành hợp lệ sẽ nhận lại cọc + xu + thưởng; '
            'chết, hết giờ hoặc bỏ ván sẽ mất cọc.',
            style: chuPhu,
          ),
          const SizedBox(height: 16),
          if (pv == null)
            const Text(
              'Chưa cấu hình máy chủ '
              '(--dart-define=GOLD_RUSH_API=…) — '
              'chỉ chơi được màn luyện tập.',
              style: chuPhu,
            )
          else if (!pv.daKetNoi)
            FilledButton.icon(
              onPressed: pv.dangXuLy || pv.dangHoi ? null : pv.ketNoi,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Kết nối MetaMask'),
            )
          else
            Text(
              'Vàng: ${pv.vang}'
              '${pv.phieuCho.isEmpty ? '' : '\nChờ nhận: ${pv.vangChoNhan} (tự gộp vào giao dịch)'}',
              style: chuPhu,
            ),
          if (pv != null && (pv.thongBao ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              pv.thongBao!,
              style: TextStyle(
                color: pv.thongBaoLaLoi
                    ? Theme.of(context).colorScheme.error
                    : MauGame.chu,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Thông tin màn và quy trình vào màn có sẵn.
class _TheMan extends StatelessWidget {
  final GoldRushGame game;
  final ManChoi man;
  final PhienVi? pv;

  const _TheMan({required this.game, required this.man, required this.pv});

  @override
  Widget build(BuildContext context) {
    final p = pv;
    final Widget nut;

    final banKhoa = (p?.dangXuLy ?? false) || (p?.dangHoi ?? false);

    if (man.mienPhi) {
      nut = FilledButton(
        onPressed: banKhoa ? null : () => _choiLuyenTap(p),
        child: const Text('Chơi'),
      );
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
    }

    return Card(
      color: const Color(0x22FFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: man.mienPhi
                      ? const Color(0xFF2E7D32)
                      : MauGame.chinh,
                  foregroundColor: MauGame.chuTrenVang,
                  child: Text(
                    '${man.id}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        man.ten,
                        style: const TextStyle(
                          color: MauGame.chu,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        man.mienPhi ? 'Màn luyện tập' : 'Màn có đặt cọc',
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
            const SizedBox(height: 14),
            const Text(
              'ĐỘ KHÓ',
              style: TextStyle(
                color: MauGame.chuPhu,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Semantics(
              label: 'Độ khó ${man.sao} trên 5',
              child: ExcludeSemantics(
                child: Text(
                  '${'★' * man.sao}${'☆' * (5 - man.sao)}',
                  style: const TextStyle(
                    color: MauGame.chinh,
                    fontSize: 22,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              man.moTa,
              style: const TextStyle(
                color: MauGame.chuPhu,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: MauGame.vien),
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
            if (!man.mienPhi) ...[
              _DongThongSoMan(
                bieuTuong: Icons.card_giftcard_outlined,
                nhan: 'Thưởng thêm',
                giaTri: '${man.thuong} vàng',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MauGame.chinh.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: MauGame.chinh.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Hoàn thành hợp lệ: nhận '
                  '${man.nhanVeKhiHoanThanh} vàng\n'
                  'Gồm ${man.coc} hoàn cọc + '
                  '${man.soXu} từ xu + '
                  '${man.thuong} thưởng.',
                  style: const TextStyle(
                    color: MauGame.chu,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            nut,
          ],
        ),
      ),
    );
  }

  Future<void> _choiLuyenTap(PhienVi? p) async {
    if (!await game.choiMan(man)) {
      p?.baoLoi('Không nạp được bản đồ ${man.tep}.');
    }
  }

  Future<void> _vaoManCoCoc(BuildContext context, PhienVi p) async {
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
