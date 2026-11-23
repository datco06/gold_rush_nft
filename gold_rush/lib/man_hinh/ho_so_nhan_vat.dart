import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ngon_ngu/ngon_ngu.dart';

import 'package:flutter/services.dart';

import '../ai/may_chu_nhan_vat.dart';
import '../blockchain/nhan_vat.dart';
import '../blockchain/sbt/sbt_model.dart';
import '../cau_hinh.dart';
import '../gold_rush_game.dart';
import '../kho_do/danh_sach_nhan_vat.dart' show AnhNhanVat;
import '../kho_do/nhan_vat_voi_trang_bi.dart';
import '../kho_do/vat_pham_hien_thi.dart';
import 'anh_nhan_vat.dart';
import 'kho_do.dart';
import 'main_lobby.dart' show CharacterMiniProfile;
import 'lich_su_man_choi.dart';
import 'bang_xep_hang.dart';

// ═══════════════════════════════════════════════════════════════════
//  PALETTE — extends LobbyColors for Profile-specific tones
// ═══════════════════════════════════════════════════════════════════

abstract final class ProfileColors {
  static const background = Color(0xFF081426);
  static const panel = Color(0xFF13233A);
  static const panelSecondary = Color(0xFF1A2D47);
  static const gold = Color(0xFFF5B829);
  static const goldHighlight = Color(0xFFFFE07A);
  static const crystalBlue = Color(0xFF30BFFF);
  static const purple = Color(0xFFA865FF);
  static const textPrimary = Color(0xFFF5F7FA);
  static const textSecondary = Color(0xFFAFC0D2);
  static const border = Color(0xFF283A52);
}

// ═══════════════════════════════════════════════════════════════════
//  TAB ENUM
// ═══════════════════════════════════════════════════════════════════

enum _ProfileTab { caNhan, huyHieu, vuKhi, nhanVat }

// ═══════════════════════════════════════════════════════════════════
//  MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════

class CharacterProfileScreen extends StatefulWidget {
  final GoldRushGame game;

  const CharacterProfileScreen({super.key, required this.game});

  @override
  State<CharacterProfileScreen> createState() => _CharacterProfileScreenState();
}

class _CharacterProfileScreenState extends State<CharacterProfileScreen>
    with TickerProviderStateMixin {
  _ProfileTab _currentTab = _ProfileTab.caNhan;
  late final AnimationController _idleController;

  bool get _isTestBinding {
    final name = WidgetsBinding.instance.runtimeType.toString();
    return name.contains('TestWidgetsFlutterBinding') ||
        name.contains('AutomatedTest') ||
        name.contains('LiveTest');
  }

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (!_isTestBinding) {
      _idleController.repeat(reverse: true);
    }
    _attachListeners(widget.game);
  }

  void _attachListeners(GoldRushGame g) {
    g.auth?.addListener(_onAuthChanged);
    g.phienVi?.addListener(_onDataChanged);
    g.tienTrinh.addListener(_onDataChanged);
    g.huyHieuDaNhan.addListener(_onDataChanged);
    g.huyHieuSBTDaSoHuu.addListener(_onDataChanged);
  }

  void _detachListeners(GoldRushGame g) {
    g.auth?.removeListener(_onAuthChanged);
    g.phienVi?.removeListener(_onDataChanged);
    g.tienTrinh.removeListener(_onDataChanged);
    g.huyHieuDaNhan.removeListener(_onDataChanged);
    g.huyHieuSBTDaSoHuu.removeListener(_onDataChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final auth = widget.game.auth;
    if (auth != null && !auth.canEnterGame) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant CharacterProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      _detachListeners(oldWidget.game);
      _attachListeners(widget.game);
    }
  }

  @override
  void dispose() {
    _detachListeners(widget.game);
    _idleController.dispose();
    super.dispose();
  }

  NhanVatBan _activeCharacter() {
    final file = widget.game.nhanVatDangDung;
    for (final nv in bangNhanVat) {
      if (nv.tepAnh == file) return nv;
    }
    return georgeGoc;
  }

  int _computeLevel() {
    final g = widget.game;
    final mapCompleted = g.tienTrinhWorldMap.tienTrinh.cacManHoanThanh.length;
    final aiCompleted = g.tienTrinh.tienTrinh?.totalCompleted ?? 0;
    return 1 + math.max<int>(mapCompleted, aiCompleted);
  }

  String _formatGold(BigInt? raw) {
    if (raw == null) return '0';
    final s = raw.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _moKhoDoTab(int tabBanDau) {
    final g = widget.game;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => ValueListenableBuilder<List<VatPhamHienThi>>(
          valueListenable: g.danhSachVatPham,
          builder: (context, items, _) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                return ManHinhKhoDo(
                  tabBanDau: tabBanDau,
                  khiDong: () => Navigator.of(routeContext).pop(),
                  trangThaiTrangBi: TrangThaiKhoDo.daTai,
                  danhSachVatPham: items,
                  khiTrangBi: g.trangBiVatPham,
                  khiThao: g.thaoVatPham,
                  khiHoanDoiNFT: (vatPham, nguoiNhan, soLuong) async {
                    await g.chuyenVatPhamNFT(vatPham, nguoiNhan, soLuong);
                  },
                  layTokenIdNFT: g.tokenIdVatPham,
                  khiLamMoiKhoDo: g.dongBoNFTKhoDo,
                  trangThaiNhanVat: TrangThaiKhoDo.daTai,
                  phienVi: g.phienVi,
                  authController: g.auth,
                  tepNhanVatDangDung: g.nhanVatDangDung,
                  anhNhanVatDangDung: g.taiNguyen.anhNhanVat(g.nhanVatDangDung),
                  tenNhanVatDangDung: g.tenNhanVatDangDung,
                  khiTrangBiNhanVatAi: (nhanVat, spriteSheet) async {
                    await g.trangBiNhanVatAi(
                      characterId: nhanVat.characterId,
                      tenNhanVat: nhanVat.name,
                      spriteSheet: spriteSheet,
                    );
                    if (!context.mounted) return;
                    setModalState(() {});
                  },
                  khiMoTaoNhanVat: () async {
                    final api = MayChuNhanVat();
                    try {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => ManHinhAnhNhanVat(
                            mayChu: api,
                            authController: g.auth,
                            vi: g.phienVi?.vi,
                            phienVi: g.phienVi,
                            tienTrinhController: g.tienTrinh,
                            onPlayerTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      CharacterProfileScreen(game: g),
                                ),
                              );
                            },
                            onSettings: g.moCaiDat,
                          ),
                        ),
                      );
                    } finally {
                      api.dong();
                    }
                  },
                  khiChonNhanVat: (characterId) async {
                    final pv = g.phienVi;
                    if (g.trangThai != TrangThaiChoi.tamDung) {
                      throw StateError('Không thể chọn nhân vật lúc này.');
                    }
                    if ((pv?.dangXuLy ?? false) || (pv?.dangHoi ?? false)) {
                      throw StateError('Phiên ví đang xử lý thao tác khác.');
                    }
                    final id = int.tryParse(characterId);
                    NhanVatBan? nhanVat;
                    if (id == georgeGoc.id) {
                      nhanVat = georgeGoc;
                    } else {
                      for (final nv in bangNhanVat) {
                        if (nv.id == id) {
                          nhanVat = nv;
                          break;
                        }
                      }
                    }
                    if (nhanVat == null) {
                      throw StateError(
                        'Nhân vật không thuộc danh mục hiện tại.',
                      );
                    }
                    if (nhanVat.id != georgeGoc.id &&
                        (pv == null ||
                            !pv.daKetNoi ||
                            !pv.daCo.contains(nhanVat.id))) {
                      throw StateError('Chưa xác nhận quyền sở hữu nhân vật.');
                    }
                    await g.luuNhanVatDaChon(nhanVat);
                    if (!context.mounted) return;
                    setModalState(() {});
                    if (mounted) setState(() {});
                    pv?.veLai();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _onTabSelected(_ProfileTab tab) {
    if (tab == _ProfileTab.vuKhi) {
      _moKhoDoTab(0);
      return;
    }
    if (tab == _ProfileTab.nhanVat) {
      _moKhoDoTab(1);
      return;
    }
    setState(() => _currentTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final nv = _activeCharacter();
    final capDo = _computeLevel();
    final pv = g.phienVi;
    final goldText = pv == null
        ? '0'
        : (pv.dangXuLy ? '...' : _formatGold(pv.vangKhaDung));

    return Material(
      color: ProfileColors.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final compact = w < 1000 || h < 600;
            final menuWidth = compact ? 130.0 : math.min(180.0, w * 0.16);

            return Stack(
              children: [
                // Background cave gradient
                const _CaveBackground(),

                Column(
                  children: [
                    // ── HEADER ──
                    _ProfileHeader(
                      game: g,
                      nhanVat: nv,
                      capDo: capDo,
                      goldText: goldText,
                      compact: compact,
                      onClose: () => Navigator.of(context).pop(),
                    ),

                    // ── BODY: Menu + Character + Panel ──
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // LEFT MENU
                          SizedBox(
                            width: menuWidth,
                            child: _ProfileSidebar(
                              currentTab: _currentTab,
                              compact: compact,
                              onTabChanged: _onTabSelected,
                              onLeaderboard: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ManHinhBangXepHang(game: g),
                                ),
                              ),
                              onHistory: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ManHinhLichSuManChoi(game: g),
                                ),
                              ),
                            ),
                          ),

                          // CENTER CHARACTER
                          Expanded(
                            flex: compact ? 3 : 4,
                            child: _CharacterShowcase(
                              nhanVat: nv,
                              capDo: capDo,
                              idleAnimation: _idleController,
                              compact: compact,
                              game: g,
                            ),
                          ),

                          // RIGHT PANEL
                          Expanded(
                            flex: compact ? 4 : 4,
                            child: _AnimatedTabContent(
                              tab: _currentTab,
                              game: g,
                              nhanVat: nv,
                              capDo: capDo,
                              compact: compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CAVE BACKGROUND
// ═══════════════════════════════════════════════════════════════════

class _CaveBackground extends StatelessWidget {
  const _CaveBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, 0.3),
            radius: 1.4,
            colors: [Color(0xFF162944), Color(0xFF0C1E34), Color(0xFF081426)],
          ),
        ),
        child: CustomPaint(painter: _CrystalsPainter()),
      ),
    );
  }
}

class _CrystalsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ProfileColors.crystalBlue.withValues(alpha: 0.06);
    // Decorative crystal spots
    for (final pos in [
      Offset(size.width * 0.08, size.height * 0.7),
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.92, size.height * 0.65),
      Offset(size.width * 0.85, size.height * 0.9),
      Offset(size.width * 0.5, size.height * 0.95),
    ]) {
      canvas.drawCircle(pos, 30, paint);
      canvas.drawCircle(
        pos,
        15,
        Paint()..color = ProfileColors.crystalBlue.withValues(alpha: 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════
//  HEADER
// ═══════════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  final GoldRushGame game;
  final NhanVatBan nhanVat;
  final int capDo;
  final String goldText;
  final bool compact;
  final VoidCallback onClose;

  const _ProfileHeader({
    required this.game,
    required this.nhanVat,
    required this.capDo,
    required this.goldText,
    required this.compact,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 20,
        vertical: compact ? 8 : 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xE6081426),
        border: Border(bottom: BorderSide(color: ProfileColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CharacterMiniProfile(
                    compact: compact,
                    characterFile: nhanVat.tepAnh,
                    characterName: nhanVat.ten,
                    playerTitle: 'Nhà Thám Hiểm Vàng',
                    level: capDo,
                  ),
                  const SizedBox(width: 16),
                  ChuGame(
                    goldText,
                    style: TextStyle(
                      color: ProfileColors.textPrimary,
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: compact ? 20 : 24,
                    height: compact ? 20 : 24,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ProfileColors.goldHighlight,
                          ProfileColors.gold,
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.monetization_on_rounded,
                      color: const Color(0xFF4A2B00),
                      size: compact ? 15 : 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // HỒ SƠ title
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_rounded,
                color: ProfileColors.goldHighlight,
                size: compact ? 18 : 22,
              ),
              const SizedBox(width: 6),
              ChuGame(
                'HỒ SƠ',
                style: TextStyle(
                  color: ProfileColors.goldHighlight,
                  fontSize: compact ? 14 : 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),

          const SizedBox(width: 12),

          // Close button
          _CloseButton(compact: compact, onTap: onClose),
        ],
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final bool compact;
  final VoidCallback onTap;

  const _CloseButton({required this.compact, required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 32.0 : 38.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: PhamViNgonNgu.of(context).dich('Đóng Hồ sơ'),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _hovered
                  ? const Color(0xFF1A2D47)
                  : ProfileColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? ProfileColors.goldHighlight
                    : ProfileColors.gold.withValues(alpha: 0.7),
                width: 1.5,
              ),
              boxShadow: [
                if (_hovered)
                  BoxShadow(
                    color: ProfileColors.gold.withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
              ],
            ),
            child: Icon(
              Icons.close_rounded,
              color: _hovered
                  ? ProfileColors.goldHighlight
                  : ProfileColors.textSecondary,
              size: widget.compact ? 18 : 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SIDEBAR
// ═══════════════════════════════════════════════════════════════════

class _ProfileSidebar extends StatelessWidget {
  final _ProfileTab currentTab;
  final bool compact;
  final ValueChanged<_ProfileTab> onTabChanged;
  final VoidCallback onLeaderboard;
  final VoidCallback onHistory;

  const _ProfileSidebar({
    required this.currentTab,
    required this.compact,
    required this.onTabChanged,
    required this.onLeaderboard,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: compact ? 8 : 16,
        top: compact ? 8 : 16,
        bottom: compact ? 8 : 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _SidebarButton(
              icon: Icons.person_outline_rounded,
              label: 'CÁ NHÂN',
              active: currentTab == _ProfileTab.caNhan,
              compact: compact,
              onTap: () => onTabChanged(_ProfileTab.caNhan),
            ),
            SizedBox(height: compact ? 6 : 10),
            _SidebarButton(
              icon: Icons.military_tech_rounded,
              label: 'HUY HIỆU',
              active: currentTab == _ProfileTab.huyHieu,
              compact: compact,
              onTap: () => onTabChanged(_ProfileTab.huyHieu),
            ),
            SizedBox(height: compact ? 6 : 10),
            _SidebarButton(
              icon: Icons.gavel_rounded,
              label: 'VŨ KHÍ',
              active: currentTab == _ProfileTab.vuKhi,
              compact: compact,
              onTap: () => onTabChanged(_ProfileTab.vuKhi),
            ),
            SizedBox(height: compact ? 6 : 10),
            _SidebarButton(
              icon: Icons.groups_rounded,
              label: 'NHÂN VẬT',
              active: currentTab == _ProfileTab.nhanVat,
              compact: compact,
              onTap: () => onTabChanged(_ProfileTab.nhanVat),
            ),
            SizedBox(height: compact ? 6 : 10),
            _SidebarButton(
              icon: Icons.emoji_events_outlined,
              label: 'Bảng xếp hạng',
              active: false,
              compact: compact,
              onTap: onLeaderboard,
            ),
            SizedBox(height: compact ? 6 : 10),
            _SidebarButton(
              icon: Icons.history_rounded,
              label: 'Lịch sử màn chơi',
              active: false,
              compact: compact,
              onTap: onHistory,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 14,
            vertical: widget.compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFFD4931A), Color(0xFFF5B829)],
                  )
                : null,
            color: isActive
                ? null
                : (_hovered
                      ? ProfileColors.panelSecondary
                      : ProfileColors.panel),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? ProfileColors.goldHighlight
                  : (_hovered
                        ? ProfileColors.gold.withValues(alpha: 0.5)
                        : ProfileColors.border),
              width: isActive ? 1.8 : 1,
            ),
            boxShadow: [
              if (isActive)
                BoxShadow(
                  color: ProfileColors.gold.withValues(alpha: 0.3),
                  blurRadius: 12,
                ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: isActive
                    ? const Color(0xFF1A0A00)
                    : (_hovered
                          ? ProfileColors.gold
                          : ProfileColors.textSecondary),
                size: widget.compact ? 18 : 22,
              ),
              SizedBox(width: widget.compact ? 6 : 10),
              Expanded(
                child: ChuGame(
                  widget.label,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF1A0A00)
                        : ProfileColors.textPrimary,
                    fontSize: widget.compact ? 11 : 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1A0A00),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CHARACTER SHOWCASE (center)
// ═══════════════════════════════════════════════════════════════════

class _CharacterShowcase extends StatelessWidget {
  final NhanVatBan nhanVat;
  final int capDo;
  final AnimationController idleAnimation;
  final bool compact;
  final GoldRushGame game;

  const _CharacterShowcase({
    required this.nhanVat,
    required this.capDo,
    required this.idleAnimation,
    required this.compact,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    final charSize = compact ? 100.0 : 160.0;

    return AnimatedBuilder(
      animation: idleAnimation,
      builder: (context, child) {
        final offset = math.sin(idleAnimation.value * math.pi) * 4;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, -offset),
              child: Container(
                width: charSize + 40,
                height: charSize + 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ProfileColors.gold.withValues(alpha: 0.15),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: ProfileColors.crystalBlue.withValues(alpha: 0.08),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                  ],
                ),
                child: Center(
                  child: ValueListenableBuilder<List<VatPhamHienThi>>(
                    valueListenable: game.danhSachVatPham,
                    builder: (context, items, _) => NhanVatVoiTrangBi(
                      tepAnh: nhanVat.tepAnh,
                      kichThuoc: charSize,
                      danhSachVatPham: items,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Pedestal glow
            Container(
              width: charSize + 60,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                gradient: RadialGradient(
                  colors: [
                    ProfileColors.gold.withValues(alpha: 0.3),
                    ProfileColors.gold.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Equipment slots below character
            _EquipmentSlots(game: game, compact: compact),
          ],
        );
      },
    );
  }
}

class _EquipmentSlots extends StatelessWidget {
  final GoldRushGame game;
  final bool compact;

  const _EquipmentSlots({required this.game, required this.compact});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<VatPhamHienThi>>(
      valueListenable: game.danhSachVatPham,
      builder: (context, items, _) {
        VatPhamHienThi? findBySlot(OTrangBi o) {
          for (final vp in items) {
            if (vp.oDangTrangBi == o) return vp;
          }
          return null;
        }

        final slots = [
          (OTrangBi.vuKhiChinh, 'Vũ khí chính', Icons.gavel_rounded),
          (OTrangBi.vuKhiPhu, 'Vũ khí phụ', Icons.sports_martial_arts),
          (OTrangBi.giap, 'Giáp', Icons.shield_outlined),
          (OTrangBi.giay, 'Giày', Icons.directions_run_rounded),
        ];

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: compact ? 6 : 10,
          runSpacing: compact ? 6 : 10,
          children: [
            for (final slot in slots)
              _MiniSlot(
                label: slot.$2,
                icon: slot.$3,
                item: findBySlot(slot.$1),
                compact: compact,
              ),
          ],
        );
      },
    );
  }
}

class _MiniSlot extends StatelessWidget {
  final String label;
  final IconData icon;
  final VatPhamHienThi? item;
  final bool compact;

  const _MiniSlot({
    required this.label,
    required this.icon,
    required this.item,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 44.0 : 56.0;
    return Tooltip(
      message: PhamViNgonNgu.of(context)
          .dich(item != null ? '$label: ${item!.ten}' : '$label (Trống)'),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: ProfileColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: item != null
                ? _rarityColor(item!.doHiem)
                : ProfileColors.border,
          ),
        ),
        child: Center(
          child: item != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: _rarityColor(item!.doHiem),
                      size: compact ? 18 : 24,
                    ),
                    if (!compact)
                      ChuGame(
                        item!.thuocTinh.values.firstOrNull ?? '',
                        style: const TextStyle(
                          color: ProfileColors.goldHighlight,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                )
              : Icon(
                  icon,
                  color: ProfileColors.border,
                  size: compact ? 18 : 24,
                ),
        ),
      ),
    );
  }
}

Color _rarityColor(DoHiemVatPham doHiem) => switch (doHiem) {
  DoHiemVatPham.thuong => const Color(0xFF8899AA),
  DoHiemVatPham.khongPhoBien => const Color(0xFF38B86A),
  DoHiemVatPham.hiem => ProfileColors.crystalBlue,
  DoHiemVatPham.suThi => ProfileColors.purple,
  DoHiemVatPham.huyenThoai => ProfileColors.gold,
};

// ═══════════════════════════════════════════════════════════════════
//  ANIMATED TAB CONTENT (right panel)
// ═══════════════════════════════════════════════════════════════════

class _AnimatedTabContent extends StatelessWidget {
  final _ProfileTab tab;
  final GoldRushGame game;
  final NhanVatBan nhanVat;
  final int capDo;
  final bool compact;

  const _AnimatedTabContent({
    required this.tab,
    required this.game,
    required this.nhanVat,
    required this.capDo,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(tab),
        margin: EdgeInsets.all(compact ? 8 : 16),
        padding: EdgeInsets.all(compact ? 12 : 20),
        decoration: BoxDecoration(
          color: ProfileColors.panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ProfileColors.gold.withValues(alpha: 0.4),
            width: 1.3,
          ),
        ),
        child: switch (tab) {
          _ProfileTab.caNhan => _TabCaNhan(
            game: game,
            nhanVat: nhanVat,
            capDo: capDo,
            compact: compact,
          ),
          _ProfileTab.huyHieu => _TabHuyHieu(game: game, compact: compact),
          _ProfileTab.vuKhi => _TabVuKhi(game: game, compact: compact),
          _ProfileTab.nhanVat => _TabNhanVat(
            game: game,
            nhanVat: nhanVat,
            compact: compact,
          ),
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 1 — CÁ NHÂN
// ═══════════════════════════════════════════════════════════════════

class _TabCaNhan extends StatelessWidget {
  final GoldRushGame game;
  final NhanVatBan nhanVat;
  final int capDo;
  final bool compact;

  const _TabCaNhan({
    required this.game,
    required this.nhanVat,
    required this.capDo,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final wallet = game.phienVi?.diaChi ?? game.auth?.walletAddress;
    final walletShort = wallet != null && wallet.length > 12
        ? '${wallet.substring(0, 6)}...${wallet.substring(wallet.length - 4)}'
        : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          const _SectionTitle(
            icon: Icons.info_outline_rounded,
            title: 'THÔNG TIN NHÂN VẬT',
          ),
          const SizedBox(height: 14),

          // Character info card
          Container(
            padding: EdgeInsets.all(compact ? 12 : 16),
            decoration: BoxDecoration(
              color: ProfileColors.panelSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ProfileColors.border),
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: compact ? 56 : 72,
                  height: compact ? 56 : 72,
                  decoration: BoxDecoration(
                    color: ProfileColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ProfileColors.gold, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Center(
                    child: AnhNhanVat(
                      tepAnh: nhanVat.tepAnh,
                      kichThuoc: compact ? 48 : 60,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 12 : 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChuGame(
                        nhanVat.ten,
                        style: TextStyle(
                          color: ProfileColors.textPrimary,
                          fontSize: compact ? 16 : 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ChuGame(
                        'Nhà Thám Hiểm Vàng',
                        style: TextStyle(
                          color: ProfileColors.goldHighlight,
                          fontSize: compact ? 12 : 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD4931A), Color(0xFFF5B829)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ChuGame(
                          'Lv.$capDo',
                          style: TextStyle(
                            color: const Color(0xFF1A0A00),
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (walletShort != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ChuGame(
                              'Ví: $walletShort',
                              style: TextStyle(
                                color: ProfileColors.textSecondary,
                                fontSize: compact ? 10.5 : 12,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: wallet!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: ChuGame('Đã sao chép địa chỉ ví'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.copy_rounded,
                                size: compact ? 13 : 15,
                                color: ProfileColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: compact ? 16 : 24),

          // TRANG BỊ HIỆN TẠI
          const _SectionTitle(
            icon: Icons.shield_rounded,
            title: 'TRANG BỊ HIỆN TẠI',
          ),
          const SizedBox(height: 10),
          _EquippedItemsList(game: game, compact: compact),

          SizedBox(height: compact ? 16 : 24),

          // HUY HIỆU TRƯNG BÀY
          const _SectionTitle(
            icon: Icons.military_tech_rounded,
            title: 'HUY HIỆU TRƯNG BÀY',
          ),
          const SizedBox(height: 10),
          _DisplayedBadges(game: game, compact: compact),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: ProfileColors.gold, size: 18),
        const SizedBox(width: 8),
        ChuGame(
          title,
          style: const TextStyle(
            color: ProfileColors.gold,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ── Equipped items list (CÁ NHÂN tab) ──

class _EquippedItemsList extends StatelessWidget {
  final GoldRushGame game;
  final bool compact;

  const _EquippedItemsList({required this.game, required this.compact});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<VatPhamHienThi>>(
      valueListenable: game.danhSachVatPham,
      builder: (context, items, _) {
        final equipped = items.where((v) => v.oDangTrangBi != null).toList();
        if (equipped.isEmpty) {
          return _EmptyState(
            message: PhamViNgonNgu.of(context)
                .dich('Chưa có trang bị nào được sử dụng.'),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in equipped)
              _EquipmentCard(item: item, compact: compact, game: game),
          ],
        );
      },
    );
  }
}

class _EquipmentCard extends StatefulWidget {
  final VatPhamHienThi item;
  final bool compact;
  final GoldRushGame game;

  const _EquipmentCard({
    required this.item,
    required this.compact,
    required this.game,
  });

  @override
  State<_EquipmentCard> createState() => _EquipmentCardState();
}

class _EquipmentCardState extends State<_EquipmentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = _rarityColor(item.doHiem);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _showItemDetail(context, item, widget.game),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.compact ? 110 : 140,
          padding: EdgeInsets.all(widget.compact ? 8 : 10),
          decoration: BoxDecoration(
            color: _hovered
                ? ProfileColors.panelSecondary
                : ProfileColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.duongDanAnh != null &&
                  item.duongDanAnh!.trim().isNotEmpty)
                HinhTrangBiFrame(
                  asset: item.duongDanAnh!,
                  kichThuoc: widget.compact ? 28 : 34,
                  fallback: Icon(
                    _iconForVatPham(item),
                    color: color,
                    size: widget.compact ? 26 : 32,
                  ),
                )
              else
                Icon(
                  _iconForVatPham(item),
                  color: color,
                  size: widget.compact ? 26 : 32,
                ),
              const SizedBox(height: 4),
              ChuGame(
                item.ten,
                style: TextStyle(
                  color: ProfileColors.textPrimary,
                  fontSize: widget.compact ? 10.5 : 12,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.oDangTrangBi != null)
                ChuGame(
                  _slotLabel(item.oDangTrangBi!),
                  style: TextStyle(
                    color: color,
                    fontSize: widget.compact ? 9 : 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showItemDetail(
  BuildContext context,
  VatPhamHienThi item,
  GoldRushGame game,
) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: ProfileColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _rarityColor(item.doHiem).withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForVatPham(item),
                    color: _rarityColor(item.doHiem),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ChuGame(
                          item.ten,
                          style: const TextStyle(
                            color: ProfileColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        ChuGame(
                          item.doHiem.name.toUpperCase(),
                          style: TextStyle(
                            color: _rarityColor(item.doHiem),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item.moTa.isNotEmpty) ...[
                const SizedBox(height: 12),
                ChuGame(
                  item.moTa,
                  style: const TextStyle(
                    color: ProfileColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
              if (item.thuocTinh.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final e in item.thuocTinh.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ChuGame(
                          e.key,
                          style: const TextStyle(
                            color: ProfileColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        ChuGame(
                          e.value,
                          style: const TextStyle(
                            color: ProfileColors.goldHighlight,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (item.oDangTrangBi != null) ...[
                const SizedBox(height: 8),
                ChuGame(
                  'Đang trang bị: ${_slotLabel(item.oDangTrangBi!)}',
                  style: const TextStyle(
                    color: ProfileColors.gold,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    game.moKhoDo();
                  },
                  icon: const Icon(Icons.backpack_outlined, size: 16),
                  label: const ChuGame('Mở Kho đồ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProfileColors.gold,
                    foregroundColor: const Color(0xFF1A0A00),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _slotLabel(OTrangBi o) => switch (o) {
  OTrangBi.vuKhiChinh => 'Vũ khí chính',
  OTrangBi.vuKhiPhu => 'Vũ khí phụ',
  OTrangBi.giap => 'Giáp',
  OTrangBi.giay => 'Giày',
};

IconData _iconForVatPham(VatPhamHienThi vp) => switch (vp.bieuTuong) {
  BieuTuongVatPham.kiem => Icons.gavel_rounded,
  BieuTuongVatPham.cung => Icons.sports_martial_arts,
  BieuTuongVatPham.giap => Icons.shield_outlined,
  BieuTuongVatPham.binhHoiPhuc => Icons.local_drink_rounded,
  BieuTuongVatPham.macDinh => Icons.inventory_2_outlined,
};

// ── Displayed badges (CÁ NHÂN tab) ──

class _DisplayedBadges extends StatelessWidget {
  final GoldRushGame game;
  final bool compact;

  const _DisplayedBadges({required this.game, required this.compact});

  List<ThanhTuuSBT> _getDisplayed() {
    // Hiển thị toàn bộ danh mục; trạng thái sở hữu được thể hiện bằng
    // màu sáng hoặc làm mờ/khóa ở từng huy hiệu.
    return _badgesFor(game);
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _getDisplayed();
    if (displayed.isEmpty) {
      return _EmptyState(
        message: PhamViNgonNgu.of(context)
            .dich('Bạn chưa trưng bày huy hiệu nào.'),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final badge in displayed)
          _BadgeChip(badge: badge, compact: compact),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 2 — HUY HIỆU
// ═══════════════════════════════════════════════════════════════════

class _TabHuyHieu extends StatelessWidget {
  final GoldRushGame game;
  final bool compact;

  const _TabHuyHieu({required this.game, required this.compact});

  @override
  Widget build(BuildContext context) {
    final badges = _badgesFor(game);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.military_tech_rounded,
            title: 'HUY HIỆU',
          ),
          const SizedBox(height: 6),
          ChuGame(
            'Huy hiệu Thành tựu (SBT) — chưa kết nối API đồng bộ & chọn huy hiệu trưng bày',
            style: TextStyle(
              color: ProfileColors.textSecondary,
              fontSize: compact ? 11 : 12,
            ),
          ),
          const SizedBox(height: 14),
          if (badges.isEmpty)
            _EmptyState(
              message: PhamViNgonNgu.of(context).dich(
                'Chưa có dữ liệu huy hiệu.\n'
                'Kết nối ví và hoàn thành thành tựu để nhận huy hiệu SBT.',
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final badge in badges)
                  _BadgeTile(badge: badge, compact: compact),
              ],
            ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final ThanhTuuSBT badge;
  final bool compact;

  const _BadgeTile({required this.badge, required this.compact});

  @override
  Widget build(BuildContext context) {
    final isOwned = badge.owned;
    final isDisplayed = badge.displayed;
    final color = isOwned ? ProfileColors.gold : ProfileColors.border;

    return Tooltip(
      message: badge.description,
      child: Container(
        width: compact ? 110 : 140,
        padding: EdgeInsets.all(compact ? 10 : 14),
        decoration: BoxDecoration(
          color: isDisplayed
              ? ProfileColors.gold.withValues(alpha: 0.1)
              : ProfileColors.panelSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDisplayed
                ? ProfileColors.gold
                : (isOwned
                      ? ProfileColors.gold.withValues(alpha: 0.5)
                      : ProfileColors.border),
            width: isDisplayed ? 1.8 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge.imagePath != null)
              Opacity(
                opacity: isOwned ? 1 : 0.35,
                child: Image.asset(
                  badge.imagePath!,
                  width: compact ? 42 : 54,
                  height: compact ? 42 : 54,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.military_tech_rounded,
                    color: color,
                    size: compact ? 28 : 34,
                  ),
                ),
              )
            else
              Icon(
                Icons.military_tech_rounded,
                color: color,
                size: compact ? 28 : 34,
              ),
            const SizedBox(height: 6),
            ChuGame(
              badge.name,
              style: TextStyle(
                color: isOwned
                    ? ProfileColors.textPrimary
                    : ProfileColors.textSecondary,
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ChuGame(
              isDisplayed
                  ? 'Đang trưng bày'
                  : (isOwned ? 'Đã mở khóa' : 'Chưa mở khóa'),
              style: TextStyle(
                color: isDisplayed
                    ? ProfileColors.gold
                    : (isOwned
                          ? ProfileColors.crystalBlue
                          : const Color(0xFF5A6A7A)),
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final ThanhTuuSBT badge;
  final bool compact;

  const _BadgeChip({required this.badge, required this.compact});

  @override
  Widget build(BuildContext context) {
    final isOwned = badge.owned;
    return Tooltip(
      message: badge.description,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: isOwned
              ? ProfileColors.gold.withValues(alpha: 0.1)
              : ProfileColors.panelSecondary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOwned ? ProfileColors.gold : ProfileColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: isOwned ? 1 : 0.35,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (badge.imagePath != null)
                    Image.asset(
                      badge.imagePath!,
                      width: compact ? 34 : 42,
                      height: compact ? 34 : 42,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.military_tech_rounded,
                        color: isOwned
                            ? ProfileColors.gold
                            : ProfileColors.textSecondary,
                        size: compact ? 20 : 24,
                      ),
                    )
                  else
                    Icon(
                      Icons.military_tech_rounded,
                      color: isOwned
                          ? ProfileColors.gold
                          : ProfileColors.textSecondary,
                      size: compact ? 20 : 24,
                    ),
                  if (!isOwned)
                    Icon(
                      Icons.lock_rounded,
                      color: ProfileColors.textSecondary,
                      size: compact ? 15 : 18,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            ChuGame(
              badge.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isOwned
                    ? ProfileColors.textPrimary
                    : ProfileColors.textSecondary.withValues(alpha: 0.65),
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 3 — VŨ KHÍ
// ═══════════════════════════════════════════════════════════════════

class _TabVuKhi extends StatefulWidget {
  final GoldRushGame game;
  final bool compact;

  const _TabVuKhi({required this.game, required this.compact});

  @override
  State<_TabVuKhi> createState() => _TabVuKhiState();
}

class _TabVuKhiState extends State<_TabVuKhi> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<VatPhamHienThi>>(
      valueListenable: widget.game.danhSachVatPham,
      builder: (context, items, _) {
        final weapons = items
            .where(
              (v) =>
                  v.loai == LoaiVatPham.vuKhi ||
                  v.loai == LoaiVatPham.giap ||
                  v.loai == LoaiVatPham.giay,
            )
            .toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.gavel_rounded,
                title: 'VŨ KHÍ & GIÁP',
              ),
              const SizedBox(height: 14),
              if (weapons.isEmpty)
                _EmptyState(
                  message: PhamViNgonNgu.of(context)
                      .dich('Bạn chưa sở hữu vũ khí nào.'),
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final w in weapons)
                      _WeaponTile(
                        item: w,
                        compact: widget.compact,
                        selected: w.id == _selectedId,
                        onTap: () => setState(() => _selectedId = w.id),
                      ),
                  ],
                ),
                if (_selectedId != null) ...[
                  const SizedBox(height: 16),
                  Builder(
                    builder: (_) {
                      final selected = weapons
                          .where((w) => w.id == _selectedId)
                          .firstOrNull;
                      if (selected == null) return const SizedBox.shrink();
                      return _WeaponDetail(
                        item: selected,
                        compact: widget.compact,
                        game: widget.game,
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WeaponTile extends StatefulWidget {
  final VatPhamHienThi item;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  const _WeaponTile({
    required this.item,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_WeaponTile> createState() => _WeaponTileState();
}

class _WeaponTileState extends State<_WeaponTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = _rarityColor(item.doHiem);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.compact ? 90 : 120,
          padding: EdgeInsets.all(widget.compact ? 8 : 10),
          decoration: BoxDecoration(
            color: widget.selected || _hovered
                ? ProfileColors.panelSecondary
                : ProfileColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected ? color : ProfileColors.border,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForVatPham(item),
                color: color,
                size: widget.compact ? 24 : 30,
              ),
              const SizedBox(height: 4),
              ChuGame(
                item.ten,
                style: TextStyle(
                  color: ProfileColors.textPrimary,
                  fontSize: widget.compact ? 10 : 11.5,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.oDangTrangBi != null) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: ProfileColors.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ChuGame(
                    'Đang dùng',
                    style: TextStyle(
                      color: ProfileColors.gold,
                      fontSize: widget.compact ? 8 : 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeaponDetail extends StatelessWidget {
  final VatPhamHienThi item;
  final bool compact;
  final GoldRushGame game;

  const _WeaponDetail({
    required this.item,
    required this.compact,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    final color = _rarityColor(item.doHiem);
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: ProfileColors.panelSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_iconForVatPham(item), color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: ChuGame(
                  item.ten,
                  style: TextStyle(
                    color: ProfileColors.textPrimary,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ChuGame(
                item.doHiem.name.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (item.moTa.isNotEmpty) ...[
            const SizedBox(height: 8),
            ChuGame(
              item.moTa,
              style: const TextStyle(
                color: ProfileColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (item.thuocTinh.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final e in item.thuocTinh.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ChuGame(
                      e.key,
                      style: const TextStyle(
                        color: ProfileColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    ChuGame(
                      e.value,
                      style: const TextStyle(
                        color: ProfileColors.goldHighlight,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (item.oDangTrangBi != null) ...[
            const SizedBox(height: 8),
            ChuGame(
              'Đang trang bị: ${_slotLabel(item.oDangTrangBi!)}',
              style: const TextStyle(
                color: ProfileColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (item.oDangTrangBi != null)
                TextButton(
                  onPressed: () => game.thaoVatPham(item.id),
                  child: const ChuGame(
                    'Tháo trang bị',
                    style: TextStyle(color: ProfileColors.textSecondary),
                  ),
                ),
              if (item.oDangTrangBi == null)
                TextButton(
                  onPressed: () => game.trangBiVatPham(item.id),
                  child: const ChuGame(
                    'Trang bị',
                    style: TextStyle(color: ProfileColors.crystalBlue),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => game.moKhoDo(),
                icon: const Icon(Icons.backpack_outlined, size: 15),
                label: const ChuGame('Kho đồ'),
                style: FilledButton.styleFrom(
                  backgroundColor: ProfileColors.gold,
                  foregroundColor: const Color(0xFF1A0A00),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 4 — NHÂN VẬT
// ═══════════════════════════════════════════════════════════════════

class _TabNhanVat extends StatelessWidget {
  final GoldRushGame game;
  final NhanVatBan nhanVat;
  final bool compact;

  const _TabNhanVat({
    required this.game,
    required this.nhanVat,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final owned = <NhanVatBan>[georgeGoc];
    // Check owned characters from PhienVi.daCo
    final pv = game.phienVi;
    if (pv != null) {
      for (final nv in bangNhanVat) {
        if (pv.daCo.contains(nv.id)) owned.add(nv);
      }
    }
    final dangDung = game.nhanVatDangDung;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(icon: Icons.groups_rounded, title: 'NHÂN VẬT'),
          const SizedBox(height: 6),
          ChuGame(
            'Nhân vật chỉ thay đổi ngoại hình, không ảnh hưởng sức mạnh.',
            style: TextStyle(
              color: ProfileColors.textSecondary,
              fontSize: compact ? 11 : 12,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final nv in owned)
                _CharacterCard(
                  nhanVat: nv,
                  isActive: nv.tepAnh == dangDung,
                  compact: compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final NhanVatBan nhanVat;
  final bool isActive;
  final bool compact;

  const _CharacterCard({
    required this.nhanVat,
    required this.isActive,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 100 : 130,
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: isActive
            ? ProfileColors.gold.withValues(alpha: 0.1)
            : ProfileColors.panelSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? ProfileColors.gold : ProfileColors.border,
          width: isActive ? 1.8 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 48 : 64,
            height: compact ? 48 : 64,
            decoration: BoxDecoration(
              color: ProfileColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? ProfileColors.gold : ProfileColors.border,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: AnhNhanVat(
                tepAnh: nhanVat.tepAnh,
                kichThuoc: compact ? 40 : 52,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ChuGame(
            nhanVat.ten,
            style: TextStyle(
              color: ProfileColors.textPrimary,
              fontSize: compact ? 11 : 12.5,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          if (isActive) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: ProfileColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const ChuGame(
                'ĐANG DÙNG',
                style: TextStyle(
                  color: ProfileColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionLink extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionLink> createState() => _ActionLinkState();
}

class _ActionLinkState extends State<_ActionLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? ProfileColors.panelSecondary
                : ProfileColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? ProfileColors.crystalBlue
                  : ProfileColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: ProfileColors.crystalBlue, size: 18),
              const SizedBox(width: 8),
              ChuGame(
                widget.label,
                style: TextStyle(
                  color: _hovered
                      ? ProfileColors.crystalBlue
                      : ProfileColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: ProfileColors.textSecondary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═══════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: ProfileColors.panelSecondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ProfileColors.border),
      ),
      child: ChuGame(
        message,
        style: const TextStyle(
          color: ProfileColors.textSecondary,
          fontSize: 12.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  BADGE CATALOG (read from SBT model, no fake data)
// ═══════════════════════════════════════════════════════════════════

/// Returns the 5 SBT achievement badges from the canonical catalog.
/// Ownership/eligibility status is chuaKiemTra because verifying ownership
/// requires an on-chain call per wallet, which is not done during UI build.
/// The Profile screen shows them as "Chưa mở khóa" until the SBT service
/// confirms ownership for the connected wallet.
List<ThanhTuuSBT> _allBadges() => [...bangThanhTuuSBT];

List<ThanhTuuSBT> _badgesFor(GoldRushGame game) {
  final unlocked = game.huyHieuSBTDaSoHuu.value;
  final displayed = unlocked.toList()..sort();
  final displayedIds = displayed.take(3).toSet();
  return [
    for (final badge in _allBadges())
      if (unlocked.contains(badge.achievementId))
        badge.copyWith(
          ownershipStatus: TrangThaiSoHuuSBT.daSoHuu,
          selectedForDisplay: displayedIds.contains(badge.achievementId),
        )
      else
        badge,
  ];
}
