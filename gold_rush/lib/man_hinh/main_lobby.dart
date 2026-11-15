import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../blockchain/nhan_vat.dart';
import '../ai/may_chu_nhan_vat.dart';
import '../components/ui/gold_rush_top_bar.dart';
import '../gold_rush_game.dart';
import '../kho_do/danh_sach_nhan_vat.dart' show AnhNhanVat;
import '../kho_do/nhan_vat_voi_trang_bi.dart';
import '../kho_do/vat_pham_hien_thi.dart';
import 'ho_so_nhan_vat.dart';
import 'anh_nhan_vat.dart';

/// Bảng màu Fantasy Treasure Adventure / RPG Mining Cave cho Main Lobby.
abstract final class LobbyColors {
  static const background = Color(0xFF081426);
  static const panel = Color(0xFF142238);
  static const panelTranslucent = Color(0xD9142238);
  static const panelBorder = Color(0xFFE6A523);
  static const primaryGold = Color(0xFFFFBF32);
  static const highlightGold = Color(0xFFFFE27A);
  static const crystalBlue = Color(0xFF27C6FF);
  static const textPrimary = Color(0xFFF8F5EA);
  static const textSecondary = Color(0xFFB7C4D5);
}

/// Màn hình Main Lobby mới của Gold Rush v1.3 (tỷ lệ desktop 16:9, responsive).
class GoldRushMainLobby extends StatefulWidget {
  final GoldRushGame game;

  const GoldRushMainLobby({super.key, required this.game});

  @override
  State<GoldRushMainLobby> createState() => _GoldRushMainLobbyState();
}

class _GoldRushMainLobbyState extends State<GoldRushMainLobby>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _entranceController;
  String? _selectedSlotId;
  bool _startingAdventure = false;

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
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _isTestBinding ? 1.0 : 0.0,
    );
    if (!_isTestBinding) {
      _idleController.repeat(reverse: true);
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Listenable get _lobbyListenable {
    final g = widget.game;
    final items = <Listenable>[
      g.danhSachVatPham,
      g.tienTrinh,
      g.tienTrinhWorldMap,
      if (g.phienVi != null) g.phienVi!,
      if (g.auth != null) g.auth!,
    ];
    return Listenable.merge(items);
  }

  NhanVatBan _activeCharacterInfo() {
    final file = widget.game.nhanVatDangDung;
    if (file == georgeGoc.tepAnh) return georgeGoc;
    for (final nv in bangNhanVat) {
      if (nv.tepAnh == file) return nv;
    }
    return georgeGoc;
  }

  String _formatGold(BigInt? raw) {
    if (raw == null) return '0';
    final s = raw.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buf.write('.');
      }
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _onStartAdventure() async {
    if (_startingAdventure) return;
    setState(() => _startingAdventure = true);
    try {
      widget.game.moChonMan();
    } finally {
      if (mounted) {
        setState(() => _startingAdventure = false);
      }
    }
  }

  void _openProfileDialog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CharacterProfileScreen(game: widget.game),
      ),
    );
  }

  void _onSlotTap(_LobbyEquipSlot slot) {
    if (!slot.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: LobbyColors.panel,
          content: Text(
            'Ô ${slot.label} chưa được hỗ trợ trong phiên bản hiện tại.',
            style: const TextStyle(color: LobbyColors.textPrimary),
          ),
        ),
      );
      return;
    }

    setState(() => _selectedSlotId = slot.id);
    final item = slot.item;
    if (item == null) {
      widget.game.moKhoDo();
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: const Color(0x99040A14),
      builder: (_) => _ChiTietTrangBiDialog(
        slotLabel: slot.label,
        item: item,
        onOpenKhoDo: () {
          Navigator.of(context).pop();
          widget.game.moKhoDo();
        },
      ),
    );
  }

  Future<void> _openAiWorkshop() async {
    final api = MayChuNhanVat();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ManHinhAnhNhanVat(
            mayChu: api,
            authController: widget.game.auth,
            vi: widget.game.phienVi?.vi,
            tienTrinhController: widget.game.tienTrinh,
          ),
        ),
      );
    } finally {
      api.dong();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LobbyColors.background,
      child: ListenableBuilder(
        listenable: _lobbyListenable,
        builder: (context, _) {
          final g = widget.game;
          final nv = _activeCharacterInfo();
          final pv = g.phienVi;
          final goldText = pv == null
              ? '0'
              : (pv.dangXuLy ? '...' : _formatGold(pv.vang));

          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final compact = w < 900 || h < 540;
              final rightPanelWidth = compact
                  ? math.min(230.0, w * 0.42)
                  : math.min(286.0, math.max(230.0, w * 0.22));
              final horizontalPad = compact ? 14.0 : 28.0;
              final verticalPad = compact ? 12.0 : 20.0;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Hình nền hang động mỏ vàng + bục đá phát sáng
                  RepaintBoundary(
                    child: _LobbyBackground(
                      compact: compact,
                      rightPanelWidth: rightPanelWidth,
                    ),
                  ),

                  // 2. Nhân vật chính nổi bật ở trung tâm trên bục đá
                  _CharacterShowcase(
                    tepAnh: g.nhanVatDangDung,
                    tenNhanVat: nv.ten,
                    danhSachVatPham: g.danhSachVatPham.value,
                    idleAnimation: _idleController,
                    compact: compact,
                  ),

                  // 3. Giao diện Header + Panel Trang bị + Nút BẮT ĐẦU
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPad,
                        vertical: verticalPad,
                      ),
                      child: FadeTransition(
                        opacity: _entranceController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GoldRushTopBar(
                              activeItem: GoldRushTopBarItem.sanhCho,
                              gold: goldText,
                              playerName: g.auth?.user?.username ?? 'datco6',
                              onSanhCho: null,
                              onCuaHang: g.moCuaHang,
                              onKhoDo: g.moKhoDo,
                              onXuongAi: _openAiWorkshop,
                              onPlayerTap: _openProfileDialog,
                              onSettings: g.moCaiDat,
                              showClose: false,
                            ),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 30),
                                      child: SingleChildScrollView(
                                        physics: const ClampingScrollPhysics(),
                                        child: SizedBox(
                                          width: rightPanelWidth,
                                          child: _EquippedItemsPanel(
                                            compact: compact,
                                            items: g.danhSachVatPham.value,
                                            selectedSlotId: _selectedSlotId,
                                            onSlotTap: _onSlotTap,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: const Alignment(0, 0.88),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: compact ? 280 : 440,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _StartAdventureButton(
                                            compact: compact,
                                            loading: _startingAdventure,
                                            onPressed: _onStartAdventure,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Nhấn ENTER để bắt đầu ván mới',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFF7D90A0),
                                              fontSize: 10,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
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
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// 1. HÌNH NỀN HANG ĐỘNG MỎ VÀNG & BỤC ĐÁ PHÁT SÁNG
// ============================================================================

class _LobbyBackground extends StatelessWidget {
  final bool compact;
  final double rightPanelWidth;

  const _LobbyBackground({
    required this.compact,
    required this.rightPanelWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: LobbyColors.background),
        Image.asset(
          'assets/images/inventory_cave_bg_v1.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        // Lớp phủ ánh sáng chiều sâu + tinh thể xanh & đèn lồng vàng
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(compact ? 0.0 : -0.14, 0.08),
              radius: 0.95,
              colors: const [
                Color(0x1427C6FF),
                Color(0x4D081426),
                Color(0xCC060F1E),
              ],
              stops: const [0.0, 0.58, 1.0],
            ),
          ),
        ),
        // Bục đá phát sáng dưới chân nhân vật (căn chính giữa)
        const CustomPaint(painter: _PedestalPainter(centerShiftX: 0.0)),
      ],
    );
  }
}

class _PedestalPainter extends CustomPainter {
  final double centerShiftX;

  const _PedestalPainter({required this.centerShiftX});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5 + centerShiftX;
    final cy = size.height * 0.75 - 10.0;
    final rx = math.min(size.width * 0.20, 210.0);
    final ry = rx * 0.28;

    // Ánh sáng vàng chiếu lên từ bục đá
    final beamRect = Rect.fromCenter(
      center: Offset(cx, cy - ry * 2.2),
      width: rx * 1.4,
      height: ry * 5.0,
    );
    canvas.drawOval(
      beamRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            LobbyColors.primaryGold.withValues(alpha: 0.22),
            LobbyColors.crystalBlue.withValues(alpha: 0.07),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(beamRect),
    );

    // Đĩa đá tối màu nền
    final baseRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2.05,
      height: ry * 2.15,
    );
    canvas.drawOval(
      baseRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF283A52), Color(0xFF162438), Color(0xFF0A1422)],
        ).createShader(baseRect),
    );

    // Vòng phát sáng vàng ngoài
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 1.92,
        height: ry * 1.92,
      ),
      Paint()
        ..color = LobbyColors.panelBorder.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // Vòng sáng vàng trong
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 1.46,
        height: ry * 1.46,
      ),
      Paint()
        ..color = LobbyColors.highlightGold.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Tâm tinh thể xanh nhẹ
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: rx * 0.85,
        height: ry * 0.85,
      ),
      Paint()
        ..color = LobbyColors.crystalBlue.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PedestalPainter oldDelegate) =>
      oldDelegate.centerShiftX != centerShiftX;
}

// ============================================================================
// 2. HEADER PHÍA TRÊN (LOGO + THẺ GEORGE BÊN TRÁI | VÀNG + SHOP + CÀI ĐẶT PHẢI)
// ============================================================================

// Giữ lại để tương thích với các màn lobby cũ đang tham chiếu nội bộ.
// ignore: unused_element
class _LobbyHeader extends StatelessWidget {
  final bool compact;
  final String characterFile;
  final String characterName;
  final String playerTitle;
  final int level;
  final String goldText;
  final bool hasWallet;
  final VoidCallback onProfileTap;
  final VoidCallback? onGoldAddTap;
  final VoidCallback onShopTap;
  final VoidCallback onSettingsTap;

  const _LobbyHeader({
    required this.compact,
    required this.characterFile,
    required this.characterName,
    required this.playerTitle,
    required this.level,
    required this.goldText,
    required this.hasWallet,
    required this.onProfileTap,
    required this.onGoldAddTap,
    required this.onShopTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: compact ? 10 : 18,
            runSpacing: 8,
            children: [
              _GoldRushLogo(compact: compact),
              CharacterMiniProfile(
                compact: compact,
                characterFile: characterFile,
                characterName: characterName,
                playerTitle: playerTitle,
                level: level,
                onTap: onProfileTap,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GoldBalanceWidget(
              compact: compact,
              goldText: goldText,
              onAddTap: hasWallet ? onGoldAddTap : null,
            ),
            SizedBox(width: compact ? 8 : 10),
            _HeaderIconButton(
              tooltip: 'Cửa hàng nhân vật',
              size: compact ? 40 : 46,
              borderColor: LobbyColors.panelBorder,
              icon: Icons.storefront_rounded,
              iconColor: LobbyColors.highlightGold,
              onTap: onShopTap,
            ),
            SizedBox(width: compact ? 8 : 10),
            _HeaderIconButton(
              tooltip: 'Cài đặt & Đăng xuất',
              size: compact ? 40 : 46,
              borderColor: const Color(0xFF7992B1),
              icon: Icons.settings_rounded,
              iconColor: LobbyColors.textPrimary,
              onTap: onSettingsTap,
            ),
          ],
        ),
      ],
    );
  }
}

class _GoldRushLogo extends StatelessWidget {
  final bool compact;

  const _GoldRushLogo({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 38 : 46,
          height: compact ? 38 : 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3E2908), Color(0xFF1B150A)],
            ),
            border: Border.all(color: LobbyColors.panelBorder, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: LobbyColors.primaryGold.withValues(alpha: 0.35),
                blurRadius: 12,
              ),
            ],
          ),
          child: Icon(
            Icons.inventory_2_rounded,
            color: LobbyColors.highlightGold,
            size: compact ? 22 : 26,
          ),
        ),
        SizedBox(width: compact ? 8 : 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  LobbyColors.highlightGold,
                  LobbyColors.primaryGold,
                  Color(0xFFD18210),
                ],
              ).createShader(bounds),
              child: Text(
                'GOLD RUSH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 18 : 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1.0,
                  shadows: const [
                    Shadow(color: Color(0xAA000000), blurRadius: 6),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'AI ADVENTURE & BLOCKCHAIN',
              style: TextStyle(
                color: LobbyColors.textSecondary,
                fontSize: compact ? 8.5 : 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: compact ? 110 : 148,
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    LobbyColors.primaryGold,
                    LobbyColors.primaryGold.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Thẻ George nhỏ gọn nằm ngay bên phải logo GOLD RUSH (tái sử dụng ở Main Lobby & Hồ sơ).
class CharacterMiniProfile extends StatefulWidget {
  final bool compact;
  final String characterFile;
  final String characterName;
  final String playerTitle;
  final int level;
  final VoidCallback? onTap;
  final String? tooltip;

  const CharacterMiniProfile({
    super.key,
    required this.compact,
    required this.characterFile,
    required this.characterName,
    required this.playerTitle,
    required this.level,
    this.onTap,
    this.tooltip,
  });

  @override
  State<CharacterMiniProfile> createState() => _CharacterMiniProfileState();
}

class _CharacterMiniProfileState extends State<CharacterMiniProfile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final avatarSize = widget.compact ? 38.0 : 44.0;
    final interactive = widget.onTap != null;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8 : 11,
        vertical: widget.compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: LobbyColors.panelTranslucent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: interactive && _hovered
              ? LobbyColors.highlightGold
              : LobbyColors.panelBorder.withValues(alpha: 0.85),
          width: interactive && _hovered ? 1.8 : 1.3,
        ),
        boxShadow: [
          if (interactive && _hovered)
            BoxShadow(
              color: LobbyColors.primaryGold.withValues(alpha: 0.35),
              blurRadius: 14,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar pixel-art George hình vuông viền vàng nền xanh đen
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: LobbyColors.background,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: LobbyColors.panelBorder, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: AnhNhanVat(
                tepAnh: widget.characterFile,
                kichThuoc: avatarSize - 6,
              ),
            ),
          ),
          SizedBox(width: widget.compact ? 8 : 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.characterName,
                    style: TextStyle(
                      color: LobbyColors.textPrimary,
                      fontSize: widget.compact ? 12.5 : 14,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF422806),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: LobbyColors.primaryGold,
                        width: 0.9,
                      ),
                    ),
                    child: Text(
                      'Lv.${widget.level}',
                      style: const TextStyle(
                        color: LobbyColors.highlightGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.playerTitle,
                style: TextStyle(
                  color: LobbyColors.textSecondary,
                  fontSize: widget.compact ? 9.5 : 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (!widget.compact) ...[
            const SizedBox(width: 10),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF471217),
                border: Border.all(color: const Color(0xFFE0574E), width: 1.1),
              ),
              child: const Icon(
                Icons.military_tech_rounded,
                color: LobbyColors.highlightGold,
                size: 14,
              ),
            ),
          ],
        ],
      ),
    );
    if (!interactive) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip ?? 'Mở Hồ sơ nhân vật',
        child: GestureDetector(onTap: widget.onTap, child: card),
      ),
    );
  }
}

class _GoldBalanceWidget extends StatelessWidget {
  final bool compact;
  final String goldText;
  final VoidCallback? onAddTap;

  const _GoldBalanceWidget({
    required this.compact,
    required this.goldText,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 38 : 44,
      padding: EdgeInsets.only(
        left: compact ? 12 : 14,
        right: onAddTap != null ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: LobbyColors.panelTranslucent,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: LobbyColors.panelBorder, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: LobbyColors.primaryGold.withValues(alpha: 0.18),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            goldText,
            style: TextStyle(
              color: LobbyColors.textPrimary,
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Container(
            width: compact ? 22 : 26,
            height: compact ? 22 : 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [LobbyColors.highlightGold, LobbyColors.primaryGold],
              ),
            ),
            child: Icon(
              Icons.monetization_on_rounded,
              color: const Color(0xFF4A2B00),
              size: compact ? 16 : 19,
            ),
          ),
          if (onAddTap != null) ...[
            const SizedBox(width: 6),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Tooltip(
                message: 'Mở Cửa hàng',
                child: GestureDetector(
                  onTap: onAddTap,
                  child: Container(
                    width: compact ? 24 : 26,
                    height: compact ? 24 : 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF283A52),
                      border: Border.all(
                        color: LobbyColors.primaryGold.withValues(alpha: 0.7),
                      ),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: LobbyColors.highlightGold,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  final String tooltip;
  final double size;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.tooltip,
    required this.size,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: LobbyColors.panelTranslucent,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _hovered
                    ? LobbyColors.highlightGold
                    : widget.borderColor,
                width: _hovered ? 1.8 : 1.4,
              ),
              boxShadow: [
                if (_hovered)
                  BoxShadow(
                    color: widget.borderColor.withValues(alpha: 0.45),
                    blurRadius: 12,
                  ),
              ],
            ),
            child: Icon(
              widget.icon,
              color: widget.iconColor,
              size: widget.size * 0.54,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 3. NHÂN VẬT CHÍNH Ở TRUNG TÂM
// ============================================================================

class _CharacterShowcase extends StatelessWidget {
  final String tepAnh;
  final String tenNhanVat;
  final List<VatPhamHienThi> danhSachVatPham;
  final Animation<double> idleAnimation;
  final bool compact;

  const _CharacterShowcase({
    required this.tepAnh,
    required this.tenNhanVat,
    required this.danhSachVatPham,
    required this.idleAnimation,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final spriteSize = compact ? 132.0 : 184.0;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pedestalY = constraints.maxHeight * 0.65;
          final left = (constraints.maxWidth - spriteSize) * 0.5;
          final top = math.max(0.0, pedestalY - spriteSize + 8.0);
          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: spriteSize,
                height: spriteSize,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: idleAnimation,
                    builder: (context, child) {
                      final bob =
                          math.sin(idleAnimation.value * math.pi) * -6.0;
                      return Transform.translate(
                        offset: Offset(0, bob),
                        child: child,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: LobbyColors.primaryGold.withValues(
                              alpha: 0.18,
                            ),
                            blurRadius: 38,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: NhanVatVoiTrangBi(
                        tepAnh: tepAnh,
                        kichThuoc: spriteSize,
                        danhSachVatPham: danhSachVatPham,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// 4. PANEL TRANG BỊ HIỆN TẠI (BÊN PHẢI — LƯỚI 2×3)
// ============================================================================

class _LobbyEquipSlot {
  final String id;
  final String label;
  final bool supported;
  final VatPhamHienThi? item;
  final IconData fallbackIcon;

  const _LobbyEquipSlot({
    required this.id,
    required this.label,
    required this.supported,
    required this.item,
    required this.fallbackIcon,
  });
}

class _EquippedItemsPanel extends StatelessWidget {
  final bool compact;
  final List<VatPhamHienThi> items;
  final String? selectedSlotId;
  final ValueChanged<_LobbyEquipSlot> onSlotTap;

  const _EquippedItemsPanel({
    required this.compact,
    required this.items,
    required this.selectedSlotId,
    required this.onSlotTap,
  });

  VatPhamHienThi? _findEquipped(OTrangBi slot) {
    for (final vp in items) {
      if (vp.oDangTrangBi == slot) return vp;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final slots = <_LobbyEquipSlot>[
      _LobbyEquipSlot(
        id: 'main_weapon',
        label: 'Vũ khí chính',
        supported: true,
        item: _findEquipped(OTrangBi.vuKhiChinh),
        fallbackIcon: Icons.gavel_rounded,
      ),
      _LobbyEquipSlot(
        id: 'armor',
        label: 'Giáp',
        supported: true,
        item: _findEquipped(OTrangBi.giap),
        fallbackIcon: Icons.shield_outlined,
      ),
      _LobbyEquipSlot(
        id: 'off_weapon',
        label: 'Vũ khí phụ',
        supported: true,
        item: _findEquipped(OTrangBi.vuKhiPhu),
        fallbackIcon: Icons.gps_fixed_rounded,
      ),
      const _LobbyEquipSlot(
        id: 'acc_1',
        label: 'Phụ kiện 1',
        supported: false,
        item: null,
        fallbackIcon: Icons.circle_outlined,
      ),
      const _LobbyEquipSlot(
        id: 'acc_2',
        label: 'Phụ kiện 2',
        supported: false,
        item: null,
        fallbackIcon: Icons.auto_awesome_outlined,
      ),
      const _LobbyEquipSlot(
        id: 'companion',
        label: 'Đồng hành',
        supported: false,
        item: null,
        fallbackIcon: Icons.pets_rounded,
      ),
    ];

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: LobbyColors.panelTranslucent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LobbyColors.panelBorder, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: LobbyColors.primaryGold.withValues(alpha: 0.22),
            blurRadius: 18,
          ),
          const BoxShadow(
            color: Color(0x99000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.star_rounded,
                color: LobbyColors.highlightGold,
                size: 13,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'TRANG BỊ HIỆN TẠI',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: LobbyColors.highlightGold,
                    fontSize: compact ? 11.5 : 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.star_rounded,
                color: LobbyColors.highlightGold,
                size: 13,
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: compact ? 8 : 10,
              mainAxisSpacing: compact ? 8 : 10,
              childAspectRatio: 1.08,
            ),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot = slots[index];
              return _EquipmentSlotWidget(
                slot: slot,
                selected: slot.id == selectedSlotId,
                onTap: () => onSlotTap(slot),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EquipmentSlotWidget extends StatefulWidget {
  final _LobbyEquipSlot slot;
  final bool selected;
  final VoidCallback onTap;

  const _EquipmentSlotWidget({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_EquipmentSlotWidget> createState() => _EquipmentSlotWidgetState();
}

class _EquipmentSlotWidgetState extends State<_EquipmentSlotWidget> {
  bool _hovered = false;

  Color _rarityColor(DoHiemVatPham hiem) => switch (hiem) {
    DoHiemVatPham.thuong => const Color(0xFF8EA1B5),
    DoHiemVatPham.khongPhoBien => const Color(0xFF47D16C),
    DoHiemVatPham.hiem => LobbyColors.crystalBlue,
    DoHiemVatPham.suThi => const Color(0xFFC16BFF),
    DoHiemVatPham.huyenThoai => LobbyColors.primaryGold,
  };

  IconData _itemIcon(BieuTuongVatPham bt) => switch (bt) {
    BieuTuongVatPham.kiem => Icons.gavel_rounded,
    BieuTuongVatPham.cung => Icons.gps_fixed_rounded,
    BieuTuongVatPham.giap => Icons.shield_rounded,
    BieuTuongVatPham.binhHoiPhuc => Icons.local_drink_rounded,
    BieuTuongVatPham.macDinh => Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final item = widget.slot.item;
    final supported = widget.slot.supported;
    final borderColor = !supported
        ? const Color(0xFF283A52)
        : (widget.selected || _hovered
              ? LobbyColors.highlightGold
              : (item != null
                    ? _rarityColor(item.doHiem)
                    : const Color(0xFF445D7B)));

    final badgeValue = item != null && item.thuocTinh.isNotEmpty
        ? item.thuocTinh.values.first
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: item != null
            ? '${widget.slot.label}: ${item.ten}'
            : (supported
                  ? '${widget.slot.label} (Trống — bấm để mở Kho đồ)'
                  : '${widget.slot.label} (Chưa hỗ trợ)'),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: supported
                  ? const Color(0xCC0A182B)
                  : const Color(0x8807111F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: widget.selected || _hovered ? 2.0 : 1.4,
              ),
              boxShadow: [
                if (item != null)
                  BoxShadow(
                    color: _rarityColor(item.doHiem).withValues(alpha: 0.22),
                    blurRadius: 10,
                  ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item?.duongDanAnh != null)
                        HinhTrangBiFrame(
                          asset: item!.duongDanAnh!,
                          kichThuoc: 34,
                          fallback: Icon(
                            _itemIcon(item.bieuTuong),
                            color: _rarityColor(item.doHiem),
                            size: 28,
                          ),
                        )
                      else
                        Icon(
                          item != null
                              ? _itemIcon(item.bieuTuong)
                              : widget.slot.fallbackIcon,
                          color: item != null
                              ? _rarityColor(item.doHiem)
                              : (supported
                                    ? LobbyColors.textSecondary.withValues(
                                        alpha: 0.55,
                                      )
                                    : const Color(0xFF42546B)),
                          size: 26,
                        ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          item?.ten ??
                              (supported ? widget.slot.label : 'Chưa hỗ trợ'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: item != null
                                ? LobbyColors.textPrimary
                                : const Color(0xFF6B7F99),
                            fontSize: 9.5,
                            fontWeight: item != null
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeValue != null)
                  Positioned(
                    right: 5,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xD9071220),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _rarityColor(item!.doHiem)
                              .withValues(alpha: 0.7),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        badgeValue,
                        style: const TextStyle(
                          color: LobbyColors.highlightGold,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
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
}

// ============================================================================
// 5. NÚT BẮT ĐẦU — TRUNG TÂM PHÍA DƯỚI
// ============================================================================

class _StartAdventureButton extends StatefulWidget {
  final bool compact;
  final bool loading;
  final VoidCallback onPressed;

  const _StartAdventureButton({
    required this.compact,
    required this.loading,
    required this.onPressed,
  });

  @override
  State<_StartAdventureButton> createState() => _StartAdventureButtonState();
}

class _StartAdventureButtonState extends State<_StartAdventureButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled
            ? null
            : (_) {
                setState(() => _pressed = false);
                widget.onPressed();
              },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: widget.compact ? 58 : 70,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: disabled
                    ? const [Color(0xFF7D6530), Color(0xFF54421E)]
                    : const [
                        LobbyColors.highlightGold,
                        LobbyColors.primaryGold,
                        Color(0xFFC87D0A),
                      ],
              ),
              border: Border.all(
                color: _hovered ? Colors.white : LobbyColors.highlightGold,
                width: _hovered ? 2.2 : 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: LobbyColors.primaryGold.withValues(
                    alpha: _hovered ? 0.72 : 0.45,
                  ),
                  blurRadius: _hovered ? 24 : 16,
                  spreadRadius: _hovered ? 2 : 0,
                ),
                const BoxShadow(
                  color: Color(0xAA000000),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF281803),
                    ),
                  )
                else
                  CustomPaint(
                    size: Size.square(widget.compact ? 26 : 32),
                    painter: const _CrossedSwordsPainter(),
                  ),
                SizedBox(width: widget.compact ? 10 : 14),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.loading ? 'ĐANG MỞ...' : 'BẮT ĐẦU',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF231502),
                          fontSize: widget.compact ? 17 : 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '« Phiêu Lưu Ngay »',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF3E2605),
                          fontSize: widget.compact ? 10.5 : 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrossedSwordsPainter extends CustomPainter {
  const _CrossedSwordsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bladePaint = Paint()
      ..color = const Color(0xFF2A1903)
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round;
    final guardPaint = Paint()
      ..color = const Color(0xFF4A2B04)
      ..strokeWidth = w * 0.10
      ..strokeCap = StrokeCap.round;

    // Kiếm 1 (trái dưới -> phải trên)
    canvas.drawLine(
      Offset(w * 0.16, h * 0.84),
      Offset(w * 0.84, h * 0.16),
      bladePaint,
    );
    canvas.drawLine(
      Offset(w * 0.22, h * 0.62),
      Offset(w * 0.38, h * 0.78),
      guardPaint,
    );

    // Kiếm 2 (phải dưới -> trái trên)
    canvas.drawLine(
      Offset(w * 0.84, h * 0.84),
      Offset(w * 0.16, h * 0.16),
      bladePaint,
    );
    canvas.drawLine(
      Offset(w * 0.78, h * 0.62),
      Offset(w * 0.62, h * 0.78),
      guardPaint,
    );
  }

  @override
  bool shouldRepaint(_CrossedSwordsPainter oldDelegate) => false;
}

// ============================================================================
// 6. DIALOG CHI TIẾT TRANG BỊ & HỒ SƠ NHÂN VẬT (ĐIỀU HƯỚNG TỚI CÁC MÀN CŨ)
// ============================================================================

class _ChiTietTrangBiDialog extends StatelessWidget {
  final String slotLabel;
  final VatPhamHienThi item;
  final VoidCallback onOpenKhoDo;

  const _ChiTietTrangBiDialog({
    required this.slotLabel,
    required this.item,
    required this.onOpenKhoDo,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LobbyColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: LobbyColors.panelBorder, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                slotLabel.toUpperCase(),
                style: const TextStyle(
                  color: LobbyColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.ten,
                style: const TextStyle(
                  color: LobbyColors.highlightGold,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (item.moTa.isNotEmpty)
                Text(
                  item.moTa,
                  style: const TextStyle(
                    color: LobbyColors.textPrimary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              if (item.thuocTinh.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final e in item.thuocTinh.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(
                            color: LobbyColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          e.value,
                          style: const TextStyle(
                            color: LobbyColors.highlightGold,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Đóng',
                      style: TextStyle(color: LobbyColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onOpenKhoDo,
                    icon: const Icon(Icons.backpack_outlined, size: 17),
                    label: const Text('Mở Kho đồ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: LobbyColors.primaryGold,
                      foregroundColor: const Color(0xFF231502),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
