import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ngon_ngu/ngon_ngu.dart';

import '../ai/may_chu_nhan_vat.dart';
import '../blockchain/may_chu_phieu.dart';
import '../blockchain/phien_vi.dart';
import '../blockchain/vi.dart';
import '../components/ui/gold_rush_top_bar.dart';
import '../components/qr_scanner.dart';
import '../gold_rush_game.dart';
import '../kho_do/nhan_vat_voi_trang_bi.dart';
import 'anh_nhan_vat.dart';
import 'ho_so_nhan_vat.dart';

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

  void _moHoSo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CharacterProfileScreen(game: game),
      ),
    );
  }

  Future<void> _moXuongAi() async {
    game.dongQuaTang();
    final api = MayChuNhanVat();
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (aiContext, _, _) => ManHinhAnhNhanVat(
            mayChu: api,
            authController: game.auth,
            vi: game.phienVi?.vi,
            phienVi: game.phienVi,
            tienTrinhController: game.tienTrinh,
            onPlayerTap: () {
              Navigator.of(aiContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => CharacterProfileScreen(game: game),
                ),
              );
            },
            onSanhCho: () {
              Navigator.of(aiContext).pop();
              game.veMenu();
            },
            onCuaHang: () {
              Navigator.of(aiContext).pop();
              game.moCuaHang();
            },
            onRungRuong: () {
              Navigator.of(aiContext).pop();
              game.moRungRuong();
            },
            onQuaTang: () => Navigator.of(aiContext).maybePop(),
            onKhoDo: () {
              Navigator.of(aiContext).pop();
              game.moKhoDo();
            },
            onSettings: game.moCaiDat,
          ),
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          ),
        ),
      );
    } finally {
      api.dong();
    }
  }

  Widget _thanhTren(PhienVi? pv) {
    Widget taoThanhTren() => GoldRushTopBar(
      activeItem: GoldRushTopBarItem.quaTang,
      gold: pv == null ? '0' : (pv.dangXuLy ? '...' : pv.vangDinhDang),
      playerName: game.auth?.user?.username ?? 'datco6',
      onSanhCho: game.veMenu,
      onPlayerTap: _moHoSo,
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
      onXuongAi: _moXuongAi,
      onSettings: game.moCaiDat,
      onClose: game.veMenu,
      showClose: false,
    );

    if (pv == null) return taoThanhTren();
    return ListenableBuilder(
      listenable: pv,
      builder: (context, _) => taoThanhTren(),
    );
  }

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
      if (mounted) {
        setState(
          () => _thongBao = e.ma == 409
              ? 'Mã quà tặng đã được sử dụng hoặc đạt giới hạn nhận.'
              : e.thongBao,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _thongBao = 'Không thể nhận quà: $e');
    } finally {
      if (mounted) setState(() => _dangXuLy = false);
    }
  }

  Future<void> _hienPopupPhanThuong(KetQuaDoiQuaTang result) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC050A13),
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final imageSize = math
            .min(190.0, math.min(size.width - 80, size.height * .30))
            .clamp(96.0, 190.0)
            .toDouble();
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: size.height * .9,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  size.width < 420 ? 16 : 22,
                  size.width < 420 ? 18 : 24,
                  size.width < 420 ? 16 : 22,
                  20,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF263B55), Color(0xFF101D2D)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE4B653), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88000000), blurRadius: 30),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ChuGame(
                      '✦ CHÚC MỪNG BẠN! ✦',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFFFD780),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: imageSize,
                      height: imageSize,
                      decoration: BoxDecoration(
                        gradient: const RadialGradient(
                          colors: [Color(0xFF5C507A), Color(0xFF1D2B43)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFFFFD780),
                          width: 2,
                        ),
                      ),
                      child: result.laVang
                          ? const Icon(
                              Icons.monetization_on_rounded,
                              size: 92,
                              color: Color(0xFFFFD780),
                            )
                          : result.imageUrl.isNotEmpty
                          ? HinhTrangBiFrame(
                              asset: result.imageUrl,
                              kichThuoc: 128,
                            )
                          : const Icon(
                              Icons.card_giftcard_rounded,
                              size: 92,
                              color: Color(0xFFFFD780),
                            ),
                    ),
                    SizedBox(height: size.height < 600 ? 10 : 18),
                    ChuGame(
                      result.laVang ? 'PHẦN THƯỞNG VÀNG' : 'VẬT PHẨM HIẾM',
                      style: const TextStyle(
                        color: Color(0xFFDDA9F3),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ChuGame(
                      result.laVang
                          ? 'Bạn nhận được ${result.amount} vàng.'
                          : 'Bạn nhận được ${result.name} ×${result.amount}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB9C7D5),
                        fontSize: 15,
                      ),
                    ),
                    if (!result.laVang && result.rarity.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ChuGame(
                        result.rarity,
                        style: const TextStyle(color: Color(0xFFB9C7D5)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        if (!result.laVang)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                game.dongQuaTang();
                                game.moKhoDo();
                              },
                              child: const ChuGame('XEM KHO ĐỒ'),
                            ),
                          ),
                        if (!result.laVang) const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE8B64F),
                              foregroundColor: const Color(0xFF211A10),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const ChuGame(
                              'ĐÓNG',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pv = widget.game.phienVi;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 1100 || size.height < 560;
    final giftSize = compact
        ? math.min(150.0, math.max(112.0, size.height * .28))
        : 190.0;
    return Material(
      color: const Color(0xFF081421),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _QuaTangNen()),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 20,
                compact ? 10 : 20,
                compact ? 10 : 20,
                compact ? 8 : 18,
              ),
              child: Column(
                children: [
                  _thanhTren(pv),
                  SizedBox(height: compact ? 8 : 26),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact ? 320 : 720,
                          ),
                          child: Column(
                            children: [
                              ChuGame(
                                '✦ KHO BÁU DÀNH CHO BẠN ✦',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFE6AE43),
                                  fontSize: compact ? 10 : 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 4,
                                ),
                              ),
                              SizedBox(height: compact ? 5 : 14),
                              ChuGame(
                                'TRUNG TÂM\nQUÀ TẶNG',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFFFD889),
                                  fontFamily: 'serif',
                                  fontSize: compact ? 28 : 42,
                                  height: .96,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 18),
                              ChuGame(
                                'Khám phá những mã quà đặc biệt\nvà nhận phần thưởng vào ví Gold Rush.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFAFC0D1),
                                  fontSize: compact ? 11 : 17,
                                  height: compact ? 1.25 : 1.5,
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 28),
                              compact
                                  ? SizedBox(
                                      height: giftSize,
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: const SizedBox(
                                          width: 289,
                                          height: 190,
                                          child: _GiftShowcase(),
                                        ),
                                      ),
                                    )
                                  : const _GiftShowcase(),
                              SizedBox(height: compact ? 8 : 22),
                              SizedBox(
                                width: double.infinity,
                                height: compact ? 46 : 62,
                                child: FilledButton.icon(
                                  onPressed: _dangXuLy ? null : _moQuetMaQr,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                  ),
                                  label: const ChuGame('MỞ CAMERA QUÉT QR'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFF2C76B),
                                    foregroundColor: const Color(0xFF382719),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 7,
                                    textStyle: TextStyle(
                                      fontSize: compact ? 12 : 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 6 : 14),
                              ChuGame(
                                '✧ Quét mã QR hợp lệ để nhận quà ✧',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFAFC0D1),
                                  fontSize: compact ? 11 : 15,
                                ),
                              ),
                              if (_thongBao != null) ...[
                                SizedBox(height: compact ? 6 : 12),
                                ChuGame(
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
                              SizedBox(height: compact ? 8 : 18),
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
              child: ChuGame(
                '✦',
                style: TextStyle(color: Color(0xFFFFDA8A), fontSize: 28),
              ),
            ),
            const Positioned(
              bottom: 50,
              left: 104,
              child: ChuGame(
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
