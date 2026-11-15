import 'package:flutter/material.dart';

import '../../ngon_ngu/ngon_ngu.dart';

/// Ngôn ngữ thiết kế dùng chung cho các control trong Kho đồ.
abstract final class GameInventoryStyle {
  static const gold = Color(0xFFE0A100);
  static const goldLight = Color(0xFFF5D06A);
  static const goldDark = Color(0xFF795000);
  static const navy = Color(0xFF07182A);
  static const panel = Color(0xFF0B223A);
  static const border = Color(0xFF31506B);
  static const borderHover = Color(0xFF8B7A48);
  static const textPrimary = Color(0xFFF5F1DE);
  static const textMuted = Color(0xFFB9C4D0);

  static const activeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8D6400), Color(0xFFF2C14E)],
  );

  static const inactiveGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A1E33), Color(0xFF061321)],
  );

  static List<BoxShadow> glow({double opacity = 0.42}) => [
    BoxShadow(
      color: gold.withValues(alpha: opacity),
      blurRadius: 16,
      spreadRadius: 1,
    ),
    const BoxShadow(
      color: Color(0x99000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  static InputDecoration searchDecoration({BuildContext? context, Widget? suffixIcon}) {
    OutlineInputBorder makeBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: (context == null ? NgonNgu.chung : PhamViNgonNgu.of(context)).dich('Tìm vật phẩm...'),
      hintStyle: const TextStyle(color: textMuted, fontSize: 14),
      prefixIcon: const Icon(Icons.search_rounded, color: textMuted, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: navy.withValues(alpha: 0.94),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: makeBorder(border),
      enabledBorder: makeBorder(border),
      focusedBorder: makeBorder(goldLight, 1.6),
      hoverColor: panel,
    );
  }
}

class GameTabButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const GameTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<GameTabButton> createState() => _GameTabButtonState();
}

class _GameTabButtonState extends State<GameTabButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final highlighted = selected || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: selected
                  ? GameInventoryStyle.activeGradient
                  : GameInventoryStyle.inactiveGradient,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected
                    ? GameInventoryStyle.goldLight
                    : highlighted
                    ? GameInventoryStyle.borderHover
                    : GameInventoryStyle.border,
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected
                  ? GameInventoryStyle.glow()
                  : _hovered
                  ? GameInventoryStyle.glow(opacity: 0.14)
                  : const [],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    size: 20,
                    color: selected
                        ? const Color(0xFFFFF1B5)
                        : GameInventoryStyle.textMuted,
                  ),
                  const SizedBox(width: 8),
                  ChuGame(
                    widget.label,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFFFFF1C7)
                          : GameInventoryStyle.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      shadows: selected
                          ? const [Shadow(color: Colors.black45, blurRadius: 3)]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameCloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const GameCloseButton({super.key, required this.onTap});

  @override
  State<GameCloseButton> createState() => _GameCloseButtonState();
}

class _GameCloseButtonState extends State<GameCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: PhamViNgonNgu.of(context).dich('Quay lại Menu'),
      child: Semantics(
        button: true,
        label: 'Quay lại Menu',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.94 : 1,
              duration: const Duration(milliseconds: 100),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _hovered
                      ? const LinearGradient(
                          colors: [Color(0xFF50390A), Color(0xFF0A192A)],
                        )
                      : GameInventoryStyle.inactiveGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _hovered
                        ? GameInventoryStyle.goldLight
                        : GameInventoryStyle.gold,
                    width: _hovered ? 2 : 1.4,
                  ),
                  boxShadow: _hovered
                      ? GameInventoryStyle.glow(opacity: 0.52)
                      : GameInventoryStyle.glow(opacity: 0.2),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFFFE9A6),
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameMenuButton<T> extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool active;
  final List<PopupMenuEntry<T?>> items;
  final ValueChanged<T?> onSelected;

  const GameMenuButton({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    required this.onSelected,
    this.active = false,
  });

  @override
  State<GameMenuButton<T>> createState() => _GameMenuButtonState<T>();
}

class _GameMenuButtonState<T> extends State<GameMenuButton<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<T?>(
        tooltip: widget.label,
        onSelected: widget.onSelected,
        color: GameInventoryStyle.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: GameInventoryStyle.gold),
        ),
        itemBuilder: (_) => widget.items,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            gradient: widget.active
                ? GameInventoryStyle.activeGradient
                : GameInventoryStyle.inactiveGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.active || _hovered
                  ? GameInventoryStyle.goldLight
                  : GameInventoryStyle.border,
              width: widget.active ? 1.6 : 1,
            ),
            boxShadow: widget.active
                ? GameInventoryStyle.glow(opacity: 0.3)
                : _hovered
                ? GameInventoryStyle.glow(opacity: 0.12)
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.active
                    ? const Color(0xFFFFF1B5)
                    : GameInventoryStyle.textMuted,
              ),
              const SizedBox(width: 7),
              ChuGame(
                widget.label,
                style: TextStyle(
                  color: widget.active
                      ? const Color(0xFFFFF1C7)
                      : GameInventoryStyle.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: GameInventoryStyle.textPrimary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GameToggleButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const GameToggleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<GameToggleButton> createState() => _GameToggleButtonState();
}

class _GameToggleButtonState extends State<GameToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            gradient: widget.selected
                ? GameInventoryStyle.activeGradient
                : GameInventoryStyle.inactiveGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected || _hovered
                  ? GameInventoryStyle.goldLight
                  : GameInventoryStyle.border,
              width: widget.selected ? 1.6 : 1,
            ),
            boxShadow: widget.selected
                ? GameInventoryStyle.glow(opacity: 0.34)
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selected ? Icons.check_circle_rounded : widget.icon,
                size: 18,
                color: widget.selected
                    ? const Color(0xFFFFF1B5)
                    : GameInventoryStyle.textMuted,
              ),
              const SizedBox(width: 7),
              ChuGame(
                widget.label,
                style: TextStyle(
                  color: widget.selected
                      ? const Color(0xFFFFF1C7)
                      : GameInventoryStyle.textPrimary,
                  fontSize: 14,
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

class GameSegmentButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const GameSegmentButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<GameSegmentButton> createState() => _GameSegmentButtonState();
}

class _GameSegmentButtonState extends State<GameSegmentButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              gradient: widget.selected
                  ? GameInventoryStyle.activeGradient
                  : GameInventoryStyle.inactiveGradient,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.selected || _hovered
                    ? GameInventoryStyle.goldLight
                    : GameInventoryStyle.border,
                width: widget.selected ? 1.7 : 1,
              ),
              boxShadow: widget.selected
                  ? GameInventoryStyle.glow(opacity: 0.38)
                  : _hovered
                  ? GameInventoryStyle.glow(opacity: 0.12)
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.selected
                      ? const Color(0xFF4A3100)
                      : GameInventoryStyle.textPrimary,
                ),
                const SizedBox(width: 7),
                ChuGame(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected
                        ? const Color(0xFF3F2A00)
                        : GameInventoryStyle.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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

class GameEquipmentSlot extends StatefulWidget {
  final Widget icon;
  final bool selected;

  const GameEquipmentSlot({
    super.key,
    required this.icon,
    this.selected = false,
  });

  @override
  State<GameEquipmentSlot> createState() => _GameEquipmentSlotState();
}

class _GameEquipmentSlotState extends State<GameEquipmentSlot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 62,
        height: 62,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: highlighted
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF68470B), Color(0xFF0A192A)],
                )
              : GameInventoryStyle.inactiveGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? GameInventoryStyle.goldLight
                : GameInventoryStyle.gold.withValues(alpha: 0.58),
            width: highlighted ? 2 : 1,
          ),
          boxShadow: highlighted
              ? GameInventoryStyle.glow(opacity: widget.selected ? 0.58 : 0.3)
              : const [],
        ),
        child: widget.icon,
      ),
    );
  }
}
