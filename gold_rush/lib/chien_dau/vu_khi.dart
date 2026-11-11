import '../cau_hinh.dart';

enum LoaiVuKhi { kiem, cung }

/// Một món vũ khí của George (cận chiến hoặc tầm xa).
class VuKhi {
  final String id;
  final String ten;
  final LoaiVuKhi loai;
  final int satThuong;
  final double thoiGianHoi;
  final double tamDanh;

  const VuKhi({
    required this.id,
    required this.ten,
    required this.loai,
    required this.satThuong,
    required this.thoiGianHoi,
    required this.tamDanh,
  });

  bool get tamXa => loai == LoaiVuKhi.cung;

  static const kiem = VuKhi(
    id: 'sword_001',
    ten: 'Kiếm sắt',
    loai: LoaiVuKhi.kiem,
    satThuong: CauHinh.satThuongGoc,
    thoiGianHoi: CauHinh.thoiGianHoiDanh,
    tamDanh: CauHinh.tamDanhCanChien,
  );

  static const cung = VuKhi(
    id: 'bow_001',
    ten: 'Cung gỗ',
    loai: LoaiVuKhi.cung,
    satThuong: 8,
    thoiGianHoi: 0.6,
    tamDanh: 140,
  );

  static const tatCa = [kiem, cung];
}

