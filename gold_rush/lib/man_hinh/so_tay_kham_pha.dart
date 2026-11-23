import 'package:flutter/material.dart';

import '../gold_rush_game.dart';
import '../ngon_ngu/ngon_ngu.dart';
import '../so_tay/danh_muc_so_tay.dart';
import '../so_tay/so_tay_kham_pha.dart';

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
                                  Icon(
                                    mo
                                        ? Icons.menu_book_rounded
                                        : Icons.lock_outline,
                                    color: mo
                                        ? const Color(0xFFF5B829)
                                        : const Color(0xFFAFC0D2),
                                    size: 22,
                                  ),
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
