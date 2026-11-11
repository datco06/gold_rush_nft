import 'package:flutter/material.dart';

import '../blockchain/phien_vi.dart';
import '../cau_hinh.dart';
import '../gold_rush_game.dart';
import '../man_choi.dart';

/// Lớp phủ "Chọn màn": 1 màn luyện tập + các màn có cọc.
///
/// Luật hiển thị NGAY trên thẻ màn, và hỏi xác nhận trước khi đặt cọc — người chơi phải biết rõ
/// mình được gì, mất gì TRƯỚC khi MetaMask hiện hộp thoại.
class ManHinhChonMan extends StatelessWidget {
  final GoldRushGame game;

  const ManHinhChonMan({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final pv = game.phienVi;
    final noiDung = pv == null
        ? _danhSach(context, null)
        : ListenableBuilder(listenable: pv, builder: (context, _) => _danhSach(context, pv));
    return Container(
      color: CauHinh.mauNenMo,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: noiDung),
      ),
    );
  }

  Widget _danhSach(BuildContext context, PhienVi? pv) {
    const phu = TextStyle(color: Color(0xFF9FAEBC), fontSize: 13, height: 1.45);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CHỌN MÀN',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: CauHinh.mauChinh),
        ),
        const SizedBox(height: 6),
        const Text(
          'Màn có cọc: vàng cọc bị trừ NGAY khi vào màn. Nhặt hết xu trước khi hết giờ thì nhận lại cọc '
          '+ xu + thưởng; chết, hết giờ hay thoát giữa chừng thì mất cọc.',
          textAlign: TextAlign.center,
          style: phu,
        ),
        const SizedBox(height: 12),
        if (pv == null)
          const Text(
            'Chưa cấu hình máy chủ (--dart-define=GOLD_RUSH_API=…) — chỉ chơi được màn luyện tập.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFFFB4A9), fontSize: 13),
          )
        else if (!pv.daKetNoi)
          FilledButton.icon(
            onPressed: pv.dangXuLy ? null : pv.ketNoi,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Kết nối MetaMask để chơi màn có cọc'),
          )
        else
          Text(
            'Vàng: ${pv.vang}'
            '${pv.phieuCho.isEmpty ? '' : '  ·  chờ nhận ${pv.vangChoNhan} (tự gộp vào giao dịch)'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: CauHinh.mauChu, fontWeight: FontWeight.w700),
          ),
        if (pv != null && (pv.thongBao ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            pv.thongBao!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: pv.thongBaoLaLoi ? const Color(0xFFFFB4A9) : const Color(0xFF9FAEBC),
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final m in game.danhSachMan) _TheMan(game: game, man: m, pv: pv),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: game.dongChonMan, child: const Text('Đóng')),
      ],
    );
  }
}

class _TheMan extends StatelessWidget {
  final GoldRushGame game;
  final ManChoi man;
  final PhienVi? pv;

  const _TheMan({required this.game, required this.man, required this.pv});

  @override
  Widget build(BuildContext context) {
    final p = pv;
    final Widget nut;
    final banKhoa = (p?.dangXuLy ?? false) || (p?.dangHoi ?? false); // đang chuẩn bị màn có cọc: không cho mở ván khác chen vào
    if (man.mienPhi) {
      nut = FilledButton(onPressed: banKhoa ? null : () => _choiLuyenTap(p), child: const Text('Chơi'));
    } else {
      // Đủ vàng, HOẶC có vé cùng màn đang mở (có thể dùng lại không mất thêm cọc)
      final duVang = p != null &&
          p.daKetNoi &&
          (p.vang + p.vangChoNhan >= BigInt.from(man.coc) || (p.ve.dangMo && p.ve.man == man.id));
      nut = FilledButton(
        onPressed: (p == null || !p.daKetNoi || banKhoa || !duVang)
            ? null
            : () => _vaoManCoCoc(context, p),
        child: Text('Cọc ${man.coc}'),
      );
    }
    final thongSo = [
      '${man.soXu} xu',
      man.gioiHanGiay == 0 ? 'không giới hạn giờ' : '⏱ ${dinhDangGiay(man.gioiHanGiay)}',
      if (!man.mienPhi) 'hoàn thành: +${man.nhanVeKhiHoanThanh} vàng',
    ].join('  ·  ');
    return Card(
      color: const Color(0x22FFFFFF),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: man.mienPhi ? const Color(0xFF2E7D32) : CauHinh.mauChinh,
          foregroundColor: const Color(0xFF241A05),
          child: Text('${man.id}', style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        title: Text(
          '${man.ten}   ${'★' * man.sao}${'☆' * (5 - man.sao)}',
          style: const TextStyle(color: CauHinh.mauChu, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${man.moTa}\n$thongSo',
          style: const TextStyle(color: Color(0xFF9FAEBC), fontSize: 12, height: 1.4),
        ),
        isThreeLine: true,
        trailing: nut,
      ),
    );
  }

  Future<void> _choiLuyenTap(PhienVi? p) async {
    if (!await game.choiMan(man)) p?.baoLoi('Không nạp được bản đồ ${man.tep}.');
  }

  Future<void> _vaoManCoCoc(BuildContext context, PhienVi p) async {
    if (!p.giuCho()) return; // đang hỏi/đang xử lý một màn khác
    final bool? dongY;
    try {
      dongY = await _hoiXacNhan(context, p);
    } finally {
      p.thaCho();
    }
    if (dongY != true) return;
    final maVan = game.nhatKy.sinhMaVan();
    final kq = await p.chuanBiMan(man, maVan);
    if (kq == null) return; // lỗi đã hiện trên màn hình (pv.thongBao)
    if (!await game.choiMan(man, maVan: maVan, ve: kq.ve, batDauThat: kq.luc)) {
      p.baoLoi('Không mở được màn ${man.id}. Vé số ${kq.ve} đã đăng ký với máy chủ nên cọc của vé '
          'này không lấy lại được — báo giảng viên kèm thông báo lỗi trong console.');
    }
  }

  /// Kiểm tra trước rồi hỏi. true = người chơi đồng ý.
  Future<bool?> _hoiXacNhan(BuildContext context, PhienVi p) async {
    // Kiểm tra TRƯỚC khi hỏi: bản đồ nạp được không, vé đang mở có dùng lại được không.
    if (!await game.napTruocBanDo(man)) {
      p.baoLoi('Không nạp được bản đồ ${man.tep} — chưa trừ vàng.');
      return false;
    }
    final dungLai = await p.coTheDungLaiVe(man);
    final veCungManDaDung = p.ve.dangMo && p.ve.man == man.id && !p.veDangMoDaCoPhieu && !dungLai;
    final boVeCu = p.ve.dangMo && p.ve.man != man.id && !p.veDangMoDaCoPhieu;
    if (!context.mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Vào màn ${man.id} · ${man.ten}?'),
        content: Text(
          '${dungLai ? '• Dùng lại vé số ${p.ve.so} đã đặt cọc ${p.ve.coc} vàng — KHÔNG trừ thêm, không cần MetaMask.\n' : '• Trừ ngay ${man.coc} vàng tiền cọc (một giao dịch MetaMask).\n'}'
          '${veCungManDaDung ? '• Vé số ${p.ve.so} của màn này đã dùng cho một ván không hoàn thành — cần vé mới.\n' : ''}'
          '• Nhặt đủ ${man.soXu} xu trong ${dinhDangGiay(man.gioiHanGiay)}: nhận lại '
          '${man.coc} cọc + ${man.soXu} xu + ${man.thuong} thưởng = ${man.nhanVeKhiHoanThanh} vàng.\n'
          '• Chết, hết giờ, thoát ván hoặc đóng trình duyệt: mất ${man.coc} vàng cọc.\n'
          '${p.phieuCho.isEmpty ? '' : '• ${p.phieuCho.length} phiếu vàng đang chờ sẽ được nhận trong CÙNG giao dịch.\n'}'
          '${boVeCu ? '• Vé màn ${p.ve.man} đang mở (chưa hoàn thành) sẽ bị bỏ — cọc ${p.ve.coc} của vé đó mất.\n' : ''}'
          'Vàng chỉ dùng trong game, không chuyển nhượng, không quy đổi ra tiền.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Thôi')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(dungLai ? 'Vào màn' : 'Đặt cọc ${man.coc}'),
          ),
        ],
      ),
    );
  }
}
