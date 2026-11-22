import '../man_choi.dart';
import '../kho_do/danh_sach_trang_bi.dart';

enum NhomSoTay { diaDiem, quai, trangBi }

class MucSoTay {
  const MucSoTay(this.khoa, this.nhom, this.ten, this.moTa);
  final String khoa;
  final NhomSoTay nhom;
  final String ten;
  final String moTa;
}

List<MucSoTay> danhMucSoTay(List<ManChoi> stages) => [
  for (final stage in stages)
    MucSoTay('dia_diem:${stage.id}', NhomSoTay.diaDiem, stage.ten, stage.moTa),
  const MucSoTay(
    'quai:zombie',
    NhomSoTay.quai,
    'Zombie',
    'Di chuyển chậm, tầm nhìn ngắn.',
  ),
  const MucSoTay(
    'quai:skeleton',
    NhomSoTay.quai,
    'Bộ xương',
    'Di chuyển nhanh hơn Zombie, tầm nhìn xa hơn.',
  ),
  const MucSoTay(
    'quai:thuong',
    NhomSoTay.quai,
    'Quái thường',
    'Kẻ địch cận chiến có nhiều máu hơn Zombie.',
  ),
  const MucSoTay(
    'quai:giap',
    NhomSoTay.quai,
    'Quái giáp',
    'Kẻ địch cận chiến nhanh, có nhiều máu hơn.',
  ),
  const MucSoTay(
    'quai:khong_lo',
    NhomSoTay.quai,
    'Quái khổng lồ',
    'Quái có nhiều máu, gây sát thương va chạm cao.',
  ),
  const MucSoTay(
    'quai:boss',
    NhomSoTay.quai,
    'Boss',
    'Kẻ địch đặc biệt có nhiều giai đoạn chiến đấu.',
  ),
  for (final item in danhSachTrangBiCuaHang())
    MucSoTay('trang_bi:${item.id}', NhomSoTay.trangBi, item.ten, item.moTa),
];
