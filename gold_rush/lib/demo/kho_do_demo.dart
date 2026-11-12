import 'package:flutter/material.dart';

import '../blockchain/nhan_vat.dart';
import '../giao_dien/mau_game.dart';
import '../kho_do/vat_pham_hien_thi.dart';
import '../man_hinh/kho_do.dart';

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
      home: const _TrangDemo(),
    );
  }
}

class _TrangDemo extends StatefulWidget {
  const _TrangDemo();

  @override
  State<_TrangDemo> createState() => _TrangDemoState();
}

class _TrangDemoState extends State<_TrangDemo> {
  TrangThaiKhoDo _trangThai = TrangThaiKhoDo.daTai;

  bool _moKhoDo = true;
  bool _giaLapThatBai = false;
  bool _dangXuLy = false;

  // George là nhân vật mặc định ai cũng có.
  // Lựa chọn này chỉ thuộc phiên demo, không thay đổi game thật.
  String? _tepNhanVatDangDung = georgeGoc.tepAnh;

  // Vật phẩm minh họa, không phải tài sản người chơi thật.
  List<VatPhamHienThi> _duLieuMau = [
    VatPhamHienThi(
      id: 'demo_kiem',
      ten: 'Kiếm hành trình',
      loai: LoaiVatPham.vuKhi,
      doHiem: DoHiemVatPham.thuong,
      nguon: NguonVatPham.game,
      bieuTuong: BieuTuongVatPham.kiem,
      laDuLieuMau: true,
      moTa: 'Thanh kiếm minh họa dành cho người thám hiểm.',
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
      moTa: 'Cây cung minh họa cho vũ khí tầm xa.',
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
      moTa: 'Áo giáp minh họa cho ô trang bị phòng thủ.',
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
      moTa: 'Vật phẩm minh họa, chưa có thao tác sử dụng.',
      thuocTinh: {'Hiệu ứng mẫu': 'Hồi 20 máu'},
    ),
  ];

  VatPhamHienThi _voiTrangBi(VatPhamHienThi vatPham, OTrangBi? o) {
    return VatPhamHienThi(
      id: vatPham.id,
      ten: vatPham.ten,
      moTa: vatPham.moTa,
      loai: vatPham.loai,
      doHiem: vatPham.doHiem,
      nguon: vatPham.nguon,
      bieuTuong: vatPham.bieuTuong,
      duongDanAnh: vatPham.duongDanAnh,
      thuocTinh: vatPham.thuocTinh,
      oDangTrangBi: o,
      laDuLieuMau: vatPham.laDuLieuMau,
      chainId: vatPham.chainId,
      diaChiHopDong: vatPham.diaChiHopDong,
      tokenId: vatPham.tokenId,
    );
  }

  Future<void> _trangBi(String itemId) {
    return _xuLyTrangBi(itemId, thao: false);
  }

  Future<void> _thaoTrangBi(String itemId) {
    return _xuLyTrangBi(itemId, thao: true);
  }

  Future<void> _xuLyTrangBi(String itemId, {required bool thao}) async {
    if (_dangXuLy) {
      throw StateError('Demo đang xử lý thao tác khác.');
    }

    final vatPham = _duLieuMau.singleWhere((vp) => vp.id == itemId);

    if (!vatPham.laDuLieuMau) {
      throw StateError('Demo chỉ xử lý vật phẩm mẫu.');
    }

    if (vatPham.loai != LoaiVatPham.vuKhi && vatPham.loai != LoaiVatPham.giap) {
      throw StateError('Vật phẩm không thuộc nhóm trang bị.');
    }

    final seThatBai = _giaLapThatBai;

    setState(() {
      _dangXuLy = true;
    });

    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      if (!mounted) {
        throw StateError('Đã đóng màn demo.');
      }

      if (seThatBai) {
        throw StateError('Lỗi nghiệp vụ được mô phỏng.');
      }

      OTrangBi? oMoi;

      if (!thao) {
        // Quy tắc minh họa, không áp dụng vào gameplay thật.
        if (vatPham.loai == LoaiVatPham.giap) {
          oMoi = OTrangBi.giap;
        } else if (vatPham.bieuTuong == BieuTuongVatPham.cung) {
          oMoi = OTrangBi.vuKhiPhu;
        } else {
          oMoi = OTrangBi.vuKhiChinh;
        }
      }

      final danhSachMoi = [
        for (final vp in _duLieuMau)
          if (vp.id == itemId)
            _voiTrangBi(vp, oMoi)
          else if (!thao && vp.oDangTrangBi == oMoi)
            _voiTrangBi(vp, null)
          else
            vp,
      ];

      setState(() {
        _duLieuMau = danhSachMoi;
      });
    } finally {
      if (mounted) {
        setState(() {
          _dangXuLy = false;
        });
      }
    }
  }

  Future<void> _chonNhanVat(String characterId) async {
    if (_dangXuLy) {
      throw StateError('Demo đang xử lý thao tác khác.');
    }

    // Demo không kết nối ví nên chỉ xác nhận George mặc định.
    if (characterId != georgeGoc.id.toString()) {
      throw StateError('Demo chưa xác nhận quyền sở hữu nhân vật cửa hàng.');
    }

    final seThatBai = _giaLapThatBai;

    setState(() {
      _dangXuLy = true;
    });

    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      if (!mounted) {
        throw StateError('Đã đóng màn demo.');
      }

      if (seThatBai) {
        throw StateError('Lỗi chọn nhân vật được mô phỏng.');
      }

      // Cập nhật sau khi mô phỏng xác nhận thành công.
      setState(() {
        _tepNhanVatDangDung = georgeGoc.tepAnh;
      });
    } finally {
      if (mounted) {
        setState(() {
          _dangXuLy = false;
        });
      }
    }
  }

  void _thuLai() {
    setState(() {
      _trangThai = TrangThaiKhoDo.dangTai;
    });
  }

  @override
  Widget build(BuildContext context) {
    final danhSachHienThi = _trangThai == TrangThaiKhoDo.daTai
        ? _duLieuMau
        : <VatPhamHienThi>[];

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  const Text(
                    'DEMO UI — không phải kho đồ thật',
                    style: TextStyle(color: MauGame.chinh),
                  ),
                  DropdownButton<TrangThaiKhoDo>(
                    value: _trangThai,
                    items: const [
                      DropdownMenuItem(
                        value: TrangThaiKhoDo.daTai,
                        child: Text('Có dữ liệu'),
                      ),
                      DropdownMenuItem(
                        value: TrangThaiKhoDo.trong,
                        child: Text('Dữ liệu trống'),
                      ),
                      DropdownMenuItem(
                        value: TrangThaiKhoDo.dangTai,
                        child: Text('Đang tải'),
                      ),
                      DropdownMenuItem(
                        value: TrangThaiKhoDo.loi,
                        child: Text('Có lỗi'),
                      ),
                    ],
                    onChanged: _dangXuLy
                        ? null
                        : (giaTri) {
                            if (giaTri == null) return;

                            setState(() {
                              _trangThai = giaTri;
                            });
                          },
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _giaLapThatBai,
                        onChanged: _dangXuLy
                            ? null
                            : (giaTri) {
                                setState(() {
                                  _giaLapThatBai = giaTri;
                                });
                              },
                      ),
                      const Text(
                        'Giả lập thao tác thất bại',
                        style: TextStyle(color: MauGame.chuPhu, fontSize: 12),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _dangXuLy || _trangThai != TrangThaiKhoDo.daTai
                        ? null
                        : () {
                            setState(() {
                              _tepNhanVatDangDung = null;
                            });
                          },
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Bỏ lựa chọn nhân vật (demo)'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _moKhoDo
                ? ManHinhKhoDo(
                    trangThaiTrangBi: _trangThai,
                    trangThaiNhanVat: _trangThai,
                    danhSachVatPham: danhSachHienThi,
                    khiTrangBi: _trangBi,
                    khiThao: _thaoTrangBi,
                    phienVi: null,
                    tepNhanVatDangDung: _tepNhanVatDangDung,
                    khiChonNhanVat: _chonNhanVat,
                    loiTrangBi: 'Thông báo lỗi mẫu của kho đồ.',
                    loiNhanVat: 'Thông báo lỗi mẫu của nhân vật.',
                    khiDong: () {
                      if (_dangXuLy) return;

                      setState(() {
                        _moKhoDo = false;
                      });
                    },
                    khiThuLaiTrangBi: _thuLai,
                    khiThuLaiNhanVat: _thuLai,
                  )
                : Center(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _moKhoDo = true;
                        });
                      },
                      child: const Text('Mở lại Kho đồ demo'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
