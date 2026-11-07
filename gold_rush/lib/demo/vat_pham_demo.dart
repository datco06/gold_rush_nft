import 'package:flutter/material.dart';

import '../giao_dien/khung_game.dart';
import '../giao_dien/mau_game.dart';
import '../kho_do/luoi_vat_pham.dart';
import '../kho_do/vat_pham_hien_thi.dart';

void main() {
  runApp(const _UngDungDemo());
}

class _UngDungDemo extends StatelessWidget {
  const _UngDungDemo();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MauGame.chinh,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: MauGame.nen,
      ),
      home: const _DemoVatPham(),
    );
  }
}

class _DemoVatPham extends StatefulWidget {
  const _DemoVatPham();

  @override
  State<_DemoVatPham> createState() => _DemoVatPhamState();
}

class _DemoVatPhamState extends State<_DemoVatPham> {
  String? _idDangChon;
  bool _dangMo = true;

  // Chỉ phục vụ minh họa giao diện.
  // Các thuộc tính và trạng thái này không áp dụng vào gameplay.
  final List<VatPhamHienThi> _duLieuMau = [
    VatPhamHienThi(
      id: 'demo_kiem',
      ten: 'Kiếm hành trình',
      loai: LoaiVatPham.vuKhi,
      doHiem: DoHiemVatPham.thuong,
      nguon: NguonVatPham.game,
      bieuTuong: BieuTuongVatPham.kiem,
      laDuLieuMau: true,
      moTa: 'Vũ khí mẫu để kiểm tra giao diện.',
      thuocTinh: {'Sát thương mẫu': '12', 'Tốc độ mẫu': 'Trung bình'},
      oDangTrangBi: OTrangBi.vuKhiChinh,
    ),
    VatPhamHienThi(
      id: 'demo_cung',
      ten: 'Cung rừng xanh',
      loai: LoaiVatPham.vuKhi,
      doHiem: DoHiemVatPham.hiem,
      nguon: NguonVatPham.game,
      bieuTuong: BieuTuongVatPham.cung,
      laDuLieuMau: true,
      thuocTinh: {'Sát thương mẫu': '9', 'Tầm đánh mẫu': 'Xa'},
    ),
    VatPhamHienThi(
      id: 'demo_giap',
      ten: 'Giáp người thám hiểm',
      loai: LoaiVatPham.giap,
      doHiem: DoHiemVatPham.khongPhoBien,
      nguon: NguonVatPham.game,
      bieuTuong: BieuTuongVatPham.giap,
      laDuLieuMau: true,
      thuocTinh: {'Phòng thủ mẫu': '6'},
    ),
    VatPhamHienThi(
      id: 'demo_binh',
      ten: 'Bình hồi phục',
      loai: LoaiVatPham.vatPham,
      doHiem: DoHiemVatPham.thuong,
      nguon: NguonVatPham.game,
      bieuTuong: BieuTuongVatPham.binhHoiPhuc,
      laDuLieuMau: true,
      thuocTinh: {'Hiệu ứng mẫu': 'Hồi 20 máu'},
    ),
  ];

  @override
  Widget build(BuildContext context) {
    VatPhamHienThi? vatPhamDangChon;

    for (final vatPham in _duLieuMau) {
      if (vatPham.id == _idDangChon) {
        vatPhamDangChon = vatPham;
        break;
      }
    }

    return Scaffold(
      body: !_dangMo
          ? Center(
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    _dangMo = true;
                  });
                },
                child: const Text('Mở lại demo'),
              ),
            )
          : KhungGame(
              tieuDe: 'DEMO THẺ VẬT PHẨM',
              chieuRongToiDa: 1400,
              khiDong: () {
                setState(() {
                  _dangMo = false;
                });
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'DỮ LIỆU MINH HỌA — không phải kho đồ thật',
                    style: TextStyle(
                      color: MauGame.chinh,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chạm thẻ để chọn. Chưa thực hiện trang bị '
                    'hoặc thay đổi chỉ số trong game.',
                    style: TextStyle(color: MauGame.chuPhu, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  LuoiVatPham(
                    danhSach: _duLieuMau,
                    idDangChon: _idDangChon,
                    khiChon: (vatPham) {
                      setState(() {
                        _idDangChon = vatPham.id;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    vatPhamDangChon == null
                        ? 'Chưa chọn vật phẩm.'
                        : 'Đang xem: ${vatPhamDangChon.ten}\n'
                              'ID: ${vatPhamDangChon.id}',
                    style: const TextStyle(color: MauGame.chu, height: 1.5),
                  ),
                ],
              ),
            ),
    );
  }
}
