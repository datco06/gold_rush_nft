import 'package:flutter/material.dart';

import '../gold_rush_game.dart';
import '../kho_do/danh_sach_nhan_vat.dart' show AnhNhanVat;
import '../ngon_ngu/ngon_ngu.dart';
import '../so_tay/danh_muc_so_tay.dart';
import '../so_tay/so_tay_kham_pha.dart';
import '../world_map/canh_quan_world_map.dart'
    show BoCucWorldMap, TaiNguyenWorldMap;

class ManHinhSoTayKhamPha extends StatefulWidget {
  const ManHinhSoTayKhamPha({super.key, required this.game});
  final GoldRushGame game;
  @override
  State<ManHinhSoTayKhamPha> createState() => _ManHinhSoTayKhamPhaState();
}

class _ManHinhSoTayKhamPhaState extends State<ManHinhSoTayKhamPha> {
  late Future<SoTayKhamPha> _soTay;
  NhomSoTay _nhom = NhomSoTay.diaDiem;
  static const _tenNhom = ['Địa điểm', 'Quái & Boss'];
  static const _goiY = [
    'Vào chơi màn để mở thông tin địa điểm.',
    'Gặp quái trong ván chơi để mở thông tin.',
  ];

  @override
  void initState() {
    super.initState();
    _soTay = widget.game.docSoTayKhamPha();
    widget.game.auth?.addListener(_taiLai);
  }

  void _taiLai() {
    if (mounted) {
      setState(() {
        _soTay = widget.game.docSoTayKhamPha();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ManHinhSoTayKhamPha oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.auth?.removeListener(_taiLai);
      widget.game.auth?.addListener(_taiLai);
      _soTay = widget.game.docSoTayKhamPha();
    }
  }

  @override
  void dispose() {
    widget.game.auth?.removeListener(_taiLai);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = danhMucSoTay(widget.game.danhSachMan)
        .where((m) => m.nhom == _nhom)
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFF081426),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13233A),
        foregroundColor: const Color(0xFFF5F7FA),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: PhamViNgonNgu.of(context).dich('Quay lại'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const ChuGame('Sổ tay khám phá'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final group in const [
                    NhomSoTay.diaDiem,
                    NhomSoTay.quai,
                  ])
                    ChoiceChip(
                      label: ChuGame(_tenNhom[group.index]),
                      selected: _nhom == group,
                      onSelected: (_) => setState(() {
                        _nhom = group;
                      }),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<SoTayKhamPha>(
                future: _soTay,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final daMo = snapshot.data?.daMo ?? const <String>{};
                  final soDaMo = catalog
                      .where((m) => daMo.contains(m.khoa))
                      .length;
                  return Column(
                    children: [
                      ChuGame(
                        'Đã khám phá $soDaMo/${catalog.length}',
                        style: const TextStyle(color: Color(0xFFF5B829)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: ChuGame(
                          _goiY[_nhom.index],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFAFC0D2),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: catalog.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final muc = catalog[index];
                            final mo = daMo.contains(muc.khoa);
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF13233A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF283A52),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _AnhSoTay(muc: muc, daMo: mo),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ChuGame(
                                          mo ? muc.ten : 'Chưa khám phá',
                                          style: const TextStyle(
                                            color: Color(0xFFF5F7FA),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (mo) ...[
                                          const SizedBox(height: 6),
                                          ChuGame(
                                            muc.moTa,
                                            style: const TextStyle(
                                              color: Color(0xFFAFC0D2),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnhSoTay extends StatelessWidget {
  const _AnhSoTay({required this.muc, required this.daMo});

  final MucSoTay muc;
  final bool daMo;
  static const _quai = {
    'quai:zombie': 'zombie.png',
    'quai:skeleton': 'skeleton.png',
    'quai:thuong': 'quai_thuong.png',
    'quai:giap': 'quai_giap.png',
    'quai:khong_lo': 'quai_khong_lo.png',
    // Boss dùng cùng sprite bộ xương như trong GoldRushGame.
    'quai:boss': 'skeleton.png',
  };

  @override
  Widget build(BuildContext context) {
    final sprite = _quai[muc.khoa];
    final id = muc.nhom == NhomSoTay.diaDiem
        ? int.tryParse(muc.khoa.split(':').last)
        : null;
    final congTrinh = BoCucWorldMap.congTrinh
        .where((c) => c.id == id)
        .firstOrNull;
    const anhLoi = Icon(Icons.broken_image_outlined, color: Color(0xFFAFC0D2));

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              key: ValueKey('so-tay-anh:${muc.khoa}'),
              opacity: daMo ? 1 : 0.28,
              child: sprite != null
                  ? AnhNhanVat(tepAnh: sprite, kichThuoc: 72)
                  : congTrinh != null
                  ? Image.asset(
                      '${TaiNguyenWorldMap.thuMuc}${congTrinh.anh}',
                      fit: BoxFit.contain,
                      cacheWidth: 216,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, _, _) => anhLoi,
                    )
                  : anhLoi,
            ),
            if (!daMo)
              const Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  Icons.lock_outline,
                  color: Color(0xFFAFC0D2),
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
