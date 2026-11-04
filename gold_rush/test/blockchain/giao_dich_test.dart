import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/giao_dich.dart';
import 'package:gold_rush/blockchain/loi_hop_dong.dart';
import 'package:gold_rush/blockchain/vi.dart';

import 'vi_gia.dart';

/// Bộ giao dịch: mỗi lỗi MetaMask kinh điển phải bị chặn TRƯỚC khi mở hộp thoại, hoặc xử lý đúng sau đó.
void main() {
  const duLieu = '0x27654f7a0000000000000000000000000000000000000000000000000000000000000001';

  Future<KetQuaGui> gui(ViGia vi, {Future<bool> Function()? daXong, BoGiaoDich? bo}) =>
      (bo ?? boThu(vi)).gui(tu: viThu, duLieu: duLieu, moTa: 'thử', daXong: daXong);

  test('đường suôn sẻ: gửi một lần, gas = ước lượng + 20%', () async {
    final vi = ViGia();
    expect(await gui(vi), KetQuaGui.thanhCong);
    expect(vi.daGui, [duLieu]);
    expect(vi.gasDaGui.single, BigInt.from(120000));
  });

  test('tài khoản trong ví đã đổi → dừng, không mở MetaMask', () async {
    final vi = ViGia(taiKhoan: ['0x${'b' * 40}']);
    await expectLater(gui(vi), throwsA(isA<LoiVi>().having((e) => e.loai, 'loai', LoaiLoiVi.doiTaiKhoan)));
    expect(vi.daGui, isEmpty);
  });

  test('sai mạng → xin chuyển; người chơi huỷ chuyển → dừng', () async {
    final ok = ViGia(mang: 1);
    expect(await gui(ok), KetQuaGui.thanhCong);
    expect(ok.soLanChuyenMang, 1);

    final huy = ViGia(mang: 1)..mangSauKhiChuyen = 1;
    await expectLater(gui(huy), throwsA(isA<LoiVi>()));
    expect(huy.daGui, isEmpty);
  });

  test('địa chỉ không có hợp đồng (vừa khởi động lại hardhat node) → dừng', () async {
    final vi = ViGia()..maByte = '0x';
    await expectLater(gui(vi), throwsA(isA<LoiVi>().having((e) => e.thongBao, 'tb', contains('ignition'))));
    expect(vi.daGui, isEmpty);
  });

  test('mô phỏng revert → câu tiếng Việt, KHÔNG mở MetaMask', () async {
    final vi = ViGia()
      ..loiMoPhong = taoLoiVi(ma: -32603, thongDiep: 'execution reverted', duLieu: {
        'code': 3,
        'data': '0x1427af6a${'0' * 63}1', // DaCo(1)
      });
    await expectLater(gui(vi), throwsA(isA<LoiVi>().having((e) => e.thongBao, 'tb', 'Bạn đã có nhân vật này.')));
    expect(vi.daGui, isEmpty);
  });

  test('không đủ ETH trả phí → dừng trước khi gửi', () async {
    final vi = ViGia()..soDuEth = BigInt.from(1000);
    await expectLater(gui(vi), throwsA(isA<LoiVi>().having((e) => e.loai, 'loai', LoaiLoiVi.thieuEth)));
    expect(vi.daGui, isEmpty);
  });

  test('đã xong từ trước → không gửi, không tốn phí', () async {
    final vi = ViGia();
    expect(await gui(vi, daXong: () async => true), KetQuaGui.daXongTuTruoc);
    expect(vi.daGui, isEmpty);
  });

  test('chờ vài nhịp rồi mới có biên lai', () async {
    final vi = ViGia()..bienLaiLanLuot = [null, null, const BienLai(thanhCong: true)];
    expect(await gui(vi), KetQuaGui.thanhCong);
    expect(vi.soLanHoiBienLai, 3);
  });

  test('"Tăng tốc" trong MetaMask: mã cũ không có biên lai nhưng trạng thái đích đã đạt', () async {
    final vi = ViGia()..bienLaiLanLuot = [null];
    var daVaoKhoi = false;
    vi.khiGui = (_) => daVaoKhoi = true;
    var lan = 0;
    final kq = await gui(vi, daXong: () async => lan++ > 0 && daVaoKhoi);
    expect(kq, KetQuaGui.thanhCong);
  });

  test('revert lúc vào khối → mô phỏng lại để lấy lý do', () async {
    final vi = ViGia()..bienLaiLanLuot = [const BienLai(thanhCong: false)];
    vi.khiGui = (_) => vi.loiMoPhong = taoLoiVi(duLieu: {'data': '0x1cc576f1'}); // SaiVe()
    await expectLater(gui(vi), throwsA(isA<LoiVi>().having((e) => e.thongBao, 'tb', contains('Vé không khớp'))));
  });

  test('quá lâu chưa vào khối → lỗi "chưa xác nhận", dặn ĐỪNG gửi lại', () async {
    final vi = ViGia()..bienLaiLanLuot = [null];
    await expectLater(
      gui(vi, bo: boThu(vi, choToiDa: const Duration(seconds: 3))),
      throwsA(isA<LoiVi>()
          .having((e) => e.loai, 'loai', LoaiLoiVi.chuaXacNhan)
          .having((e) => e.thongBao, 'tb', contains('ĐỪNG gửi lại'))),
    );
    expect(vi.daGui.length, 1);
  });

  test('một lúc một giao dịch: bấm hai lần không mở hai hộp thoại', () async {
    final vi = ViGia()..bienLaiLanLuot = [null, null, const BienLai(thanhCong: true)];
    final bo = boThu(vi);
    final dau = gui(vi, bo: bo);
    await expectLater(gui(vi, bo: bo), throwsA(isA<LoiVi>().having((e) => e.loai, 'loai', LoaiLoiVi.dangCho)));
    expect(await dau, KetQuaGui.thanhCong);
    expect(vi.daGui.length, 1);
  });

  test('định dạng ETH và rút gọn mã', () {
    expect(dinhDangEth(BigInt.from(10).pow(18)), '1.000000');
    expect(dinhDangEth(BigInt.from(123456789000000)), '0.000123');
    expect(rutGon('0x${'a' * 40}'), '0xaaaa…aaaa');
  });
}
