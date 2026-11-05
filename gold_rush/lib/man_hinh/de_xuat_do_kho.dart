import 'package:flutter/material.dart';

import '../ai/de_xuat_do_kho.dart';
import '../ai/may_chu_de_xuat_do_kho.dart';
import '../cau_hinh.dart';

/// Xem đề xuất từ lịch sử của màn do tầng gọi chọn.
class ManHinhDeXuatDoKho extends StatefulWidget {
  final MayChuDeXuatDoKho mayChu;
  final int manChoi;

  const ManHinhDeXuatDoKho({
    super.key,
    required this.mayChu,
    required this.manChoi,
  });

  @override
  State<ManHinhDeXuatDoKho> createState() => _ManHinhDeXuatDoKhoState();
}

class _ManHinhDeXuatDoKhoState extends State<ManHinhDeXuatDoKho> {
  KetQuaDeXuatDoKho? _ketQua;
  bool _dangTai = false;
  int _phienTai = 0;

  @override
  void didUpdateWidget(covariant ManHinhDeXuatDoKho oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manChoi != widget.manChoi ||
        !identical(oldWidget.mayChu, widget.mayChu)) {
      _phienTai++;
      _ketQua = null;
      _dangTai = false;
    }
  }

  Future<void> _tai() async {
    if (_dangTai) return;
    final phien = ++_phienTai;
    setState(() {
      _dangTai = true;
      _ketQua = null;
    });
    final kq = await widget.mayChu.deXuat(manChoi: widget.manChoi);
    if (!mounted || phien != _phienTai) return;
    setState(() {
      _dangTai = false;
      _ketQua = kq;
    });
  }

  @override
  Widget build(BuildContext context) {
    final kq = _ketQua;
    final deXuat = kq?.deXuat;
    var nhanNut = 'Xem đề xuất';
    if (_dangTai) {
      nhanNut = 'Đang tải…';
    } else if (kq?.coTheThuLai ?? false) {
      nhanNut = 'Thử lại';
    } else if (deXuat != null) {
      nhanNut = 'Cập nhật đề xuất';
    }
    return Scaffold(
      appBar: AppBar(title: Text('Đề xuất độ khó màn ${widget.manChoi}')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_dangTai) ...[
                  const LinearProgressIndicator(
                    semanticsLabel: 'Đang lấy đề xuất',
                  ),
                  const SizedBox(height: 20),
                ],
                if (!_dangTai && kq == null)
                  const Text(
                    'Xem gợi ý độ khó dựa trên lịch sử chơi.',
                    textAlign: TextAlign.center,
                  ),
                if (deXuat != null) _theDeXuat(deXuat),
                if (kq?.loi != null)
                  Text(
                    _thongBaoLoi(kq!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _dangTai ? null : _tai,
                  icon: const Icon(Icons.insights),
                  label: Text(nhanNut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _theDeXuat(DeXuatDoKho deXuat) {
    final tenMuc = switch (deXuat.doKho) {
      'easy' => 'Dễ',
      'medium' => 'Trung bình',
      _ => 'Khó',
    };
    final diem = deXuat.diemHieuSuat;
    final diemHienThi = diem == null
        ? 'Chưa đủ dữ liệu'
        : '${(diem * 100).toStringAsFixed(1)} / 100';
    final nguon = deXuat.nguon == 'rule_based' ? 'Theo luật' : 'Dự phòng';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deXuat.nguonNguCanh == 'demo'
                  ? 'Dữ liệu demo'
                  : 'Lịch sử đã xác minh',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Độ khó đề xuất • $tenMuc',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: CauHinh.mauChinh,
              ),
            ),
            const SizedBox(height: 12),
            Text(deXuat.lyDo),
            const Divider(height: 28),
            Text('Điểm hiệu suất • $diemHienThi'),
            Text(
              'Hệ số tốc độ đề xuất • ×${deXuat.heSoTocDo.toStringAsFixed(2)}',
            ),
            Text('Ván được đánh giá • ${deXuat.soVan}'),
            Text('Nguồn đề xuất • $nguon'),
          ],
        ),
      ),
    );
  }
}

String _thongBaoLoi(KetQuaDeXuatDoKho kq) {
  if (kq.maHttp == 401) return 'Máy chủ cần xác minh người chơi.';
  if (kq.maHttp == 403) return 'Bạn chưa có quyền xem đề xuất cho màn này.';
  if (kq.maHttp == 429) return 'Đang có nhiều yêu cầu. Bạn có thể thử lại sau.';
  return switch (kq.loi) {
    LoiDeXuatDoKho.chuaCauHinh => 'Chưa cấu hình máy chủ AI.',
    LoiDeXuatDoKho.yeuCauKhongHopLe => 'Thông tin màn chơi chưa hợp lệ.',
    LoiDeXuatDoKho.hetThoiGian => 'Máy chủ phản hồi quá lâu. Hãy thử lại sau.',
    LoiDeXuatDoKho.ketNoi =>
      'Không kết nối được máy chủ. Hãy kiểm tra mạng và thử lại.',
    LoiDeXuatDoKho.biTuChoi =>
      'Máy chủ chưa chấp nhận yêu cầu đề xuất (${kq.maHttp}).',
    LoiDeXuatDoKho.mayChu => 'Dịch vụ đề xuất chưa sẵn sàng. Hãy thử lại sau.',
    _ => 'Chưa đọc được đề xuất. Hãy thử lại sau.',
  };
}
