import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ai/may_chu_nhan_vat.dart';
import '../components/ui/gold_rush_top_bar.dart';
import '../blockchain/may_chu_phieu.dart';
import '../gold_rush_game.dart';
import '../kho_do/danh_sach_trang_bi.dart';
import '../kho_do/nhan_vat_voi_trang_bi.dart';
import '../kho_do/vat_pham_hien_thi.dart';
import 'anh_nhan_vat.dart';
import 'ho_so_nhan_vat.dart';

/// Giao diện mở rương may mắn. Phần thưởng thật sẽ nối ở bước nghiệp vụ sau.
class ManHinhRungRuong extends StatefulWidget {
  final GoldRushGame game;

  const ManHinhRungRuong({super.key, required this.game});

  @override
  State<ManHinhRungRuong> createState() => _ManHinhRungRuongState();
}

class _MucPhanThuongRuong {
  final int? soVang;
  final int? tokenId;

  const _MucPhanThuongRuong.vang(this.soVang) : tokenId = null;
  const _MucPhanThuongRuong.vatPham(this.tokenId) : soVang = null;
}

// Giữ đúng danh sách phần thưởng được backend quay trong core/rung_ruong.py.
const _danhSachPhanThuongRuong = [
  _MucPhanThuongRuong.vang(150),
  _MucPhanThuongRuong.vang(400),
  _MucPhanThuongRuong.vang(700),
  _MucPhanThuongRuong.vang(1000),
  _MucPhanThuongRuong.vang(50000),
  _MucPhanThuongRuong.vatPham(16),
  _MucPhanThuongRuong.vatPham(17),
  _MucPhanThuongRuong.vatPham(18),
  _MucPhanThuongRuong.vatPham(25),
  _MucPhanThuongRuong.vatPham(26),
  _MucPhanThuongRuong.vatPham(27),
  _MucPhanThuongRuong.vatPham(7),
  _MucPhanThuongRuong.vatPham(8),
  _MucPhanThuongRuong.vatPham(9),
];

class _ManHinhRungRuongState extends State<ManHinhRungRuong>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rungController;
  late final ScrollController _phanThuongScrollController;
  bool _dangMo = false;

  GoldRushGame get _game => widget.game;

  void _moHoSo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CharacterProfileScreen(game: _game),
      ),
    );
  }

  Future<void> _moXuongAi() async {
    _game.dongRungRuong();
    final api = MayChuNhanVat();
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (aiContext, _, _) => ManHinhAnhNhanVat(
            mayChu: api,
            authController: _game.auth,
            vi: _game.phienVi?.vi,
            tienTrinhController: _game.tienTrinh,
            onPlayerTap: () {
              Navigator.of(aiContext).push(
                MaterialPageRoute<void>(
                  builder: (_) => CharacterProfileScreen(game: _game),
                ),
              );
            },
            onSanhCho: () {
              Navigator.of(aiContext).pop();
              _game.veMenu();
            },
            onCuaHang: () {
              Navigator.of(aiContext).pop();
              _game.moCuaHang();
            },
            onRungRuong: () => Navigator.of(aiContext).maybePop(),
            onQuaTang: () {
              Navigator.of(aiContext).pop();
              _game.moQuaTang();
            },
            onKhoDo: () {
              Navigator.of(aiContext).pop();
              _game.moKhoDo();
            },
            onSettings: _game.moCaiDat,
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

  @override
  void initState() {
    super.initState();
    _rungController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _phanThuongScrollController = ScrollController();
  }

  @override
  void dispose() {
    _rungController.dispose();
    _phanThuongScrollController.dispose();
    super.dispose();
  }

  Future<void> _moRuong() async {
    if (_dangMo) return;
    setState(() => _dangMo = true);
    final pv = _game.phienVi;
    if (pv == null) {
      if (mounted) setState(() => _dangMo = false);
      return;
    }

    // AuthGate có thể đã kết nối ví nhưng phiên blockchain dùng chung vẫn
    // đang được đồng bộ bất đồng bộ từ lúc game khởi động.
    for (var i = 0; i < 100 && pv.dangXuLy && !pv.daKetNoi; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!pv.daKetNoi) {
      final wallet = _game.auth?.canEnterGame == true
          ? _game.auth?.walletAddress
          : null;
      if (wallet != null && wallet.isNotEmpty) {
        await pv.ketNoiDaXacThuc(wallet);
      } else {
        await pv.ketNoi();
      }
    }
    if (!mounted) return;
    final kq = pv.daKetNoi ? await pv.moRuong() : null;
    if (!mounted) return;
    if (kq == null) {
      setState(() => _dangMo = false);
      final loi = pv.thongBao;
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
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final imageSize = math
            .min(190.0, math.min(size.width - 80, size.height * 0.30))
            .clamp(120.0, 190.0)
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
                    SizedBox(height: size.height < 600 ? 10 : 18),
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
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pv = _game.phienVi;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 1100 || size.height < 500;
    return Material(
      color: const Color(0xFF07121F),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _RungRuongBackground()),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 20,
                compact ? 10 : 20,
                compact ? 10 : 20,
                compact ? 10 : 18,
              ),
              child: Column(
                children: [
                  if (pv == null)
                    GoldRushTopBar(
                      activeItem: GoldRushTopBarItem.rungRuong,
                      gold: '0',
                      playerName: _game.auth?.user?.username ?? 'datco6',
                      onSanhCho: _game.veMenu,
                      onPlayerTap: _moHoSo,
                      onCuaHang: () {
                        _game.dongRungRuong();
                        _game.moCuaHang();
                      },
                      onRungRuong: null,
                      onKhoDo: () {
                        _game.dongRungRuong();
                        _game.moKhoDo();
                      },
                      onXuongAi: _moXuongAi,
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
                        onPlayerTap: _moHoSo,
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
                        onXuongAi: _moXuongAi,
                        onSettings: _game.moCaiDat,
                        onClose: _game.veMenu,
                        showClose: false,
                      ),
                    ),
                  SizedBox(height: compact ? 8 : 18),
                  Text(
                    '✦ TREASURE UNLOCK ✦',
                    style: TextStyle(
                      color: Color(0xFFE6AE43),
                      fontSize: compact ? 10 : 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 10),
                  Text(
                    'RƯƠNG MAY MẮN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFDA8A),
                      fontSize: compact ? 28 : 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: compact ? 3 : 8),
                  Text(
                    'Chạm vào nút để đánh thức kho báu',
                    style: TextStyle(
                      color: Color(0xFFAFC0D1),
                      fontSize: compact ? 12 : 16,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 10),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _noiDungRungRuong(compact: compact),
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

  Widget _noiDungRungRuong({required bool compact}) {
    final khuVucRuong = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _khungRuong(compact: compact),
        SizedBox(height: compact ? 2 : 8),
        _chiPhiVaNutMo(compact: compact),
      ],
    );
    final danhSach = _khungPhanThuong(compact: compact);

    return LayoutBuilder(
      builder: (context, constraints) {
        final khoangCach = compact ? 8.0 : 20.0;
        final chieuRongPanel = compact
            ? (constraints.maxWidth * .43).clamp(170.0, 240.0).toDouble()
            : 330.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                // Co riêng vùng rương để panel phần quà luôn ở bên phải,
                // đồng thời đưa tâm rương thẳng với tiêu đề ở màn hình đủ rộng.
                child: Transform.translate(
                  offset: Offset(
                    constraints.maxWidth >= 700 ? chieuRongPanel / 2 : 0,
                    0,
                  ),
                  child: FittedBox(fit: BoxFit.scaleDown, child: khuVucRuong),
                ),
              ),
            ),
            SizedBox(width: khoangCach),
            SizedBox(width: chieuRongPanel, child: danhSach),
          ],
        );
      },
    );
  }

  Widget _khungPhanThuong({required bool compact}) {
    final catalog = danhSachTrangBiCuaHang();
    final chieuCao = compact ? 238.0 : 348.0;

    return SizedBox(
      width: double.infinity,
      height: chieuCao,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 14,
          compact ? 10 : 14,
          compact ? 8 : 10,
          compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xE61A2B3E), Color(0xE60B1726)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xCCCD961E), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.card_giftcard_rounded,
                  color: const Color(0xFFFFD166),
                  size: compact ? 19 : 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PHẦN QUÀ TRONG RƯƠNG',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFFFD166),
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: compact ? .5 : 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Danh sách phần thưởng có thể nhận',
              style: TextStyle(
                color: const Color(0xFFAFC0D1),
                fontSize: compact ? 10 : 11,
              ),
            ),
            const SizedBox(height: 9),
            Expanded(
              child: Scrollbar(
                controller: _phanThuongScrollController,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _phanThuongScrollController,
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: _danhSachPhanThuongRuong.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) => _dongPhanThuong(
                    muc: _danhSachPhanThuongRuong[index],
                    catalog: catalog,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dongPhanThuong({
    required _MucPhanThuongRuong muc,
    required List<VatPhamHienThi> catalog,
    required bool compact,
  }) {
    final vatPham = muc.tokenId != null && muc.tokenId! <= catalog.length
        ? catalog[muc.tokenId! - 1]
        : null;
    final kichThuoc = compact ? 38.0 : 44.0;
    final noiDungAnh = muc.soVang != null
        ? Icon(
            Icons.monetization_on_rounded,
            color: const Color(0xFFFFD166),
            size: compact ? 26 : 30,
          )
        : vatPham?.duongDanAnh != null
        ? HinhTrangBiFrame(asset: vatPham!.duongDanAnh!, kichThuoc: kichThuoc)
        : Icon(
            Icons.card_giftcard_rounded,
            color: const Color(0xFFFFD166),
            size: compact ? 24 : 28,
          );

    final ten = muc.soVang != null
        ? '${muc.soVang} vàng'
        : vatPham?.ten ?? 'Vật phẩm hiếm';
    final moTa = muc.soVang != null
        ? 'Phần thưởng vàng'
        : _tenDoHiem(vatPham?.doHiem);

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 48 : 56),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1A2C),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0x665B7691)),
      ),
      child: Row(
        children: [
          Container(
            width: kichThuoc,
            height: kichThuoc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF15283D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x5588A0BA)),
            ),
            child: noiDungAnh,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  ten,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFF6F0E3),
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  moTa,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF9FB0C2),
                    fontSize: compact ? 9 : 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tenDoHiem(DoHiemVatPham? doHiem) {
    switch (doHiem) {
      case DoHiemVatPham.hiem:
        return 'Vật phẩm hiếm';
      case DoHiemVatPham.khongPhoBien:
        return 'Vật phẩm mạnh';
      case DoHiemVatPham.thuong:
        return 'Vật phẩm thường';
      case DoHiemVatPham.suThi:
        return 'Vật phẩm sử thi';
      case DoHiemVatPham.huyenThoai:
        return 'Vật phẩm huyền thoại';
      case null:
        return 'Vật phẩm hiếm';
    }
  }

  Widget _khungRuong({required bool compact}) {
    return SizedBox(
      height: compact ? 172 : 260,
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

  Widget _chiPhiVaNutMo({required bool compact}) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0x1FF2B33D),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x66F2B33D)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.monetization_on_outlined,
                color: Color(0xFFF2B33D),
                size: compact ? 16 : 18,
              ),
              SizedBox(width: 9),
              Text(
                '100 vàng',
                style: TextStyle(
                  color: Color(0xFFFFD67A),
                  fontSize: compact ? 14 : 17,
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
                style: TextStyle(
                  color: Color(0xFFD9BC8C),
                  fontSize: compact ? 10 : 12,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 8 : 14),
        SizedBox(
          width: compact ? 240 : 270,
          height: compact ? 44 : 52,
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
