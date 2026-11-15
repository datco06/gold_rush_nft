import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/ui/gold_rush_top_bar.dart';
import '../blockchain/may_chu_phieu.dart';
import '../gold_rush_game.dart';
import '../kho_do/danh_sach_trang_bi.dart';
import '../kho_do/nhan_vat_voi_trang_bi.dart';

/// Giao diện mở rương may mắn. Phần thưởng thật sẽ nối ở bước nghiệp vụ sau.
class ManHinhRungRuong extends StatefulWidget {
  final GoldRushGame game;

  const ManHinhRungRuong({super.key, required this.game});

  @override
  State<ManHinhRungRuong> createState() => _ManHinhRungRuongState();
}

class _ManHinhRungRuongState extends State<ManHinhRungRuong>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rungController;
  bool _dangMo = false;

  GoldRushGame get _game => widget.game;

  @override
  void initState() {
    super.initState();
    _rungController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void dispose() {
    _rungController.dispose();
    super.dispose();
  }

  Future<void> _moRuong() async {
    if (_dangMo) return;
    setState(() => _dangMo = true);
    final pv = _game.phienVi;
    final kq = await pv?.moRuong();
    if (!mounted) return;
    if (kq == null) {
      setState(() => _dangMo = false);
      final loi = pv?.thongBao;
      if (loi != null && loi.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(loi)));
      }
      return;
    }
    await _rungController.forward(from: 0);
    await _game.dongBoNFTKhoDo();
    if (!mounted) return;
    setState(() => _dangMo = false);
    await _hienPopupChucMung(kq);
  }

  Future<void> _hienPopupChucMung(KetQuaMoRuong kq) {
    final catalog = danhSachTrangBiCuaHang();
    final vatPham = !kq.laVang && kq.giaTri > 0 && kq.giaTri <= catalog.length
        ? catalog[kq.giaTri - 1]
        : null;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC050A13),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
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
              const Text(
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
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0xFF5C507A), Color(0xFF1D2B43)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFFFD780), width: 2),
                ),
                child: kq.laVang
                    ? const Icon(
                        Icons.monetization_on_rounded,
                        size: 92,
                        color: Color(0xFFFFD780),
                      )
                    : vatPham?.duongDanAnh == null
                    ? const Icon(
                        Icons.card_giftcard_rounded,
                        size: 92,
                        color: Color(0xFFFFD780),
                      )
                    : HinhTrangBiFrame(
                        asset: vatPham!.duongDanAnh!,
                        kichThuoc: 128,
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                kq.laVang ? 'PHẦN THƯỞNG VÀNG' : 'VẬT PHẨM HIẾM',
                style: TextStyle(
                  color: Color(0xFFDDA9F3),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kq.laVang
                    ? 'Bạn nhận được ${kq.giaTri} vàng.'
                    : 'Bạn nhận được ${vatPham?.ten ?? 'vật phẩm'} ×${kq.soLuong}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB9C7D5), fontSize: 15),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
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
                  child: const Text(
                    'ĐÓNG',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pv = _game.phienVi;
    return Material(
      color: const Color(0xFF07121F),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _RungRuongBackground()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                children: [
                  if (pv == null)
                    GoldRushTopBar(
                      activeItem: GoldRushTopBarItem.rungRuong,
                      gold: '0',
                      playerName: _game.auth?.user?.username ?? 'datco6',
                      onSanhCho: _game.veMenu,
                      onCuaHang: () {
                        _game.dongRungRuong();
                        _game.moCuaHang();
                      },
                      onRungRuong: null,
                      onKhoDo: () {
                        _game.dongRungRuong();
                        _game.moKhoDo();
                      },
                      onXuongAi: null,
                      onSettings: _game.moCaiDat,
                      onClose: _game.veMenu,
                      showClose: false,
                    )
                  else
                    ListenableBuilder(
                      listenable: pv,
                      builder: (context, _) => GoldRushTopBar(
                        activeItem: GoldRushTopBarItem.rungRuong,
                        gold: pv.dangXuLy ? '...' : pv.vangDinhDang,
                        playerName: _game.auth?.user?.username ?? 'datco6',
                        onSanhCho: _game.veMenu,
                        onCuaHang: () {
                          _game.dongRungRuong();
                          _game.moCuaHang();
                        },
                        onRungRuong: null,
                        onQuaTang: () {
                          _game.dongRungRuong();
                          _game.moQuaTang();
                        },
                        onKhoDo: () {
                          _game.dongRungRuong();
                          _game.moKhoDo();
                        },
                        onXuongAi: null,
                        onSettings: _game.moCaiDat,
                        onClose: _game.veMenu,
                        showClose: false,
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    '✦ TREASURE UNLOCK ✦',
                    style: TextStyle(
                      color: Color(0xFFE6AE43),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'RƯƠNG MAY MẮN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFDA8A),
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chạm vào nút để đánh thức kho báu',
                    style: TextStyle(color: Color(0xFFAFC0D1), fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          _khungRuong(),
                          const SizedBox(height: 8),
                          _chiPhiVaNutMo(),
                        ],
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

  Widget _khungRuong() {
    return SizedBox(
      height: 260,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedBuilder(
            animation: _rungController,
            builder: (context, _) {
              final phase = _rungController.value * math.pi * 12;
              return Transform.translate(
                offset: Offset(math.sin(phase) * 6, 0),
                child: Transform.rotate(
                  angle: math.sin(phase) * 0.025,
                  child: _RuongMinhHoa(
                    doMo: Curves.easeOutBack.transform(_rungController.value),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chiPhiVaNutMo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x1FF2B33D),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x66F2B33D)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.monetization_on_outlined,
                color: Color(0xFFF2B33D),
                size: 18,
              ),
              SizedBox(width: 9),
              Text(
                '100 vàng',
                style: TextStyle(
                  color: Color(0xFFFFD67A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 10),
              SizedBox(
                height: 16,
                child: VerticalDivider(width: 1, color: Color(0x66F2B33D)),
              ),
              SizedBox(width: 10),
              Text(
                'mỗi lượt mở',
                style: TextStyle(color: Color(0xFFD9BC8C), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 270,
          height: 52,
          child: FilledButton.icon(
            onPressed: _dangMo ? null : _moRuong,
            icon: Icon(
              _dangMo ? Icons.hourglass_top_rounded : Icons.auto_awesome,
            ),
            label: Text(_dangMo ? 'ĐANG MỞ RƯƠNG…' : '✦ MỞ RƯƠNG ✦'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2B33D),
              foregroundColor: const Color(0xFF12202A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 6,
              shadowColor: const Color(0x99F2B33D),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RungRuongBackground extends StatelessWidget {
  const _RungRuongBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1.2,
          colors: [Color(0xFF293B52), Color(0xFF07121F)],
        ),
        border: Border.all(color: const Color(0x332B4057)),
      ),
    );
  }
}

class _RuongMinhHoa extends StatelessWidget {
  final double doMo;

  const _RuongMinhHoa({required this.doMo});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 240,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 8,
            child: Container(
              width: 278,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0x99030810),
                borderRadius: BorderRadius.all(Radius.elliptical(180, 24)),
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            child: Container(
              width: 250,
              height: 124,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF8B3F27), Color(0xFF4B241F)],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                border: Border.all(color: const Color(0xFF5A2D24), width: 6),
                boxShadow: const [
                  BoxShadow(color: Color(0xAA000000), blurRadius: 14),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          4,
                          (_) => Container(
                            height: 2,
                            color: const Color(0x55361A18),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 35,
                    top: 0,
                    bottom: 0,
                    child: _DaiVang(),
                  ),
                  const Positioned(
                    right: 35,
                    top: 0,
                    bottom: 0,
                    child: _DaiVang(),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 51,
                    child: Container(
                      height: 10,
                      color: const Color(0xFFE4A93D),
                    ),
                  ),
                  Positioned(child: _KhoaRuong(doMo: doMo)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 132 + doMo * 52,
            child: Transform.rotate(
              angle: -0.02 - doMo * 0.22,
              child: Container(
                width: 270,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFD477), Color(0xFFB66A26)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF4C2522), width: 6),
                  boxShadow: const [
                    BoxShadow(color: Color(0x99F2B33D), blurRadius: 18),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 196,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0x663F1B19),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(left: 72, bottom: 27, child: _ChanRuong()),
          const Positioned(right: 72, bottom: 27, child: _ChanRuong()),
          Positioned(
            bottom: 0,
            child: Text(
              doMo > .6 ? '✦ RƯƠNG ĐÃ MỞ ✦' : '✦ RƯƠNG ĐÃ SẴN SÀNG ✦',
              style: const TextStyle(
                color: Color(0xFFFFD477),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaiVang extends StatelessWidget {
  const _DaiVang();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      decoration: BoxDecoration(
        color: const Color(0xFFE7A93D),
        border: Border.all(color: const Color(0xFF9C5B24), width: 2),
      ),
    );
  }
}

class _ChanRuong extends StatelessWidget {
  const _ChanRuong();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFFE1A33A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF6D3A1B), width: 3),
      ),
    );
  }
}

class _KhoaRuong extends StatelessWidget {
  final double doMo;

  const _KhoaRuong({required this.doMo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFE4A93D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF6D3A1B), width: 4),
      ),
      child: Icon(
        doMo > .6 ? Icons.auto_awesome : Icons.lock_rounded,
        color: const Color(0xFF5C2D18),
        size: 28,
      ),
    );
  }
}
