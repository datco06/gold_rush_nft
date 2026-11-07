import 'package:flutter/material.dart';

import '../blockchain/nhan_vat.dart';
import '../blockchain/phien_vi.dart';
import '../cau_hinh.dart';
import '../gold_rush_game.dart';

/// Cửa hàng dùng chung PhienVi với các giao diện khác.
class ManHinhCuaHang extends StatelessWidget {
  final GoldRushGame game;

  const ManHinhCuaHang({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final pv = game.phienVi;

    return Material(
      color: CauHinh.mauNenMo,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: CauHinh.mauNen,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: CauHinh.mauChinh.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: pv == null
                        ? _khung(context, const [
                            Text(
                              'Cần máy chủ gold_rush_ai: '
                              'chạy game với '
                              '--dart-define=GOLD_RUSH_API='
                              'http://localhost:8000',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFFFB4A9),
                                height: 1.5,
                              ),
                            ),
                          ])
                        : ListenableBuilder(
                            listenable: pv,
                            builder: (context, _) =>
                                _khung(context, _noiDung(pv)),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _khung(BuildContext context, List<Widget> giua) {
    const chuPhu = TextStyle(
      color: Color(0xFF9FAEBC),
      fontSize: 13,
      height: 1.5,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'CỬA HÀNG NHÂN VẬT',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: CauHinh.mauChinh,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bản học tập trên mạng thử nghiệm: vàng và nhân vật '
          'không chuyển nhượng, không quy đổi ra tiền.',
          textAlign: TextAlign.center,
          style: chuPhu,
        ),
        const SizedBox(height: 18),
        ...giua,
        const SizedBox(height: 16),
        OutlinedButton(onPressed: game.dongCuaHang, child: const Text('Đóng')),
      ],
    );
  }

  List<Widget> _noiDung(PhienVi pv) {
    final dc = pv.diaChi;

    return [
      if (!pv.daKetNoi)
        FilledButton.icon(
          onPressed: pv.dangXuLy ? null : pv.ketNoi,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Kết nối MetaMask'),
        )
      else ...[
        Text(
          'Ví ${dc!.substring(0, 6)}…'
          '${dc.substring(dc.length - 4)}'
          '   ·   Vàng: ${pv.vang}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: CauHinh.mauChu,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (pv.ve.dangMo)
          Text(
            'Vé màn ${pv.ve.man} đang mở '
            '(cọc ${pv.ve.coc})'
            '${pv.veDangMoDaCoPhieu ? ' — đã hoàn thành, chờ nhận' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9FAEBC), fontSize: 12),
          ),
        const SizedBox(height: 10),
        if (pv.phieuCho.isNotEmpty)
          FilledButton.icon(
            onPressed: pv.dangXuLy ? null : pv.nhanTatCa,
            icon: const Icon(Icons.savings_outlined),
            label: Text(
              'Nhận ${pv.phieuCho.length} phiếu '
              '· +${pv.vangChoNhan} vàng',
            ),
          ),
        const SizedBox(height: 10),
        for (final nv in [georgeGoc, ...bangNhanVat])
          _DongNhanVat(
            nhanVat: nv,
            gia: nv.id == 0
                ? BigInt.zero
                : (pv.gia[nv.id] ?? BigInt.from(nv.giaGoiY)),
            daCo: nv.id == 0 || pv.daCo.contains(nv.id),
            dangDung: game.nhanVatDangDung == nv.tepAnh,
            duVang:
                pv.vang + pv.vangChoNhan >=
                (pv.gia[nv.id] ?? BigInt.from(nv.giaGoiY)),
            banKhoa: pv.dangXuLy,
            khiMua: () => pv.mua(nv),
            khiDung: () {
              game.nhanVatDangDung = nv.tepAnh;
              pv.veLai();
            },
          ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: pv.dangXuLy ? null : pv.lamMoi,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Làm mới'),
        ),
      ],
      if (pv.soVanChuaXinPhieu > 0 && !pv.daKetNoi)
        Text(
          '${pv.soVanChuaXinPhieu} ván đang chờ: '
          'kết nối ví để xin phiếu vàng.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9FAEBC), fontSize: 12),
        ),
      if ((pv.thongBao ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          pv.thongBao!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: pv.thongBaoLaLoi
                ? const Color(0xFFFFB4A9)
                : const Color(0xFF9FAEBC),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    ];
  }
}

class _DongNhanVat extends StatelessWidget {
  final NhanVatBan nhanVat;
  final BigInt gia;
  final bool daCo;
  final bool dangDung;
  final bool duVang;
  final bool banKhoa;
  final VoidCallback khiMua;
  final VoidCallback khiDung;

  const _DongNhanVat({
    required this.nhanVat,
    required this.gia,
    required this.daCo,
    required this.dangDung,
    required this.duVang,
    required this.banKhoa,
    required this.khiMua,
    required this.khiDung,
  });

  @override
  Widget build(BuildContext context) {
    final Widget nut;

    if (dangDung) {
      nut = const Chip(label: Text('Đang dùng'));
    } else if (daCo) {
      nut = OutlinedButton(
        onPressed: banKhoa ? null : khiDung,
        child: const Text('Dùng'),
      );
    } else {
      nut = FilledButton(
        onPressed: banKhoa || !duVang ? null : khiMua,
        child: Text('Mua · $gia vàng'),
      );
    }

    return Card(
      color: const Color(0x22FFFFFF),
      child: ListTile(
        leading: Image.asset(
          'assets/images/${nhanVat.tepAnh}',
          width: 32,
          height: 32,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
          scale: 0.5,
          errorBuilder: (_, _, _) => const Icon(Icons.person),
        ),
        title: Text(nhanVat.ten, style: const TextStyle(color: CauHinh.mauChu)),
        subtitle: Text(
          nhanVat.moTa,
          style: const TextStyle(color: Color(0xFF9FAEBC), fontSize: 12),
        ),
        trailing: nut,
      ),
    );
  }
}
