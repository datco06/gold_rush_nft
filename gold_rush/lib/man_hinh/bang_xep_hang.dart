import 'dart:async';

import 'package:flutter/material.dart';

import '../bang_xep_hang/bang_xep_hang.dart';
import '../bang_xep_hang/tong_the.dart';
import '../blockchain/sbt/sbt_model.dart';
import '../gold_rush_game.dart';
import '../ngon_ngu/ngon_ngu.dart';

class ManHinhBangXepHang extends StatefulWidget {
  const ManHinhBangXepHang({super.key, required this.game, this.mayChu});
  final GoldRushGame game;
  final MayChuBangXepHang? mayChu;
  @override
  State<ManHinhBangXepHang> createState() => _ManHinhBangXepHangState();
}

class _ManHinhBangXepHangState extends State<ManHinhBangXepHang>
    with WidgetsBindingObserver {
  late MayChuBangXepHang _mayChu;
  BangTongThe? _data;
  String? _chu;
  String? _message;
  bool _loading = false;
  bool _active = true;
  bool _invalidSession = false;
  int _sequence = 0;
  Timer? _timer;
  ModalRoute<dynamic>? _route;

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
    _mayChu =
        widget.mayChu ??
        MayChuBangXepHang(thoiGianCho: const Duration(seconds: 30));
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.game.auth?.addListener(_doiPhien);
    _chu = _chuHienTai;
    unawaited(_tai());
    _datHen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _datHen() {
    _timer?.cancel();
    if (_chu == null || !_active || _invalidSession) return;
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_route?.isCurrent != false) unawaited(_tai());
    });
  }

  Future<void> _tai() async {
    if (_chu == null || _loading || !mounted) return;
    final sequence = ++_sequence;
    final identity = _chu;
    setState(() {
      _loading = true;
    });
    try {
      final value = await _mayChu.taiTongThe(phien: identity);
      if (!mounted || sequence != _sequence || identity != _chuHienTai) return;
      if (value.viewer != widget.game.auth?.walletAddress?.toLowerCase()) {
        throw const LoiTaiBangXepHang(LoiBangXepHang.dangNhap);
      }
      if (BigInt.from(value.chainId) != widget.game.auth?.chainId) {
        setState(() {
          _data = null;
          _loading = false;
          _message = 'Bảng xếp hạng chưa hỗ trợ mạng ví hiện tại.';
        });
        _timer?.cancel();
        return;
      }
      setState(() {
        _data = value;
        _loading = false;
        _message = null;
        _invalidSession = false;
      });
      _datHen();
    } catch (error) {
      if (!mounted || sequence != _sequence || identity != _chuHienTai) return;
      final kind = error is LoiTaiBangXepHang
          ? error.loai
          : LoiBangXepHang.mayChu;
      setState(() {
        _loading = false;
        _message = switch (kind) {
          LoiBangXepHang.dangNhap =>
            'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.',
          LoiBangXepHang.ketNoi =>
            'Không tải được bảng xếp hạng. Kiểm tra kết nối và thử lại.',
          LoiBangXepHang.duLieu => 'Dữ liệu bảng xếp hạng không hợp lệ.',
          LoiBangXepHang.mayChu => 'Bảng xếp hạng tạm thời chưa sẵn sàng.',
        };
        if (kind == LoiBangXepHang.dangNhap) {
          _data = null;
          _invalidSession = true;
        }
      });
      if (_invalidSession) _timer?.cancel();
    }
  }

  void _doiPhien() {
    if (!mounted || _chu == _chuHienTai) return;
    _mayChu.huyTaiTongThe();
    setState(() {
      _sequence++;
      _chu = _chuHienTai;
      _data = null;
      _message = null;
      _loading = false;
      _invalidSession = false;
    });
    _datHen();
    unawaited(_tai());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _datHen();
    if (_active && _route?.isCurrent != false) unawaited(_tai());
  }

  @override
  void didUpdateWidget(covariant ManHinhBangXepHang oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game || oldWidget.mayChu != widget.mayChu) {
      oldWidget.game.auth?.removeListener(_doiPhien);
      _mayChu.huyTaiTongThe();
      if (oldWidget.mayChu == null) _mayChu.dong();
      _mayChu =
          widget.mayChu ??
          MayChuBangXepHang(thoiGianCho: const Duration(seconds: 30));
      widget.game.auth?.addListener(_doiPhien);
      _sequence++;
      _chu = _chuHienTai;
      _data = null;
      _message = null;
      _loading = false;
      _invalidSession = false;
      _datHen();
      unawaited(_tai());
    }
  }

  @override
  void dispose() {
    _sequence++;
    _mayChu.huyTaiTongThe();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.game.auth?.removeListener(_doiPhien);
    if (widget.mayChu == null) _mayChu.dong();
    super.dispose();
  }

  Widget _thongBao(String text, {bool retry = false}) => Center(
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
          if (retry)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(
                onPressed: _loading ? null : () => unawaited(_tai()),
                child: const ChuGame('Thử lại'),
              ),
            ),
        ],
      ),
    ),
  );

  String _ngay(DateTime utc) {
    final date = utc.toUtc().add(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  Widget _noiDung() {
    if (_chu == null) return _thongBao('Đăng nhập để xem bảng xếp hạng.');
    final data = _data;
    if (data == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _thongBao(
        _message ?? 'Bảng xếp hạng tạm thời chưa sẵn sàng.',
        retry: true,
      );
    }
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            key: const PageStorageKey('bxh-top30'),
            padding: const EdgeInsets.all(12),
            children: [
              ChuGame(
                'Top 30 server · ${data.tongNguoi} người chơi',
                style: const TextStyle(
                  color: Color(0xFFF5B829),
                  fontWeight: FontWeight.bold,
                ),
              ),
              ChuGame(
                'Cập nhật: ${_ngay(data.capNhatLuc)} (giờ Việt Nam)',
                style: const TextStyle(color: Color(0xFFAFC0D2), fontSize: 12),
              ),
              if (data.duLieuCu)
                const ChuGame(
                  'Đang hiển thị dữ liệu cập nhật lần trước.',
                  style: TextStyle(color: Color(0xFFFFCF77)),
                ),
              if (_message case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ChuGame(
                    message,
                    style: const TextStyle(color: Color(0xFFFFCF77)),
                  ),
                ),
              const SizedBox(height: 12),
              if (data.ban case final mine?) ...[
                ChuGame(
                  'Hạng của bạn: ${mine.hang}',
                  style: const TextStyle(color: Color(0xFFF5B829)),
                ),
                if (mine.hang > 30) _TheNguoiChoi(row: mine, personal: true),
              ] else
                const ChuGame(
                  'Chưa có dữ liệu xếp hạng của bạn.',
                  style: TextStyle(color: Color(0xFFAFC0D2)),
                ),
              if (data.bang.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: ChuGame(
                    'Chưa có người chơi trong bảng xếp hạng.',
                    style: TextStyle(color: Color(0xFFAFC0D2)),
                  ),
                ),
              for (final row in data.bang) ...[
                if (row.hang == 1 || row.hang == 11 || row.hang == 21)
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 4),
                    child: ChuGame(
                      'Top ${row.hang == 1
                          ? 10
                          : row.hang == 11
                          ? 20
                          : 30}',
                      style: TextStyle(
                        color: _mauHang(row.hang),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                _TheNguoiChoi(row: row),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF081426),
    appBar: AppBar(
      backgroundColor: const Color(0xFF13233A),
      foregroundColor: const Color(0xFFF5F7FA),
      title: const ChuGame('Bảng xếp hạng'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: PhamViNgonNgu.of(context).dich('Quay lại'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: PhamViNgonNgu.of(context).dich('Làm mới'),
          onPressed: _chu == null || _loading ? null : () => unawaited(_tai()),
        ),
      ],
    ),
    body: SafeArea(child: _noiDung()),
  );
}

Color _mauHang(int rank) => rank <= 10
    ? const Color(0xFFF5B829)
    : rank <= 20
    ? const Color(0xFFC0C8D4)
    : rank <= 30
    ? const Color(0xFFB78050)
    : const Color(0xFF52677E);

class _TheNguoiChoi extends StatelessWidget {
  const _TheNguoiChoi({required this.row, this.personal = false});
  final DongBangTongThe row;
  final bool personal;

  String _vang(BuildContext context) {
    final text = row.vang.toString();
    final separator = switch (PhamViNgonNgu.of(context).ma.split('-').first) {
      'en' => ',',
      'fr' => '\u202f',
      'vi' || 'es' => '.',
      _ => '',
    };
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) out.write(separator);
      out.write(text[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) => Container(
    key: personal ? const ValueKey('bxh-own') : ValueKey('bxh-row-${row.hang}'),
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: row.laBan ? const Color(0xFF213D59) : const Color(0xFF13233A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _mauHang(row.hang), width: row.laBan ? 2 : 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChuGame(
              'Hạng ${row.hang}',
              style: TextStyle(color: _mauHang(row.hang)),
            ),
            const SizedBox(width: 10),
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
            const SizedBox(width: 8),
            ChuGame(
              'Cấp ${row.level}',
              style: const TextStyle(color: Color(0xFFF5F7FA)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Tooltip(
          message: PhamViNgonNgu.of(context)
              .dich('Vàng kiếm được: ${_vang(context)}'),
          child: ChuGame(
            'Vàng kiếm được: ${_vang(context)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFFFD577)),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChuGame(
              '${row.huyHieu.length} huy hiệu',
              style: const TextStyle(color: Color(0xFFAFC0D2), fontSize: 12),
            ),
            for (final id in row.huyHieu)
              Tooltip(
                message: PhamViNgonNgu.of(context).dich(
                  bangThanhTuuSBT.firstWhere((b) => b.achievementId == id).name,
                ),
                child: Image.asset(
                  bangThanhTuuSBT
                      .firstWhere((b) => b.achievementId == id)
                      .imagePath!,
                  width: 26,
                  height: 26,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.workspace_premium,
                    size: 26,
                    color: Color(0xFFF5B829),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
