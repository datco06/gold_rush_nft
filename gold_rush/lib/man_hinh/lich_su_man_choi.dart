import 'package:flutter/material.dart';

import '../gold_rush_game.dart';
import '../lich_su/lich_su_man_choi.dart';
import '../ngon_ngu/ngon_ngu.dart';

class ManHinhLichSuManChoi extends StatefulWidget {
  const ManHinhLichSuManChoi({super.key, required this.game});
  final GoldRushGame game;

  @override
  State<ManHinhLichSuManChoi> createState() => _ManHinhLichSuManChoiState();
}

class _ManHinhLichSuManChoiState extends State<ManHinhLichSuManChoi> {
  late Future<List<VanDaChoi>> _lichSu;

  @override
  void initState() {
    super.initState();
    _lichSu = widget.game.docLichSuManChoi();
    widget.game.auth?.addListener(_taiLai);
  }

  void _taiLai() {
    if (!mounted) return;
    setState(() {
      _lichSu = widget.game.docLichSuManChoi();
    });
  }

  @override
  void didUpdateWidget(covariant ManHinhLichSuManChoi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.auth?.removeListener(_taiLai);
      widget.game.auth?.addListener(_taiLai);
      _lichSu = widget.game.docLichSuManChoi();
    }
  }

  @override
  void dispose() {
    widget.game.auth?.removeListener(_taiLai);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF081426),
    appBar: AppBar(
      backgroundColor: const Color(0xFF13233A),
      foregroundColor: const Color(0xFFF5F7FA),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: PhamViNgonNgu.of(context).dich('Quay lại'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const ChuGame('Lịch sử màn chơi'),
    ),
    body: SafeArea(
      child: FutureBuilder<List<VanDaChoi>>(
        future: _lichSu,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const <VanDaChoi>[];
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: ChuGame(
                  'Chưa có ván chơi hoàn thành.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFAFC0D2)),
                ),
              ),
            );
          }
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: ChuGame(
                  '100 ván gần nhất trên thiết bị này',
                  style: TextStyle(color: Color(0xFFAFC0D2), fontSize: 12),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _TheVanChoi(van: entries[index]),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _TheVanChoi extends StatelessWidget {
  const _TheVanChoi({required this.van});
  final VanDaChoi van;

  String _haiSo(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final giay = van.giay.floor();
    final thoiLuong = '${_haiSo(giay ~/ 60)}:${_haiSo(giay % 60)}';
    final local = van.ketThuc.toLocal();
    final ngay =
        '${_haiSo(local.day)}/${_haiSo(local.month)}/${local.year} '
        '${_haiSo(local.hour)}:${_haiSo(local.minute)}';
    final mauKetQua = van.thang
        ? const Color(0xFF7DE3AB)
        : const Color(0xFFFF9C92);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF13233A),
        border: Border.all(color: const Color(0xFF283A52)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ChuGame(
                  'Màn ${van.manId}',
                  style: const TextStyle(color: Color(0xFFF5B829)),
                ),
              ),
              Icon(
                van.thang ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 16,
                color: mauKetQua,
              ),
              const SizedBox(width: 6),
              ChuGame(
                van.thang ? 'Thắng' : 'Thua',
                style: TextStyle(color: mauKetQua, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ChuGame(
            van.tenMan,
            style: const TextStyle(
              color: Color(0xFFF5F7FA),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 20,
            runSpacing: 4,
            children: [
              ChuGame(
                'Thời lượng: $thoiLuong',
                style: const TextStyle(color: Color(0xFFAFC0D2), fontSize: 12),
              ),
              ChuGame(
                'Kết thúc: $ngay',
                style: const TextStyle(color: Color(0xFFAFC0D2), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
