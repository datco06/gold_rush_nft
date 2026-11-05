import 'dart:math';

import 'package:flutter/material.dart';

import '../ai/may_chu_nhiem_vu.dart';
import '../ai/nhiem_vu.dart';
import '../cau_hinh.dart';

/// Xem và tạo đề xuất nhiệm vụ cho màn do bên gọi chọn.
/// Backend quyết định quyền truy cập màn và ngữ cảnh demo/verified.
class ManHinhNhiemVu extends StatefulWidget {
  final MayChuNhiemVu mayChu;
  final int manChoi;

  const ManHinhNhiemVu({
    super.key,
    required this.mayChu,
    required this.manChoi,
  });

  @override
  State<ManHinhNhiemVu> createState() => _ManHinhNhiemVuState();
}

class _ManHinhNhiemVuState extends State<ManHinhNhiemVu> {
  KetQuaNhiemVu? _ketQua;
  String? _maYeuCau;
  bool _dangTai = false;
  int _phienTai = 0;

  @override
  void didUpdateWidget(covariant ManHinhNhiemVu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manChoi != widget.manChoi ||
        !identical(oldWidget.mayChu, widget.mayChu)) {
      // Phản hồi của màn hoặc danh tính cũ không được ghi vào phiên mới.
      _phienTai++;
      _ketQua = null;
      _maYeuCau = null;
      _dangTai = false;
    }
  }

  Future<void> _tai({bool thuLai = false}) async {
    if (_dangTai) return;
    if (!thuLai) _maYeuCau = _taoMaYeuCau();
    final ma = _maYeuCau;
    if (ma == null) return;
    final phien = ++_phienTai;
    setState(() {
      _dangTai = true;
      _ketQua = null;
    });
    final kq = await widget.mayChu.tao(manChoi: widget.manChoi, maYeuCau: ma);
    if (!mounted || phien != _phienTai) return;
    setState(() {
      _dangTai = false;
      _ketQua = kq;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kq = _ketQua;
    final nv = kq?.nhiemVu;
    return Scaffold(
      appBar: AppBar(title: Text('Nhiệm vụ màn ${widget.manChoi}')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_dangTai) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Đang tạo nhiệm vụ…', textAlign: TextAlign.center),
                ],
                if (!_dangTai && kq == null)
                  const Text(
                    'Tạo một đề xuất nhiệm vụ phù hợp với màn chơi.',
                    textAlign: TextAlign.center,
                  ),
                if (nv != null) _theNhiemVu(nv),
                if (kq?.loi != null)
                  Text(
                    _thongBaoLoi(kq!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 20),
                if (kq?.coTheThuLai ?? false)
                  FilledButton.icon(
                    onPressed: () => _tai(thuLai: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _dangTai ? null : () => _tai(),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      _dangTai
                          ? 'Đang tải…'
                          : kq == null
                          ? 'Tạo nhiệm vụ'
                          : 'Tạo nhiệm vụ mới',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _theNhiemVu(NhiemVu nv) {
    final mucTieu = switch (nv.mucTieu) {
      'collect_coins' => 'Thu thập ${nv.soLuong} xu',
      'finish_before_time' => 'Hoàn thành màn trước thời hạn',
      _ => 'Hoàn thành màn, trúng đòn tối đa ${nv.soLuong} lần',
    };
    final doKho = switch (nv.doKho) {
      'easy' => 'Dễ',
      'medium' => 'Trung bình',
      _ => 'Khó',
    };
    final nguon = switch (nv.nguonSinh) {
      'llm' => 'LLM',
      'rule_based' => 'Theo luật',
      _ => 'Mẫu demo',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nv.nguonNguCanh == 'demo'
                  ? 'Ngữ cảnh demo'
                  : 'Ngữ cảnh đã xác minh',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              nv.tieuDe,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: CauHinh.mauChinh,
              ),
            ),
            const SizedBox(height: 8),
            Text(nv.moTa),
            const Divider(height: 28),
            Text(mucTieu),
            if (nv.gioiHanGiay != null)
              Text('Thời hạn • ${nv.gioiHanGiay} giây'),
            Text('Độ khó • $doKho'),
            Text('Thưởng • ${nv.vangThuong} vàng'),
            Text('Nguồn sinh • $nguon'),
            const SizedBox(height: 8),
            const Text('Trạng thái • Được đề xuất'),
          ],
        ),
      ),
    );
  }
}

String _taoMaYeuCau() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  return 'req_${bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
}

String _thongBaoLoi(KetQuaNhiemVu kq) {
  if (kq.maHttp == 403) {
    return 'Màn này chưa được ngữ cảnh người chơi cho phép.';
  }
  if (kq.maHttp == 401) return 'Cần xác thực người chơi với máy chủ.';
  if (kq.maHttp == 429) {
    return 'Máy chủ đang giới hạn yêu cầu. Hãy thử lại sau.';
  }
  return switch (kq.loi) {
    LoiNhiemVu.chuaCauHinh =>
      'Chưa cấu hình GOLD_RUSH_API. Tính năng nhiệm vụ đang offline.',
    LoiNhiemVu.yeuCauKhongHopLe => 'Thông tin yêu cầu nhiệm vụ không hợp lệ.',
    LoiNhiemVu.hetThoiGian =>
      'Máy chủ phản hồi quá lâu. Có thể thử lại cùng yêu cầu.',
    LoiNhiemVu.ketNoi =>
      'Không kết nối được máy chủ. Hãy kiểm tra mạng và thử lại.',
    LoiNhiemVu.biTuChoi => 'Máy chủ từ chối yêu cầu nhiệm vụ (${kq.maHttp}).',
    LoiNhiemVu.mayChu => 'Dịch vụ nhiệm vụ chưa sẵn sàng. Hãy thử lại sau.',
    _ => 'Phản hồi nhiệm vụ không hợp lệ. Hãy tạo yêu cầu mới.',
  };
}
