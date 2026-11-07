import 'nut_man_choi.dart';

/// Tiến trình do nguồn dữ liệu bên ngoài cung cấp.
///
/// Không tự cấp quyền mở màn hoặc lưu kết quả chơi trong widget.
class TienTrinhWorldMap {
  final Set<int> cacManDaMo;
  final Set<int> cacManHoanThanh;
  final int? manHienTai;

  const TienTrinhWorldMap._({
    required this.cacManDaMo,
    required this.cacManHoanThanh,
    required this.manHienTai,
  });

  factory TienTrinhWorldMap({
    required Iterable<int> cacManDaMo,
    required Iterable<int> cacManHoanThanh,
    int? manHienTai,
  }) {
    final daMo = Set<int>.of(cacManDaMo);
    final hoanThanh = Set<int>.of(cacManHoanThanh);

    if (daMo.any((id) => id <= 0) || hoanThanh.any((id) => id <= 0)) {
      throw ArgumentError('ID màn phải là số nguyên dương.');
    }

    if (!daMo.containsAll(hoanThanh)) {
      throw ArgumentError('Màn hoàn thành phải nằm trong danh sách màn đã mở.');
    }

    if (manHienTai != null && !daMo.contains(manHienTai)) {
      throw ArgumentError('Màn hiện tại phải nằm trong danh sách màn đã mở.');
    }

    return TienTrinhWorldMap._(
      cacManDaMo: Set<int>.unmodifiable(daMo),
      cacManHoanThanh: Set<int>.unmodifiable(hoanThanh),
      manHienTai: manHienTai,
    );
  }

  bool daMoMan(int id) => cacManDaMo.contains(id);

  TrangThaiMan trangThaiCuaMan(int id) {
    if (cacManHoanThanh.contains(id)) {
      return TrangThaiMan.hoanThanh;
    }

    if (cacManDaMo.contains(id)) {
      return TrangThaiMan.daMo;
    }

    return TrangThaiMan.chuaMo;
  }
}
