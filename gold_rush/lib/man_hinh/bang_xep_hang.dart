import 'package:flutter/material.dart';

import '../bang_xep_hang/bang_xep_hang.dart';
import '../gold_rush_game.dart';
import '../ngon_ngu/ngon_ngu.dart';

class ManHinhBangXepHang extends StatefulWidget {
  const ManHinhBangXepHang({super.key, required this.game, this.mayChu});
  final GoldRushGame game;
  final MayChuBangXepHang? mayChu;

  @override
  State<ManHinhBangXepHang> createState() => _ManHinhBangXepHangState();
}

class _ManHinhBangXepHangState extends State<ManHinhBangXepHang> {
  late MayChuBangXepHang _mayChu;
  Future<BangXepHangTuan>? _bang;
  String? _chu;
  int? _man;
  bool _thichUng = false;

  String? get _chuHienTai {
    final auth = widget.game.auth;
    if (auth == null ||
        !auth.canEnterGame ||
        auth.walletAddress == null ||
        auth.chainId == null) {
      return null;
    }
    return '${auth.walletAddress!.toLowerCase()}:${auth.chainId}';
  }

  @override
  void initState() {
    super.initState();
    _mayChu = widget.mayChu ?? MayChuBangXepHang();
    widget.game.auth?.addListener(_doiPhien);
    _chu = _chuHienTai;
    _tai();
  }

  void _tai() {
    _bang = _chu == null ? null : _mayChu.tai(man: _man, thichUng: _thichUng);
  }

  void _doiPhien() {
    if (!mounted || _chu == _chuHienTai) return;
    setState(() {
      _chu = _chuHienTai;
      _tai();
    });
  }

  @override
  void didUpdateWidget(covariant ManHinhBangXepHang oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game || oldWidget.mayChu != widget.mayChu) {
      oldWidget.game.auth?.removeListener(_doiPhien);
      if (oldWidget.mayChu == null) _mayChu.dong();
      _mayChu = widget.mayChu ?? MayChuBangXepHang();
      widget.game.auth?.addListener(_doiPhien);
      _chu = _chuHienTai;
      _man = null;
      _tai();
    }
  }

  @override
  void dispose() {
    widget.game.auth?.removeListener(_doiPhien);
    if (widget.mayChu == null) _mayChu.dong();
    super.dispose();
  }

  Widget _thongBao(String text, {bool thuLai = false}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChuGame(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFAFC0D2)),
          ),
          if (thuLai) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(_tai),
              child: const ChuGame('Thử lại'),
            ),
          ],
        ],
      ),
    ),
  );

  String _ngay(DateTime utc) {
    final date = utc.toUtc().add(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF081426),
    appBar: AppBar(
      backgroundColor: const Color(0xFF13233A),
      foregroundColor: const Color(0xFFF5F7FA),
      title: const ChuGame('Bảng xếp hạng tuần'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: PhamViNgonNgu.of(context).dich('Quay lại'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: PhamViNgonNgu.of(context).dich('Làm mới'),
          onPressed: _chu == null ? null : () => setState(_tai),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    key: const ValueKey('bxh-stage'),
                    value: _man ?? 0,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF13233A),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: ChuGame('Tổng hợp'),
                      ),
                      for (final stage in widget.game.danhSachMan.where(
                        (s) => s.id >= 1 && s.id <= 20,
                      ))
                        DropdownMenuItem(
                          value: stage.id,
                          child: ChuGame('Màn ${stage.id}'),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _man = value == 0 ? null : value;
                      _tai();
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<bool>(
                    key: const ValueKey('bxh-mode'),
                    value: _thichUng,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF13233A),
                    items: const [
                      DropdownMenuItem(
                        value: false,
                        child: ChuGame('Tiêu chuẩn'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: ChuGame('Độ khó thích ứng'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _thichUng = value ?? false;
                      _tai();
                    }),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _chu == null
                ? _thongBao('Đăng nhập để xem bảng xếp hạng.')
                : FutureBuilder<BangXepHangTuan>(
                    future: _bang,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        final error = snapshot.error;
                        final kind = error is LoiTaiBangXepHang
                            ? error.loai
                            : LoiBangXepHang.mayChu;
                        final message = switch (kind) {
                          LoiBangXepHang.dangNhap =>
                            'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
                          LoiBangXepHang.ketNoi => 'Không tải được bảng xếp hạng. Kiểm tra kết nối và thử lại.',
                          LoiBangXepHang.duLieu =>
                            'Dữ liệu bảng xếp hạng không hợp lệ.',
                          LoiBangXepHang.mayChu =>
                            'Bảng xếp hạng tạm thời chưa sẵn sàng.',
                        };
                        return _thongBao(message, thuLai: true);
                      }
                      final data = snapshot.data!;
                      if (data.viewer !=
                          widget.game.auth?.walletAddress?.toLowerCase()) {
                        return _thongBao(
                          'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
                          thuLai: true,
                        );
                      }
                      if (BigInt.from(data.chainId) !=
                          widget.game.auth?.chainId) {
                        return _thongBao(
                          'Bảng xếp hạng chưa hỗ trợ mạng ví hiện tại.',
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          ChuGame(
                            'Tuần từ ${_ngay(data.batDau)}',
                            style: const TextStyle(color: Color(0xFFF5B829)),
                          ),
                          ChuGame(
                            'Kết thúc: ${_ngay(data.ketThuc)} (giờ Việt Nam)',
                            style: const TextStyle(
                              color: Color(0xFFAFC0D2),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const ChuGame(
                            'Chỉ tính ván thắng đã xác minh; mỗi màn lấy thành tích tốt nhất.',
                            style: TextStyle(
                              color: Color(0xFFAFC0D2),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const ChuGame(
                            'Hạng của bạn',
                            style: TextStyle(
                              color: Color(0xFFF5B829),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (data.ban case final mine?)
                            _DongHang(row: mine)
                          else
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: ChuGame(
                                'Bạn chưa có hạng trong tuần này.',
                                style: TextStyle(color: Color(0xFFAFC0D2)),
                              ),
                            ),
                          const SizedBox(height: 12),
                          ChuGame(
                            'Top ${data.bang.length} · ${data.tongNguoi} người chơi',
                            style: const TextStyle(color: Color(0xFFF5B829)),
                          ),
                          if (data.bang.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: ChuGame(
                                'Chưa có thành tích được xác minh trong tuần này.',
                                style: TextStyle(color: Color(0xFFAFC0D2)),
                              ),
                            ),
                          for (final row in data.bang) _DongHang(row: row),
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

class _DongHang extends StatelessWidget {
  const _DongHang({required this.row});
  final DongXepHang row;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF13233A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: row.laBan ? const Color(0xFFF5B829) : const Color(0xFF283A52),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChuGame(
              'Hạng ${row.hang}',
              style: const TextStyle(color: Color(0xFFF5B829)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                row.ten,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF5F7FA),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ChuGame(
          '${row.diem} điểm · ${row.giay.toStringAsFixed(3)} giây · ${row.soMan} màn',
          style: const TextStyle(color: Color(0xFFAFC0D2), fontSize: 12),
        ),
      ],
    ),
  );
}
