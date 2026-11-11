import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/abi.dart';
import 'package:gold_rush/blockchain/cua_hang.dart';
import 'package:gold_rush/blockchain/giao_dich.dart';
import 'package:gold_rush/blockchain/vi.dart';

import 'vi_gia.dart';

void main() {
  late ViGia vi;
  late CuaHangChuoi ch;

  setUp(() {
    vi = ViGia();
    ch = CuaHangChuoi(vi: vi, hopDong: hopDongThu, bo: boThu(vi));
    // manChoi(id) → (cọc, trần vàng mỗi phiếu)
    vi.ketQuaGoi[maHoaManChoi(2)] = '0x${tu(BigInt.from(5))}${tu(BigInt.from(23))}';
    vi.ketQuaGoi[maHoaManChoi(1)] = '0x${tu(BigInt.zero)}${tu(BigInt.from(24))}';
  });

  final xa = DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

  PhieuCho phieu(String maVan, {int man = 1, int ve = 0, int soVang = 4, String? nguoi, int? han}) => PhieuCho(
        phieu: PhieuVang(
          nguoiChoi: nguoi ?? viThu,
          man: BigInt.from(man),
          ve: BigInt.from(ve),
          soVang: BigInt.from(soVang),
          maVan: '0x${maVan * (64 ~/ maVan.length)}',
          hanChot: BigInt.from(han ?? xa),
        ),
        chuKy: '0x${'3' * 130}',
        maVan: maVan,
      );

  test('mua đủ vàng: một lệnh → gọi thẳng mua(id), không multicall', () async {
    vi.datSo(maHoaGia(2), BigInt.from(30));
    vi.datSo(maHoaBalanceOf(viThu, 0), BigInt.from(31));
    expect(await ch.thucHien(diaChi: viThu, muaNhanVat: 2), KetQuaGui.thanhCong);
    expect(vi.daGui, [maHoaMua(2)]);
  });

  test('thiếu vàng / đã có / chưa bán → báo lỗi, KHÔNG gửi', () async {
    vi.datSo(maHoaGia(2), BigInt.from(30));
    vi.datSo(maHoaBalanceOf(viThu, 0), BigInt.from(29));
    await expectLater(ch.thucHien(diaChi: viThu, muaNhanVat: 2), throwsA(isA<LoiVi>()));
    vi.datSo(maHoaBalanceOf(viThu, 2), BigInt.one);
    await expectLater(ch.thucHien(diaChi: viThu, muaNhanVat: 2), throwsA(isA<LoiVi>()));
    await expectLater(ch.thucHien(diaChi: viThu, muaNhanVat: 3), throwsA(isA<LoiVi>()));
    expect(vi.daGui, isEmpty);
  });

  test('8 vàng + phiếu 4 vàng → mua nhân vật giá 10 trong MỘT giao dịch multicall', () async {
    vi.datSo(maHoaGia(1), BigInt.from(10));
    vi.datSo(maHoaBalanceOf(viThu, 0), BigInt.from(8));
    final p = phieu('a');
    await ch.thucHien(diaChi: viThu, phieu: [p], muaNhanVat: 1);
    expect(vi.daGui.single, maHoaMulticall([maHoaNhanVang(p.phieu, p.chuKy), maHoaMua(1)]));
  });

  test('vào màn có cọc: nhận phiếu của vé cũ TRƯỚC, rồi mua vé mới — cùng giao dịch', () async {
    vi.datVe(viThu, man: 2, so: 1, coc: 5);
    final cuaVeCu = phieu('b', man: 2, ve: 1, soVang: 23); // thắng màn 2 bằng vé 1, chưa nhận
    await ch.thucHien(diaChi: viThu, phieu: [cuaVeCu], vaoMan: 2);
    expect(vi.daGui.single, maHoaMulticall([maHoaNhanVang(cuaVeCu.phieu, cuaVeCu.chuKy), maHoaVaoMan(2)]));
  });

  test('chưa đủ vàng đặt cọc (kể cả tính phiếu chờ) → không gửi', () async {
    vi.datSo(maHoaBalanceOf(viThu, 0), BigInt.from(1));
    await expectLater(
      ch.thucHien(diaChi: viThu, phieu: [phieu('c', soVang: 2)], vaoMan: 2),
      throwsA(isA<LoiVi>().having((e) => e.thongBao, 'tb', contains('cần 5, có 3'))),
    );
    expect(vi.daGui, isEmpty);
  });

  test('lọc phiếu: ví khác, sắp hết hạn, trùng, đã nhận, vé đã bị thay → bỏ', () async {
    vi.datVe(viThu, man: 3, so: 4, coc: 8);
    final daNhan = phieu('d');
    vi.datSo(maHoaDaDoi(daNhan.phieu.maVan), BigInt.one);
    final tot = phieu('e');
    final veDung = phieu('f', man: 3, ve: 4);
    final con = await ch.locPhieuDungDuoc(viThu, [
      tot,
      phieu('1', nguoi: '0x${'b' * 40}'),
      phieu('2', han: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30),
      tot,
      daNhan,
      phieu('9', man: 2, ve: 1), // vé 1 đã bị thay bằng vé 4
      veDung,
    ], await ch.veCua(viThu));
    expect(con.map((p) => p.maVan), ['e', 'f']);
  });

  test('mọi phiếu đã nhận từ trước → không gửi gì', () async {
    final p = phieu('a');
    vi.datSo(maHoaDaDoi(p.phieu.maVan), BigInt.one);
    expect(await ch.thucHien(diaChi: viThu, phieu: [p]), KetQuaGui.daXongTuTruoc);
    expect(vi.daGui, isEmpty);
  });

  test('đọc vé, vàng, nhân vật, màn', () async {
    vi.datVe(viThu, man: 2, so: 7, coc: 5);
    vi.datSo(maHoaBalanceOf(viThu, 0), BigInt.from(12));
    vi.datSo(maHoaBalanceOf(viThu, 1), BigInt.one);
    final v = await ch.veCua(viThu);
    expect([v.man, v.so, v.coc], [2, 7, BigInt.from(5)]);
    expect(await ch.soVang(viThu), BigInt.from(12));
    expect(await ch.coNhanVat(viThu, 1), isTrue);
    expect(await ch.coNhanVat(viThu, 3), isFalse);
    expect(await ch.manChoi(2), (BigInt.from(5), BigInt.from(23)));
  });
}
