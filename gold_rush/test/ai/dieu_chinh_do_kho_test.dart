import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/dieu_chinh_do_kho.dart';
import 'package:gold_rush/ai/mo_hinh_do_kho.dart';

/// Mô hình giả: luôn trả về một xác suất cố định, để kiểm thử bộ điều chỉnh
/// độc lập với mô hình thật (cùng kỹ thuật "thay mô hình bằng bản giả" mà
/// notebook dùng trong tests/test_api.py).
class MoHinhGia extends MoHinhDoKho {
  final double p;
  MoHinhGia(this.p)
      : super(
          phienBan: 'gia',
          dacTrung: MoHinhDoKho.dacTrungHoTro,
          trungBinh: List.filled(5, 0.0),
          doLech: List.filled(5, 1.0),
          heSo: List.filled(5, 0.0),
          chan: 0.0,
        );

  @override
  double duDoan(List<double> x) => p;
}

List<double> sauPhut(double phut) => [1, 0, 0, 0, phut];

void main() {
  test('mục tiêu bị kẹp trong [0,8; 1,15] và bằng 1 khi p = 0,5', () {
    expect(DieuChinhDoKho.mucTieu(1.0), 0.8);
    expect(DieuChinhDoKho.mucTieu(0.0), 1.15);
    expect(DieuChinhDoKho.mucTieu(0.5), closeTo(1.0, 1e-12));
  });

  test('không có mô hình → luôn 1.0', () {
    final dc = DieuChinhDoKho();
    dc.capNhat(sauPhut(3));
    expect(dc.heSoTocDo, 1.0);
  });

  test('đầu ván (< 0,5 phút) chưa chỉnh', () {
    final dc = DieuChinhDoKho(moHinh: MoHinhGia(1.0));
    dc.capNhat(sauPhut(0.3));
    expect(dc.heSoTocDo, 1.0);
    expect(dc.pGanNhat, isNull);
  });

  test('sắp thua → kẻ địch chậm dần, mỗi lần đi 30% quãng đường', () {
    final dc = DieuChinhDoKho(moHinh: MoHinhGia(1.0));
    dc.capNhat(sauPhut(1));
    expect(dc.heSoTocDo, closeTo(1.0 + (0.8 - 1.0) * 0.3, 1e-12));
    for (var i = 0; i < 40; i++) {
      dc.capNhat(sauPhut(1));
    }
    expect(dc.heSoTocDo, closeTo(0.8, 1e-4));
  });

  test('tắt thích ứng → về 1.0 ngay, bật lại thì dùng tiếp giá trị cũ', () {
    final dc = DieuChinhDoKho(moHinh: MoHinhGia(0.0));
    for (var i = 0; i < 40; i++) {
      dc.capNhat(sauPhut(2));
    }
    expect(dc.heSoTocDo, closeTo(1.15, 1e-4));
    dc.batThichUng = false;
    expect(dc.heSoTocDo, 1.0);
    dc.batThichUng = true;
    expect(dc.heSoTocDo, closeTo(1.15, 1e-4));
  });

  test('ván mới đặt lại', () {
    final dc = DieuChinhDoKho(moHinh: MoHinhGia(1.0));
    dc.capNhat(sauPhut(1));
    dc.datLai();
    expect(dc.heSoTocDo, 1.0);
  });
}
