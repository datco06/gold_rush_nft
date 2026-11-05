import 'dart:math';

import 'package:flutter/material.dart';

import '../ai/anh_nhan_vat.dart';
import '../ai/may_chu_nhan_vat.dart';

/// Preview ảnh tĩnh; cùng client/ngữ cảnh được dùng cho cả tạo và tải ảnh.
class ManHinhAnhNhanVat extends StatefulWidget {
  final MayChuNhanVat mayChu;

  const ManHinhAnhNhanVat({super.key, required this.mayChu});

  @override
  State<ManHinhAnhNhanVat> createState() => _ManHinhAnhNhanVatState();
}

class _ManHinhAnhNhanVatState extends State<ManHinhAnhNhanVat> {
  final _form = GlobalKey<FormState>();
  final _moTa = TextEditingController();
  KetQuaAnhNhanVat? _ketQua;
  AnhNhanVat? _anh;
  String? _maYeuCau;
  String? _moTaDaGui;
  bool _dangTai = false;
  bool _dangTao = false;
  int _phienTai = 0;

  @override
  void didUpdateWidget(covariant ManHinhAnhNhanVat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.mayChu, widget.mayChu)) {
      // Kết quả của danh tính cũ không được xuất hiện trong phiên mới.
      _phienTai++;
      _ketQua = null;
      _anh = null;
      _maYeuCau = null;
      _moTaDaGui = null;
      _dangTai = false;
      _dangTao = false;
      _form.currentState?.reset();
      _moTa.clear();
    }
  }

  @override
  void dispose() {
    _moTa.dispose();
    super.dispose();
  }

  void _doiMoTa(String _) {
    setState(() {
      _ketQua = null;
      _anh = null;
      _maYeuCau = null;
      _moTaDaGui = null;
    });
  }

  Future<void> _tao({bool thuLai = false}) async {
    if (_dangTai || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    if (!thuLai) {
      _maYeuCau = _taoMaYeuCau();
      _moTaDaGui = _moTa.text.trim();
    }
    final ma = _maYeuCau;
    final moTa = _moTaDaGui;
    if (ma == null || moTa == null) return;
    final api = widget.mayChu;
    final phien = ++_phienTai;
    setState(() {
      _dangTai = true;
      _dangTao = true;
      _anh = null;
      _ketQua = null;
    });
    final kq = await api.tao(moTa: moTa, maYeuCau: ma);
    if (!mounted || phien != _phienTai) return;
    if (kq.loi != null) {
      setState(() {
        _dangTai = false;
        _ketQua = kq;
      });
      return;
    }
    _anh = kq.anh!;
    await _taiVaHienThi(api, _anh!, phien);
  }

  Future<void> _taiLai() async {
    final anh = _anh;
    if (_dangTai || anh == null) return;
    final phien = ++_phienTai;
    setState(() {
      _dangTai = true;
      _ketQua = null;
    });
    await _taiVaHienThi(widget.mayChu, anh, phien);
  }

  Future<void> _taiVaHienThi(
    MayChuNhanVat api,
    AnhNhanVat anh,
    int phien,
  ) async {
    setState(() => _dangTao = false);
    final kq = await api.tai(anh);
    if (!mounted || phien != _phienTai) return;
    setState(() {
      _dangTai = false;
      _ketQua = kq;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kq = _ketQua;
    final png = kq?.png;
    final anh = _anh;
    final nhanCho = _dangTao ? 'Đang tạo ảnh…' : 'Đang tải ảnh…';
    return Scaffold(
      appBar: AppBar(title: const Text('Ảnh nhân vật AI')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Mô tả nhân vật bạn muốn xem, như một thợ mỏ đội mũ vàng.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _moTa,
                    enabled: !_dangTai,
                    minLines: 3,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả nhân vật',
                      helperText: 'Tối đa 500 ký tự.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return 'Hãy nhập mô tả nhân vật.';
                      if (text.runes.length > 500) {
                        return 'Mô tả tối đa 500 ký tự.';
                      }
                      return null;
                    },
                    onChanged: _doiMoTa,
                  ),
                  const SizedBox(height: 20),
                  if (_dangTai) ...[
                    LinearProgressIndicator(semanticsLabel: nhanCho),
                    const SizedBox(height: 12),
                    Text(nhanCho, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                  if (png != null && anh != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              anh.nguonSinh == 'demo'
                                  ? 'Ảnh mẫu demo'
                                  : 'Ảnh từ mô hình AI',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              anh.nguonNguCanh == 'demo'
                                  ? 'Phiên demo'
                                  : 'Phiên đã xác minh',
                            ),
                            if (anh.nguonSinh == 'demo')
                              const Text('Ảnh mẫu được chọn theo mô tả.'),
                            const SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 256),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Image.memory(
                                  png,
                                  filterQuality: FilterQuality.none,
                                  fit: BoxFit.contain,
                                  semanticLabel: 'Ảnh xem trước nhân vật',
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Text('Chưa hiển thị được ảnh.'),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Ảnh tĩnh để xem trước.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (kq?.loi != null) ...[
                    Text(
                      _thongBaoLoi(kq!, daTao: anh != null),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!_dangTai && (kq?.coTheThuLai ?? false)) ...[
                    OutlinedButton.icon(
                      onPressed: anh == null
                          ? () => _tao(thuLai: true)
                          : _taiLai,
                      icon: const Icon(Icons.refresh),
                      label: Text(anh == null ? 'Thử lại' : 'Tải lại ảnh'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _dangTai ? null : () => _tao(),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _dangTai
                          ? 'Đang xử lý…'
                          : _maYeuCau == null
                          ? 'Tạo ảnh'
                          : 'Tạo ảnh mới',
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

String _taoMaYeuCau() {
  final random = Random.secure();
  return 'imgreq_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

String _thongBaoLoi(KetQuaAnhNhanVat kq, {required bool daTao}) {
  if (kq.maHttp == 401) return 'Máy chủ cần xác minh người chơi.';
  if (kq.maHttp == 403) return 'Bạn chưa có quyền sử dụng ảnh này.';
  if (kq.maHttp == 404 && daTao) {
    return 'Ảnh đã hết hạn hoặc không còn khả dụng. Hãy tạo ảnh mới.';
  }
  if (kq.maHttp == 409) {
    return 'Yêu cầu này đã dùng cho mô tả khác. Hãy tạo ảnh mới.';
  }
  if (kq.maHttp == 429) return 'Đang có nhiều yêu cầu. Bạn có thể thử lại sau.';
  return switch (kq.loi) {
    LoiAnhNhanVat.chuaCauHinh => 'Chưa cấu hình máy chủ AI.',
    LoiAnhNhanVat.yeuCauKhongHopLe => 'Mô tả nhân vật chưa hợp lệ.',
    LoiAnhNhanVat.hetThoiGian =>
      'Máy chủ phản hồi quá lâu. Bạn có thể thử lại.',
    LoiAnhNhanVat.ketNoi =>
      'Không kết nối được máy chủ. Hãy kiểm tra mạng và thử lại.',
    LoiAnhNhanVat.biTuChoi =>
      'Máy chủ chưa chấp nhận yêu cầu ảnh (${kq.maHttp}).',
    LoiAnhNhanVat.mayChu =>
      'Dịch vụ ảnh chưa sẵn sàng. Bạn có thể thử lại sau.',
    _ =>
      daTao
          ? 'Ảnh nhận được không hợp lệ. Hãy tạo ảnh mới.'
          : 'Phản hồi tạo ảnh không hợp lệ. Hãy tạo ảnh mới.',
  };
}
