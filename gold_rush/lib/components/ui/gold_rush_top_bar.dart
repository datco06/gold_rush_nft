import 'package:flutter/material.dart';

import '../../ngon_ngu/ngon_ngu.dart';

/// Các mục điều hướng dùng chung trên TopBar Gold Rush.
enum GoldRushTopBarItem { sanhCho, cuaHang, rungRuong, quaTang, khoDo, xuongAi }

/// TopBar dùng chung cho các màn hình ngoài gameplay.
///
/// Widget này không tự điều hướng và không phụ thuộc vào Flame/Auth. Mỗi màn
/// hình truyền callback tương ứng, vì vậy có thể tái sử dụng ở lobby, cửa
/// hàng, kho đồ, hồ sơ và xưởng AI mà không tạo thêm Navigator riêng.
class GoldRushTopBar extends StatelessWidget {
  const GoldRushTopBar({
    super.key,
    this.activeItem,
    this.onSanhCho,
    this.onCuaHang,
    this.onRungRuong,
    this.onQuaTang,
    this.onKhoDo,
    this.onXuongAi,
    this.gold = '0',
    this.playerName = 'datco6',
    this.walletAddress = '0x7597…311F',
    this.onPlayerTap,
    this.onSettings,
    this.onClose,
    this.showClose = true,
  });

  final GoldRushTopBarItem? activeItem;
  final VoidCallback? onSanhCho;
  final VoidCallback? onCuaHang;
  final VoidCallback? onRungRuong;
  final VoidCallback? onQuaTang;
  final VoidCallback? onKhoDo;
  final VoidCallback? onXuongAi;
  final String gold;
  final String playerName;
  final String walletAddress;
  final VoidCallback? onPlayerTap;
  final VoidCallback? onSettings;
  final VoidCallback? onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final tight = constraints.maxWidth < 1200;
          return Container(
            constraints: BoxConstraints(minHeight: compact ? 56 : 64),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF142B38), Color(0xFF0A1721)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x1AFFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 16,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: _buildContent(compact, tight),
          );
        },
      ),
    );
  }

  Widget _buildContent(bool compact, bool tight) {
    final brand = _GoldRushBrand(compact: tight);
    final navigation = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _NavItems(
        compact: tight,
        activeItem: activeItem,
        onSanhCho: onSanhCho,
        onCuaHang: onCuaHang,
        onRungRuong: onRungRuong,
        onQuaTang: onQuaTang,
        onKhoDo: onKhoDo,
        onXuongAi: onXuongAi,
      ),
    );
    final status = _StatusArea(
      gold: gold,
      playerName: playerName,
      walletAddress: walletAddress,
      onPlayerTap: onPlayerTap,
      onSettings: onSettings,
      onClose: onClose,
      showClose: showClose,
      compact: tight,
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [brand, status],
          ),
          navigation,
        ],
      );
    }

    return Row(
      children: [
        brand,
        SizedBox(width: tight ? 6 : 12),
        Expanded(
          child: Align(alignment: Alignment.center, child: navigation),
        ),
        SizedBox(width: tight ? 6 : 12),
        status,
      ],
    );
  }
}

class _GoldRushBrand extends StatelessWidget {
  const _GoldRushBrand({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 28 : 32,
          height: compact ? 28 : 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFFFFD67A), Color(0xFFE8A62C)],
            ),
            borderRadius: BorderRadius.circular(9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33F2B33D),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            Icons.monetization_on_rounded,
            size: compact ? 15 : 17,
            color: const Color(0xFF12202A),
          ),
        ),
        SizedBox(width: compact ? 7 : 10),
        ChuGame(
          'GOLD RUSH',
          style: TextStyle(
            color: const Color(0xFFEAF2F8),
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
          ),
        ),
      ],
    );
  }
}

class _NavItems extends StatelessWidget {
  const _NavItems({
    required this.compact,
    required this.activeItem,
    required this.onSanhCho,
    required this.onCuaHang,
    required this.onRungRuong,
    required this.onQuaTang,
    required this.onKhoDo,
    required this.onXuongAi,
  });

  final bool compact;
  final GoldRushTopBarItem? activeItem;
  final VoidCallback? onSanhCho;
  final VoidCallback? onCuaHang;
  final VoidCallback? onRungRuong;
  final VoidCallback? onQuaTang;
  final VoidCallback? onKhoDo;
  final VoidCallback? onXuongAi;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavItem(
          item: GoldRushTopBarItem.sanhCho,
          label: 'Sảnh chờ',
          icon: Icons.explore_outlined,
          activeItem: activeItem,
          compact: compact,
          onTap: onSanhCho,
        ),
        _NavItem(
          item: GoldRushTopBarItem.cuaHang,
          label: 'Cửa hàng',
          icon: Icons.storefront_outlined,
          activeItem: activeItem,
          compact: compact,
          onTap: onCuaHang,
        ),
        _NavItem(
          item: GoldRushTopBarItem.rungRuong,
          label: 'Rung rương',
          icon: Icons.card_giftcard_outlined,
          activeItem: activeItem,
          compact: compact,
          onTap: onRungRuong,
        ),
        _NavItem(
          item: GoldRushTopBarItem.quaTang,
          label: 'Quà tặng',
          icon: Icons.redeem_outlined,
          activeItem: activeItem,
          compact: compact,
          onTap: onQuaTang,
        ),
        _NavItem(
          item: GoldRushTopBarItem.khoDo,
          label: 'Kho đồ',
          icon: Icons.inventory_2_outlined,
          activeItem: activeItem,
          compact: compact,
          onTap: onKhoDo,
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.label,
    required this.icon,
    required this.activeItem,
    required this.onTap,
    required this.compact,
  });

  final GoldRushTopBarItem item;
  final String label;
  final IconData icon;
  final GoldRushTopBarItem? activeItem;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = activeItem == item;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: compact ? 12 : 14),
        label: ChuGame(label),
        style: TextButton.styleFrom(
          foregroundColor: active
              ? const Color(0xFFFFD67A)
              : const Color(0xFF9BB0C0),
          backgroundColor: active
              ? const Color(0x1FF2B33D)
              : Colors.transparent,
          side: active
              ? const BorderSide(color: Color(0x4DF2B33D))
              : BorderSide.none,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 10,
            vertical: 5,
          ),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _StatusArea extends StatelessWidget {
  const _StatusArea({
    required this.gold,
    required this.playerName,
    required this.walletAddress,
    required this.onPlayerTap,
    required this.onSettings,
    required this.onClose,
    required this.showClose,
    this.compact = false,
  });

  final String gold;
  final String playerName;
  final String walletAddress;
  final VoidCallback? onPlayerTap;
  final VoidCallback? onSettings;
  final VoidCallback? onClose;
  final bool showClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 2 : 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _GoldChip(value: gold),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 112 : 152),
          child: _PlayerChip(
            name: playerName,
            address: walletAddress,
            onTap: onPlayerTap,
            compact: compact,
          ),
        ),
        _IconButton(
          icon: Icons.settings_outlined,
          onTap: onSettings,
          compact: compact,
        ),
        if (showClose)
          _IconButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            compact: compact,
          ),
      ],
    );
  }
}

class _GoldChip extends StatelessWidget {
  const _GoldChip({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x1FF2B33D),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x40F2B33D)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.monetization_on_outlined,
          size: 13,
          color: Color(0xFFF2B33D),
        ),
        const SizedBox(width: 6),
        ChuGame(
          value,
          style: const TextStyle(
            color: Color(0xFFFFD67A),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.name,
    required this.address,
    required this.onTap,
    this.compact = false,
  });

  final String name;
  final String address;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 3 : 4,
        compact ? 3 : 4,
        compact ? 7 : 10,
        compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 22 : 26,
            height: compact ? 22 : 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF3FD9A4), Color(0xFF2F8FD6)],
              ),
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChuGame(
                  name,
                  dichNoiDung: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEAF2F8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ChuGame(
                  address,
                  dichNoiDung: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7D90A0),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: compact ? 11 : 13,
            color: const Color(0xFF7D90A0),
          ),
        ],
      ),
    ),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.compact,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      color: const Color(0xFF9BB0C0),
      tooltip: PhamViNgonNgu.of(context)
          .dich(icon == Icons.close_rounded ? 'Đóng' : 'Cài đặt'),
      constraints: BoxConstraints.tightFor(
        width: compact ? 34 : 44,
        height: compact ? 34 : 44,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0x0FFFFFFF),
        side: const BorderSide(color: Color(0x1AFFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
