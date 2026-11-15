import 'package:flutter/material.dart';

import '../blockchain/phien_vi.dart';
import '../blockchain/vi.dart';
import '../components/ui/gold_rush_top_bar.dart';
import '../gold_rush_game.dart';
import '../kho_do/danh_sach_trang_bi.dart';
import '../kho_do/vat_pham_hien_thi.dart';

/// Cửa hàng trang bị. Đây là một lớp phủ riêng của game nên không tạo
/// Navigator mới và không làm thay đổi các màn hình đang có.
class ManHinhCuaHang extends StatefulWidget {
  final GoldRushGame game;

  const ManHinhCuaHang({super.key, required this.game});

  @override
  State<ManHinhCuaHang> createState() => _ManHinhCuaHangState();
}

class _ManHinhCuaHangState extends State<ManHinhCuaHang> {
  final List<VatPhamHienThi> _danhMuc = danhSachTrangBiCuaHang();
  DanhMucVatPham _tab = DanhMucVatPham.vuKhi;
  DoHiemVatPham? _doHiem;
  String? _idDangChon;

  GoldRushGame get _game => widget.game;
  PhienVi? get _phienVi => _game.phienVi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _dongBoNFT());
  }

  List<VatPhamHienThi> get _vatPhamHienThi {
    return _danhMuc.where((item) {
      final dungTab = item.danhMucHienThi == _tab;
      final dungDoHiem = _doHiem == null || item.doHiem == _doHiem;
      return dungTab && dungDoHiem;
    }).toList();
  }

  VatPhamHienThi? get _vatPhamDangChon {
    final id = _idDangChon;
    if (id == null) return null;
    for (final item in _danhMuc) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pv = _phienVi;
    final listenable = pv == null
        ? _game.danhSachVatPham
        : Listenable.merge([pv, _game.danhSachVatPham]);

    return Material(
      color: const Color(0xFF060C12),
      child: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final selected = _vatPhamDangChon;
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
                return Stack(
                  children: [
                    const _StoreAtmosphere(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                      child: Column(
                        children: [
                          GoldRushTopBar(
                            activeItem: GoldRushTopBarItem.cuaHang,
                            gold: pv == null
                                ? '0'
                                : (pv.dangXuLy ? '...' : pv.vangDinhDang),
                            playerName: _game.auth?.user?.username ?? 'datco6',
                            onSanhCho: _game.veMenu,
                            onCuaHang: null,
                            onRungRuong: () {
                              _game.dongCuaHang();
                              _game.moRungRuong();
                            },
                            onQuaTang: () {
                              _game.dongCuaHang();
                              _game.moQuaTang();
                            },
                            onKhoDo: () {
                              _game.dongCuaHang();
                              _game.moKhoDo();
                            },
                            onXuongAi: null,
                            onPlayerTap: null,
                            onSettings: _game.moCaiDat,
                            onClose: _game.veMenu,
                          ),
                          const SizedBox(height: 12),
                          const _StoreHeading(),
                          const SizedBox(height: 12),
                          Expanded(
                            child: compact
                                ? _buildCompactContent(selected)
                                : _buildWideContent(selected),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideContent(VatPhamHienThi? selected) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildCatalog()),
        if (selected != null) ...[
          const SizedBox(width: 14),
          SizedBox(
            width: 344,
            child: _ItemDetail(
              item: selected,
              onBuy: () => _muaVatPham(selected),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactContent(VatPhamHienThi? selected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          _buildCatalog(),
          if (selected != null) ...[
            const SizedBox(height: 14),
            _ItemDetail(item: selected, onBuy: () => _muaVatPham(selected)),
          ],
        ],
      ),
    );
  }

  Widget _buildCatalog() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final items = _vatPhamHienThi;
        final width = constraints.maxWidth;
        final columns = ((width + 14) / 310).floor().clamp(1, 3).toInt();

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategoryTabs(
                selected: _tab,
                onSelected: (value) => setState(() {
                  _tab = value;
                  _idDangChon = null;
                }),
              ),
              const SizedBox(height: 12),
              _RarityFilters(
                selected: _doHiem,
                onSelected: (value) => setState(() => _doHiem = value),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const _EmptyStore()
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _StoreItemCard(
                      item: item,
                      price: _priceFor(item),
                      quantity: _quantityFor(item),
                      selected: item.id == _idDangChon,
                      onTap: () => setState(() => _idDangChon = item.id),
                      onBuy: () => _muaVatPham(item),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  int _quantityFor(VatPhamHienThi item) =>
      _game.danhSachVatPham.value
          .where((owned) => owned.id == item.id)
          .firstOrNull
          ?.soLuong ??
      0;

  int _priceFor(VatPhamHienThi item) => _priceForItem(item);

  int _tokenIdFor(VatPhamHienThi item) => _danhMuc.indexOf(item) + 1;

  Future<void> _dongBoNFT() async {
    final pv = _phienVi;
    final diaChi = pv?.diaChi;
    final cuaHang = pv?.cuaHang;
    if (pv == null || !pv.daKetNoi || diaChi == null || cuaHang == null) return;

    for (final item in _danhMuc) {
      try {
        final soLuong = await cuaHang.soLuongVatPham(diaChi, _tokenIdFor(item));
        if (soLuong > BigInt.zero && mounted) {
          _game.dongBoSoLuongVatPham(item, soLuong.toInt());
        }
      } on LoiVi {
        return;
      }
    }
  }

  Future<void> _muaVatPham(VatPhamHienThi item) async {
    final pv = _phienVi;
    if (pv == null) {
      _baoMua('Cần kết nối MetaMask để mua vật phẩm.');
      return;
    }
    if (!pv.daKetNoi) {
      final diaChi = _game.auth?.walletAddress;
      if (diaChi != null && diaChi.isNotEmpty) {
        await pv.ketNoiDaXacThuc(diaChi);
      }
    }
    if (!pv.daKetNoi) {
      _baoMua(pv.thongBao ?? 'Cần kết nối MetaMask để mua vật phẩm.');
      return;
    }

    final thanhCong = await pv.muaVatPham(
      tokenId: _tokenIdFor(item),
      ten: item.ten,
    );
    if (!thanhCong) {
      if (mounted && pv.thongBao != null && pv.thongBao!.isNotEmpty) {
        _baoMua(pv.thongBao!);
      }
      return;
    }
    if (!mounted) return;
    _game.themVatPhamVaoKho(item);
    _baoMua('Đã mua ${item.ten}; NFT đã được thêm vào Kho đồ.');
  }

  void _baoMua(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF142B38),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _StoreAtmosphere extends StatelessWidget {
  const _StoreAtmosphere();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -380,
            right: -180,
            width: 1200,
            height: 660,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x1FF2B33D), Color(0x00060C12)],
                ),
              ),
            ),
          ),
          Positioned(
            left: -260,
            bottom: -300,
            width: 900,
            height: 620,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x1A58A6FF), Color(0x00060C12)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreHeading extends StatelessWidget {
  const _StoreHeading();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Cửa hàng',
        style: TextStyle(
          color: Color(0xFFEAF2F8),
          fontSize: 34,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelected});

  final DanhMucVatPham selected;
  final ValueChanged<DanhMucVatPham> onSelected;

  @override
  Widget build(BuildContext context) {
    final tabs = <({DanhMucVatPham value, String label, IconData icon})>[
      (value: DanhMucVatPham.vuKhi, label: 'Súng', icon: Icons.gps_fixed),
      (value: DanhMucVatPham.giap, label: 'Giáp', icon: Icons.shield_outlined),
      (value: DanhMucVatPham.giay, label: 'Giày', icon: Icons.directions_run),
    ];

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF101921),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: _SegmentButton(
                label: tab.label,
                icon: tab.icon,
                selected: selected == tab.value,
                onTap: () => onSelected(tab.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFC84D) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? const Color(0xFF12202A)
                    : const Color(0xFF9BB0C0),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF12202A)
                      : const Color(0xFF9BB0C0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RarityFilters extends StatelessWidget {
  const _RarityFilters({required this.selected, required this.onSelected});

  final DoHiemVatPham? selected;
  final ValueChanged<DoHiemVatPham?> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = <(DoHiemVatPham?, String)>[
      (null, 'Tất cả'),
      (DoHiemVatPham.thuong, 'Thường'),
      (DoHiemVatPham.khongPhoBien, 'Mạnh'),
      (DoHiemVatPham.hiem, 'Hiếm'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final filter in filters)
          _FilterChip(
            label: filter.$2,
            selected: selected == filter.$1,
            onTap: () => onSelected(filter.$1),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x1FF2B33D) : const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0x66F2B33D)
                  : const Color(0x1AFFFFFF),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFFFD67A)
                  : const Color(0xFF9BB0C0),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreItemCard extends StatelessWidget {
  const _StoreItemCard({
    required this.item,
    required this.price,
    required this.quantity,
    required this.selected,
    required this.onTap,
    required this.onBuy,
  });

  final VatPhamHienThi item;
  final int price;
  final int quantity;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final rarity = mauDoHiem(item.doHiem);
    final isDefault = item.id == 'sung_cap_1';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF142B38), Color(0xFF0A1721)],
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? rarity : rarity.withValues(alpha: .65),
              width: selected ? 1.7 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: rarity.withValues(alpha: .18),
                      blurRadius: 16,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RarityTag(item.doHiem),
                  if (isDefault)
                    const Text(
                      'ĐANG DÙNG',
                      style: TextStyle(
                        color: Color(0xFF35D6A0),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    )
                  else if (quantity > 0)
                    _QuantityTag(quantity),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0x13000000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x12FFFFFF)),
                  ),
                  child: Center(child: _VatPhamImage(item, size: 96)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.ten,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFEAF2F8),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _shortStats(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF9BB0C0),
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(
                    Icons.monetization_on_outlined,
                    size: 14,
                    color: price == 0
                        ? const Color(0xFFFFD67A)
                        : const Color(0xFFF2B33D),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      price == 0 ? 'Miễn phí' : '$price vàng',
                      style: const TextStyle(
                        color: Color(0xFFFFD67A),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (price > 0)
                    _BuyButton(onPressed: onBuy)
                  else
                    _OwnedButton(label: isDefault ? 'Đã mặc' : 'Miễn phí'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.shopping_cart_outlined, size: 14),
      label: const Text('Mua'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFC84D),
        foregroundColor: const Color(0xFF12202A),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}

class _OwnedButton extends StatelessWidget {
  const _OwnedButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: null,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF7D90A0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(label),
    );
  }
}

class _QuantityTag extends StatelessWidget {
  const _QuantityTag(this.quantity);

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1435D6A0),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '×$quantity',
        style: const TextStyle(
          color: Color(0xFF35D6A0),
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RarityTag extends StatelessWidget {
  const _RarityTag(this.rarity);

  final DoHiemVatPham rarity;

  @override
  Widget build(BuildContext context) {
    final color = mauDoHiem(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        tenDoHiem(rarity).toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _VatPhamImage extends StatelessWidget {
  const _VatPhamImage(this.item, {required this.size});

  final VatPhamHienThi item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = item.duongDanAnh;
    if (asset == null || asset.isEmpty) {
      return Icon(
        Icons.inventory_2_outlined,
        color: mauDoHiem(item.doHiem),
        size: size * .42,
      );
    }

    // Toàn bộ ảnh trang bị trong catalog là sprite sheet 4x4. Chỉ lấy ô
    // đầu tiên (một mặt), không thu nhỏ cả bốn hướng vào cùng một thẻ.
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: 64,
        height: 64,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 256,
            maxWidth: 256,
            minHeight: 256,
            maxHeight: 256,
            child: Image.asset(
              asset,
              width: 256,
              height: 256,
              filterQuality: FilterQuality.none,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemDetail extends StatelessWidget {
  const _ItemDetail({required this.item, required this.onBuy});

  final VatPhamHienThi item;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final price = _priceForItem(item);
    final rarity = mauDoHiem(item.doHiem);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142B38), Color(0xFF0A1721)],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: rarity.withValues(alpha: .7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'THÔNG TIN VẬT PHẨM',
                style: TextStyle(
                  color: Color(0xFFF2B33D),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.7,
                ),
              ),
              _RarityTag(item.doHiem),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 132,
            decoration: BoxDecoration(
              color: const Color(0x13000000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            child: Center(child: _VatPhamImage(item, size: 118)),
          ),
          const SizedBox(height: 13),
          Text(
            item.ten,
            style: const TextStyle(
              color: Color(0xFFEAF2F8),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.moTa,
            style: const TextStyle(
              color: Color(0xFF9BB0C0),
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 13),
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          const SizedBox(height: 10),
          for (final entry in item.thuocTinh.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  const Icon(
                    Icons.bolt_outlined,
                    size: 14,
                    color: Color(0xFFF2B33D),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        color: Color(0xFF9BB0C0),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    entry.value,
                    style: const TextStyle(
                      color: Color(0xFF35D6A0),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.monetization_on_outlined,
                color: Color(0xFFF2B33D),
                size: 16,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  price == 0 ? 'Miễn phí' : '$price vàng',
                  style: const TextStyle(
                    color: Color(0xFFFFD67A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: price == 0 ? null : onBuy,
                icon: const Icon(Icons.shopping_cart_outlined, size: 15),
                label: const Text('Mua'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC84D),
                  foregroundColor: const Color(0xFF12202A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

int _priceForItem(VatPhamHienThi item) {
  if (item.doHiem == DoHiemVatPham.hiem) return 100000;
  return 1;
}

String _shortStats(VatPhamHienThi item) {
  if (item.loai == LoaiVatPham.vuKhi) {
    return '${item.satThuong} HP  ·  ${item.tamBan.toInt()} ô  ·  cơ bản';
  }
  if (item.loai == LoaiVatPham.giap) {
    return '+${item.hpCongThem} HP  ·  giảm ${(item.giamSatThuong * 100).round()}%';
  }
  return '+${(item.tocDoCongThem * 100).round()}% tốc độ chạy';
}

class _EmptyStore extends StatelessWidget {
  const _EmptyStore();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: const Text(
        'Chưa có vật phẩm trong danh mục này.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF9BB0C0)),
      ),
    );
  }
}

String tenDoHiem(DoHiemVatPham doHiem) {
  switch (doHiem) {
    case DoHiemVatPham.thuong:
      return 'Thường';
    case DoHiemVatPham.khongPhoBien:
      return 'Mạnh';
    case DoHiemVatPham.hiem:
      return 'Hiếm';
    case DoHiemVatPham.suThi:
      return 'Sử thi';
    case DoHiemVatPham.huyenThoai:
      return 'Huyền thoại';
  }
}

Color mauDoHiem(DoHiemVatPham doHiem) {
  switch (doHiem) {
    case DoHiemVatPham.thuong:
      return const Color(0xFFAAB5C0);
    case DoHiemVatPham.khongPhoBien:
      return const Color(0xFF43D98B);
    case DoHiemVatPham.hiem:
      return const Color(0xFF36BFFF);
    case DoHiemVatPham.suThi:
      return const Color(0xFFA765FF);
    case DoHiemVatPham.huyenThoai:
      return const Color(0xFFF5B829);
  }
}
