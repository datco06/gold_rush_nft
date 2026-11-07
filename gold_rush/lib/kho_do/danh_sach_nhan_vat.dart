import 'package:flutter/material.dart';

import '../blockchain/nhan_vat.dart';
import '../blockchain/phien_vi.dart';
import '../giao_dien/mau_game.dart';

/// Danh sách nhân vật gốc và nhân vật cửa hàng đã sở hữu.
///
/// Quyền sở hữu đọc từ PhienVi.
/// Lựa chọn đang dùng nhận từ bên ngoài.
/// Không mua nhân vật hoặc tự thay đổi trạng thái game.
class DanhSachNhanVat extends StatefulWidget {
  final PhienVi? phienVi;
  final String tepNhanVatDangDung;

  /// Nhận ID nhân vật dưới dạng chuỗi.
  /// Callback hoàn tất khi lựa chọn được xác nhận.
  /// Callback phải ném lỗi nếu lựa chọn thất bại.
  final Future<void> Function(String characterId)? khiChonNhanVat;

  const DanhSachNhanVat({
    super.key,
    required this.phienVi,
    required this.tepNhanVatDangDung,
    this.khiChonNhanVat,
  });

  @override
  State<DanhSachNhanVat> createState() => _DanhSachNhanVatState();
}

class _DanhSachNhanVatState extends State<DanhSachNhanVat> {
  bool _dangChon = false;
  String? _loi;

  @override
  void didUpdateWidget(covariant DanhSachNhanVat oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.phienVi, widget.phienVi) ||
        oldWidget.tepNhanVatDangDung != widget.tepNhanVatDangDung) {
      _loi = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pv = widget.phienVi;

    if (pv == null) {
      return _noiDung(null);
    }

    return ListenableBuilder(
      listenable: pv,
      builder: (context, _) => _noiDung(pv),
    );
  }

  Widget _noiDung(PhienVi? pv) {
    final daKetNoi = pv?.daKetNoi ?? false;
    final banKhoa =
        _dangChon || (pv?.dangXuLy ?? false) || (pv?.dangHoi ?? false);

    // George luôn có.
    // Nhân vật cửa hàng chỉ hiển thị khi phiên ví xác nhận sở hữu.
    final danhSach = <NhanVatBan>[
      georgeGoc,
      if (daKetNoi)
        for (final nv in bangNhanVat)
          if (pv!.daCo.contains(nv.id)) nv,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Chọn ngoại hình nhân vật. '
          'Lựa chọn được áp dụng từ ván chơi tiếp theo.',
          style: TextStyle(color: MauGame.chuPhu, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        if (!daKetNoi) ...[
          const Text(
            'George mặc định luôn khả dụng. '
            'Chưa kết nối ví nên chưa xác nhận được '
            'các nhân vật cửa hàng.',
            style: TextStyle(color: MauGame.chuPhu, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
        ],
        if (pv?.dangXuLy ?? false) ...[
          const LinearProgressIndicator(color: MauGame.chinh),
          const SizedBox(height: 10),
          const Text(
            'Phiên ví đang xử lý. '
            'Vui lòng đợi trước khi chọn nhân vật.',
            style: TextStyle(color: MauGame.chuPhu, fontSize: 12),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            const khoangCach = 12.0;

            final soCot = ((constraints.maxWidth + khoangCach) / 212)
                .floor()
                .clamp(1, 4)
                .toInt();

            final rongThe =
                (constraints.maxWidth - (soCot - 1) * khoangCach) / soCot;

            return Wrap(
              spacing: khoangCach,
              runSpacing: khoangCach,
              children: [
                for (final nv in danhSach)
                  SizedBox(
                    width: rongThe,
                    child: _theNhanVat(nv, banKhoa: banKhoa),
                  ),
              ],
            );
          },
        ),
        if (_dangChon) ...[
          const SizedBox(height: 12),
          const Text(
            'Đang xác nhận lựa chọn nhân vật…',
            style: TextStyle(color: MauGame.chuPhu, fontSize: 12),
          ),
        ],
        if (_loi != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _loi!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
        if (widget.khiChonNhanVat == null) ...[
          const SizedBox(height: 12),
          const Text(
            'Chưa kết nối thao tác chọn nhân vật.',
            style: TextStyle(color: MauGame.chuPhu, fontSize: 12),
          ),
        ],
        if ((pv?.thongBao ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            pv!.thongBao!,
            style: TextStyle(
              color: pv.thongBaoLaLoi
                  ? Theme.of(context).colorScheme.error
                  : MauGame.chuPhu,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _theNhanVat(NhanVatBan nv, {required bool banKhoa}) {
    final dangDung = widget.tepNhanVatDangDung == nv.tepAnh;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MauGame.nen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dangDung ? MauGame.chinh : MauGame.vien,
          width: dangDung ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AnhNhanVat(tepAnh: nv.tepAnh, kichThuoc: 80)),
          const SizedBox(height: 14),
          Text(
            nv.ten,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MauGame.chu,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nv.moTa,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MauGame.chuPhu,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            nv.id == 0 ? 'Nhân vật mặc định' : 'Đã sở hữu theo phiên ví',
            textAlign: TextAlign.center,
            style: const TextStyle(color: MauGame.chuPhu, fontSize: 11),
          ),
          const SizedBox(height: 12),
          if (dangDung)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: MauGame.chinh,
                  size: 18,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Đang dùng',
                    style: TextStyle(
                      color: MauGame.chinh,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            OutlinedButton(
              onPressed: banKhoa || widget.khiChonNhanVat == null
                  ? null
                  : () => _chonNhanVat(nv),
              style: OutlinedButton.styleFrom(foregroundColor: MauGame.chinh),
              child: const Text('Chọn nhân vật'),
            ),
        ],
      ),
    );
  }

  Future<void> _chonNhanVat(NhanVatBan nv) async {
    final callback = widget.khiChonNhanVat;
    final pv = widget.phienVi;

    if (_dangChon ||
        callback == null ||
        (pv?.dangXuLy ?? false) ||
        (pv?.dangHoi ?? false)) {
      return;
    }

    // Kiểm tra lại quyền hiển thị trước khi gửi lựa chọn.
    if (nv.id != 0 &&
        (pv == null || !pv.daKetNoi || !pv.daCo.contains(nv.id))) {
      setState(() {
        _loi = 'Chưa xác nhận được quyền sở hữu nhân vật.';
      });
      return;
    }

    final diaChiLucChon = pv?.diaChi;

    setState(() {
      _dangChon = true;
      _loi = null;
    });

    try {
      await callback(nv.id.toString());

      if (!mounted) return;

      // Trạng thái "Đang dùng" vẫn lấy từ tham số bên ngoài.
      // Không tự gán lựa chọn thành công trong widget.
      setState(() {
        _dangChon = false;

        if (nv.id != 0 && pv?.diaChi != diaChiLucChon) {
          _loi =
              'Tài khoản ví đã thay đổi. '
              'Vui lòng kiểm tra lại danh sách nhân vật.';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _dangChon = false;
        _loi =
            'Không chọn được nhân vật. '
            'Vui lòng kiểm tra dữ liệu và thử lại.';
      });
    }
  }
}

/// Hiển thị khung đầu tiên của sprite sheet 4 cột × 4 hàng.
///
/// Kích thước khung được phóng theo kichThuoc,
/// không hiển thị toàn bộ sprite sheet.
class AnhNhanVat extends StatelessWidget {
  final String tepAnh;
  final double kichThuoc;

  const AnhNhanVat({super.key, required this.tepAnh, this.kichThuoc = 80})
    : assert(kichThuoc > 0);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: kichThuoc,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: kichThuoc * 4,
          maxWidth: kichThuoc * 4,
          minHeight: kichThuoc * 4,
          maxHeight: kichThuoc * 4,
          child: Image.asset(
            'assets/images/$tepAnh',
            width: kichThuoc * 4,
            height: kichThuoc * 4,
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            filterQuality: FilterQuality.none,
            errorBuilder: (context, error, stackTrace) {
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox.square(
                  dimension: kichThuoc,
                  child: const Tooltip(
                    message: 'Không tải được ảnh nhân vật',
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: MauGame.chuPhu,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
