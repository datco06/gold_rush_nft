import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/loi_hop_dong.dart';
import 'package:gold_rush/blockchain/vi.dart';

void main() {
  final mau = jsonDecode(File('test/blockchain/abi_mau.json').readAsStringSync()) as Map<String, dynamic>;

  test('bảng bộ chọn lỗi khớp Python (và Hardhat đã đối chiếu với ABI thật)', () {
    expect(boChonLoi, (mau['loi'] as Map).cast<String, String>());
  });

  test('đọc dữ liệu revert thật: ERC1155InsufficientBalance → "có 3, cần 8"', () {
    expect(dichLoiHopDong(duLieu: mau['revert_mau']), 'Không đủ vàng: có 3, cần 8.');
  });

  test('tìm dữ liệu revert lồng nhau như MetaMask trả về', () {
    final loi = {
      'code': -32603,
      'message': 'Internal JSON-RPC error.',
      'data': {
        'originalError': {'code': 3, 'data': '0x1623efa8${'0' * 63}1', 'message': 'execution reverted'},
      },
    };
    expect(dichLoiHopDong(duLieu: loi), 'Màn luyện tập không cần vé.');
  });

  test('Hardhat ghi tên lỗi trong thông điệp', () {
    expect(dichLoiHopDong(thongDiep: "reverted with custom error 'PhieuDaDung()'"), 'Phiếu này đã được nhận rồi.');
  });

  test('Error(string) của require', () {
    // Error("Hết") — offset 0x20, độ dài 5 byte UTF-8 (H · ế = 3 byte · t)
    final than = '${'0' * 62}20${'0' * 63}5${'48e1babf74'.padRight(64, '0')}';
    expect(dichLoiHopDong(duLieu: '0x08c379a0$than'), 'Hợp đồng từ chối: Hết.');
  });

  test('không phải revert → null', () {
    expect(dichLoiHopDong(duLieu: null, thongDiep: 'network error'), isNull);
  });

  test('phân loại lỗi ví', () {
    expect(taoLoiVi(ma: 4001).loai, LoaiLoiVi.tuChoi);
    expect(taoLoiVi(ma: 4001).nguoiDungTuChoi, isTrue);
    expect(taoLoiVi(ma: -32002).loai, LoaiLoiVi.dangCho);
    expect(taoLoiVi(ma: 4902).loai, LoaiLoiVi.chuaCoMang);
    expect(taoLoiVi(ma: -32603, thongDiep: 'Nonce too high. Expected nonce to be 0').loai, LoaiLoiVi.saiNonce);
    expect(taoLoiVi(ma: -32000, thongDiep: 'insufficient funds for gas').loai, LoaiLoiVi.thieuEth);
    expect(taoLoiVi(ma: 3, duLieu: '0x1cc576f1').loai, LoaiLoiVi.hopDongTuChoi);
    expect(taoLoiVi(thongDiep: 'gì đó').loai, LoaiLoiVi.khac);
  });
}
