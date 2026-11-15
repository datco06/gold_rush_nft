import 'package:flutter/material.dart';

import '../blockchain/may_chu_phieu.dart';
import '../blockchain/vi.dart';
import '../components/ui/gold_rush_top_bar.dart';
import '../components/qr_scanner.dart';
import '../gold_rush_game.dart';

class ManHinhTrungTamQuaTang extends StatefulWidget {
  final GoldRushGame game;

  const ManHinhTrungTamQuaTang({super.key, required this.game});

  @override
  State<ManHinhTrungTamQuaTang> createState() => _ManHinhTrungTamQuaTangState();
}

class _ManHinhTrungTamQuaTangState extends State<ManHinhTrungTamQuaTang> {
  bool _dangXuLy = false;
  String? _thongBao;

  GoldRushGame get game => widget.game;

  Future<void> _moQuetMaQr() async {
    final ma = await moQuetMaQr(context);
    if (!mounted || ma == null || ma.isEmpty || _dangXuLy) return;
    await _doiMa(ma);
  }

  Future<void> _doiMa(String ma) async {
    final pv = game.phienVi;
    if (pv == null || !pv.daKetNoi) {
      setState(() => _thongBao = 'Cần kết nối MetaMask trước khi nhận quà.');
      return;
    }
    setState(() {
      _dangXuLy = true;
      _thongBao = 'ĐANG KIỂM TRA MÃ QUÀ…';
    });
    try {
      final claim = await pv.mayChu.doiMaQuaTang(ma);
      if (!mounted) return;
      if (claim.status == 'confirmed') {
        setState(() => _thongBao = null);
        await _hienPopupPhanThuong(claim);
        return;
      }
      setState(() => _thongBao = 'ĐANG CẤP THƯỞNG…');
      final hash = claim.laVang
          ? await game.nhanQuaTangVang(claim.vouchers)
          : await game.nhanQuaTangNFT(claim.voucher!);
      final confirmed = await pv.mayChu.xacNhanQuaTang(
        claimId: claim.claimId,
        transactionHash: hash,
      );
      if (!mounted) return;
      setState(() => _thongBao = null);
      await _hienPopupPhanThuong(confirmed);
    } on LoiVi catch (e) {
      if (mounted) setState(() => _thongBao = e.thongBao);
    } catch (e) {
      if (mounted) setState(() => _thongBao = 'Không thể nhận quà: $e');
    } finally {
      if (mounted) setState(() => _dangXuLy = false);
    }
  }

  Future<void> _hienPopupPhanThuong(KetQuaDoiQuaTang result) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('✦ CHÚC MỪNG! ✦'),
        content: result.laVang
            ? Text(
                '🪙 +${result.amount} VÀNG',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result.imageUrl.isNotEmpty)
                    Image.asset(
                      result.imageUrl,
                      height: 110,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.card_giftcard, size: 72),
                    )
                  else
                    const Icon(Icons.card_giftcard, size: 72),
                  const SizedBox(height: 12),
                  Text(
                    result.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (result.rarity.isNotEmpty) Text(result.rarity),
                  Text('Số lượng ×${result.amount}'),
                ],
              ),
        actions: [
          if (!result.laVang)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                game.dongQuaTang();
                game.moKhoDo();
              },
              child: const Text('XEM KHO ĐỒ'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pv = widget.game.phienVi;
    return Material(
      color: const Color(0xFF081421),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _QuaTangNen()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                children: [
                  GoldRushTopBar(
                    activeItem: GoldRushTopBarItem.quaTang,
                    gold: pv == null
                        ? '0'
                        : (pv.dangXuLy ? '...' : pv.vangDinhDang),
                    playerName: game.auth?.user?.username ?? 'datco6',
                    onSanhCho: game.dongQuaTang,
                    onCuaHang: () {
                      game.dongQuaTang();
                      game.moCuaHang();
                    },
                    onRungRuong: () {
                      game.dongQuaTang();
                      game.moRungRuong();
                    },
                    onQuaTang: null,
                    onKhoDo: () {
                      game.dongQuaTang();
                      game.moKhoDo();
                    },
                    onXuongAi: null,
                    onSettings: game.moCaiDat,
                    onClose: game.dongQuaTang,
                    showClose: false,
                  ),
                  const SizedBox(height: 26),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            children: [
                              const Text(
                                '✦ KHO BÁU DÀNH CHO BẠN ✦',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFE6AE43),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'TRUNG TÂM\nQUÀ TẶNG',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFFFD889),
                                  fontFamily: 'serif',
                                  fontSize: 42,
                                  height: .96,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Khám phá những mã quà đặc biệt\nvà nhận phần thưởng vào ví Gold Rush.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFAFC0D1),
                                  fontSize: 17,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 28),
                              const _GiftShowcase(),
                              const SizedBox(height: 22),
                              SizedBox(
                                width: double.infinity,
                                height: 62,
                                child: FilledButton.icon(
                                  onPressed: _dangXuLy ? null : _moQuetMaQr,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                  ),
                                  label: const Text('MỞ CAMERA QUÉT QR'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFF2C76B),
                                    foregroundColor: const Color(0xFF382719),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 7,
                                    textStyle: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '✧ Quét mã QR hợp lệ để nhận quà ✧',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFAFC0D1),
                                  fontSize: 15,
                                ),
                              ),
                              if (_thongBao != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _thongBao!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _thongBao!.startsWith('ĐANG')
                                        ? const Color(0xFFFFD889)
                                        : const Color(0xFFFFB4A8),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuaTangNen extends StatelessWidget {
  const _QuaTangNen();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(0, -.18),
          radius: 1.15,
          colors: [Color(0xFF253A52), Color(0xFF081421)],
        ),
        border: Border.all(color: const Color(0x332B4057)),
      ),
      child: CustomPaint(painter: _QuaTangVongTrangTri()),
    );
  }
}

class _QuaTangVongTrangTri extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .58);
    final base = size.shortestSide * .34;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x332B4057);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, base * i / 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GiftShowcase extends StatelessWidget {
  const _GiftShowcase();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.52,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x331B2B3E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xCCB8832E)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final scale in [.58, .76, .94])
              FractionallySizedBox(
                widthFactor: scale,
                heightFactor: scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x665F5136)),
                  ),
                ),
              ),
            const _HopQuaPixelArt(),
            const Positioned(
              top: 44,
              right: 84,
              child: Text(
                '✦',
                style: TextStyle(color: Color(0xFFFFDA8A), fontSize: 28),
              ),
            ),
            const Positioned(
              bottom: 50,
              left: 104,
              child: Text(
                '✧',
                style: TextStyle(color: Color(0xFFE6AE43), fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HopQuaPixelArt extends StatelessWidget {
  const _HopQuaPixelArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 18,
            child: Container(
              width: 150,
              height: 116,
              decoration: BoxDecoration(
                color: const Color(0xFFF3AE13),
                border: Border.all(color: const Color(0xFFA76708), width: 5),
                borderRadius: BorderRadius.circular(7),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 16,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 38,
            child: Container(
              width: 166,
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC928),
                border: Border.all(color: const Color(0xFFA76708), width: 5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Positioned(
            top: 36,
            bottom: 19,
            child: Container(
              width: 22,
              decoration: BoxDecoration(
                color: const Color(0xFFD9282F),
                border: Border.symmetric(
                  vertical: BorderSide(
                    color: const Color(0xFF9A1822),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 58,
            left: 20,
            right: 20,
            child: Container(height: 22, color: const Color(0xFFD9282F)),
          ),
          Positioned(
            top: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: -.42,
                  child: _NoQua(size: const Size(55, 34)),
                ),
                Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE83237),
                    border: Border.all(
                      color: const Color(0xFF9A1822),
                      width: 3,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                Transform.rotate(
                  angle: .42,
                  child: _NoQua(size: const Size(55, 34)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoQua extends StatelessWidget {
  final Size size;

  const _NoQua({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: const Color(0xFFE83237),
        border: Border.all(color: const Color(0xFF9A1822), width: 3),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}
