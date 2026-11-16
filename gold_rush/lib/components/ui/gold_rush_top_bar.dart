import 'package:flutter/material.dart';

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
          // Màn hình điện thoại ngang thường rộng 800–1000 px trong
          // browser/device preview. Giữ mọi thành phần trên một hàng rồi
          // thu nhỏ đồng bộ, tránh việc menu rơi xuống và làm mất ví.
          final compact = constraints.maxWidth < 1100;
          return Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
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
            child: compact ? _buildCompact(context) : _buildWide(context),
          );
        },
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _GoldRushBrand(),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _NavItems(
                  activeItem: activeItem,
                  onSanhCho: onSanhCho,
                  onCuaHang: onCuaHang,
                  onRungRuong: onRungRuong,
                  onQuaTang: onQuaTang,
                  onKhoDo: onKhoDo,
                  onXuongAi: onXuongAi,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: _StatusArea(
                gold: gold,
                playerName: playerName,
                walletAddress: walletAddress,
                onPlayerTap: onPlayerTap,
                onSettings: onSettings,
                onClose: onClose,
                showClose: showClose,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: 1040,
          child: Row(
            children: [
              const SizedBox(
                width: 150,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _GoldRushBrand(compact: true),
                ),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _NavItems(
                      dense: true,
                      activeItem: activeItem,
                      onSanhCho: onSanhCho,
                      onCuaHang: onCuaHang,
                      onRungRuong: onRungRuong,
                      onQuaTang: onQuaTang,
                      onKhoDo: onKhoDo,
                      onXuongAi: onXuongAi,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 270,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _StatusArea(
                      gold: gold,
                      playerName: playerName,
                      walletAddress: walletAddress,
                      onPlayerTap: onPlayerTap,
                      onSettings: onSettings,
                      onClose: onClose,
                      showClose: showClose,
                      compact: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
            color: Color(0xFF12202A),
          ),
        ),
        SizedBox(width: compact ? 7 : 10),
        Text(
          'GOLD RUSH',
          style: TextStyle(
            color: Color(0xFFEAF2F8),
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
    this.dense = false,
    required this.activeItem,
    required this.onSanhCho,
    required this.onCuaHang,
    required this.onRungRuong,
    required this.onQuaTang,
    required this.onKhoDo,
    required this.onXuongAi,
  });

  final bool dense;
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
          dense: dense,
          activeItem: activeItem,
          onTap: onSanhCho,
        ),
        _NavItem(
          item: GoldRushTopBarItem.cuaHang,
          label: 'Cửa hàng',
          icon: Icons.storefront_outlined,
          dense: dense,
          activeItem: activeItem,
          onTap: onCuaHang,
        ),
        _NavItem(
          item: GoldRushTopBarItem.rungRuong,
          label: 'Rung rương',
          icon: Icons.card_giftcard_outlined,
          dense: dense,
          activeItem: activeItem,
          onTap: onRungRuong,
        ),
        _NavItem(
          item: GoldRushTopBarItem.quaTang,
          label: 'Quà tặng',
          icon: Icons.redeem_outlined,
          dense: dense,
          activeItem: activeItem,
          onTap: onQuaTang,
        ),
        _NavItem(
          item: GoldRushTopBarItem.khoDo,
          label: 'Kho đồ',
          icon: Icons.inventory_2_outlined,
          dense: dense,
          activeItem: activeItem,
          onTap: onKhoDo,
        ),
        _NavItem(
          item: GoldRushTopBarItem.xuongAi,
          label: 'Xưởng AI',
          icon: Icons.auto_awesome_outlined,
          dense: dense,
          activeItem: activeItem,
          onTap: onXuongAi,
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
    this.dense = false,
  });

  final GoldRushTopBarItem item;
  final String label;
  final IconData icon;
  final GoldRushTopBarItem? activeItem;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final active = activeItem == item;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: dense ? 12 : 13),
        label: Text(label),
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
            horizontal: dense ? 8 : 11,
            vertical: dense ? 5 : 6,
          ),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(
            fontSize: dense ? 11 : 12,
            fontWeight: FontWeight.w500,
          ),
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
    final controls = <Widget>[
      _GoldChip(value: gold),
      _PlayerChip(name: playerName, address: walletAddress, onTap: onPlayerTap),
      _IconButton(icon: Icons.settings_outlined, onTap: onSettings),
      Visibility(
        visible: showClose,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: _IconButton(icon: Icons.close_rounded, onTap: onClose),
      ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: compact
          ? [
              _GoldChip(value: gold),
              const SizedBox(width: 4),
              _PlayerChip(
                name: playerName,
                address: walletAddress,
                onTap: onPlayerTap,
                compact: true,
              ),
              const SizedBox(width: 4),
              _IconButton(icon: Icons.settings_outlined, onTap: onSettings),
              Visibility(
                visible: showClose,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _IconButton(icon: Icons.close_rounded, onTap: onClose),
              ),
            ]
          : controls,
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
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFFFD67A),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
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
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: Color(0xFFEAF2F8),
                  fontSize: compact ? 9 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                address,
                style: TextStyle(
                  color: Color(0xFF7D90A0),
                  fontSize: compact ? 7 : 8,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          SizedBox(width: compact ? 5 : 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: compact ? 11 : 13,
            color: Color(0xFF7D90A0),
          ),
        ],
      ),
    ),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      color: const Color(0xFF9BB0C0),
      tooltip: icon == Icons.close_rounded ? 'Đóng' : 'Cài đặt',
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0x0FFFFFFF),
        side: const BorderSide(color: Color(0x1AFFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
