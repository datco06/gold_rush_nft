import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nut_man_choi.dart';

/// Sáu vùng địa lý chính trên World Map tương ứng với sáu màn cốt lõi.
enum LoaiVungWorldMap {
  langKhoiDau,
  khuRung,
  nuiDaMoVang,
  nuiLua,
  denCoTanTich,
  vungKhoBau,
}

/// Thông tin một vùng địa lý trên World Map.
class VungWorldMap {
  final int idManChinh;
  final LoaiVungWorldMap loai;
  final String ten;
  final String diaDanh;
  final Rect phamVi;
  final Color mauNenChinh;
  final Color mauNenPhu;
  final Color mauVien;
  final Offset viTriBienBao;

  const VungWorldMap({
    required this.idManChinh,
    required this.loai,
    required this.ten,
    required this.diaDanh,
    required this.phamVi,
    required this.mauNenChinh,
    required this.mauNenPhu,
    required this.mauVien,
    required this.viTriBienBao,
  });
}

/// Các kiểu mặt đường nối liền các vùng trên World Map.
enum LoaiDuongWorldMap {
  duongDatLang,
  cauGoSuoi,
  duongMonRung,
  duongDaNui,
  cauDaDungNham,
  duongCoDen,
  duongKhoBau,
}

/// Một tuyến đường nối trực tiếp giữa hai node màn chơi.
class DoanDuongWorldMap {
  final int tuMan;
  final int denMan;
  final List<Offset> cacDiem;
  final List<LoaiDuongWorldMap> loaiTungChang;

  const DoanDuongWorldMap({
    required this.tuMan,
    required this.denMan,
    required this.cacDiem,
    required this.loaiTungChang,
  });

  double get tongChieuDai {
    var d = 0.0;
    for (var i = 0; i < cacDiem.length - 1; i++) {
      d += (cacDiem[i + 1] - cacDiem[i]).distance;
    }
    return d;
  }

  LoaiDuongWorldMap loaiCuaChang(int chiSo) {
    if (loaiTungChang.isEmpty) return LoaiDuongWorldMap.duongDatLang;
    final idx = chiSo.clamp(0, loaiTungChang.length - 1);
    return loaiTungChang[idx];
  }

  /// Trả về bản sao đảo chiều từ `denMan` về `tuMan`.
  DoanDuongWorldMap daoChieu() => DoanDuongWorldMap(
    tuMan: denMan,
    denMan: tuMan,
    cacDiem: cacDiem.reversed.toList(growable: false),
    loaiTungChang: loaiTungChang.reversed.toList(growable: false),
  );
}

/// Lộ trình di chuyển liên tục của George qua một hoặc nhiều đoạn đường.
class LoTrinhGeorgeWorldMap {
  final int tuMan;
  final int denMan;
  final List<int> cacManDiQua;
  final List<Offset> cacDiem;

  const LoTrinhGeorgeWorldMap({
    required this.tuMan,
    required this.denMan,
    required this.cacManDiQua,
    required this.cacDiem,
  });

  double get tongChieuDai {
    var d = 0.0;
    for (var i = 0; i < cacDiem.length - 1; i++) {
      d += (cacDiem[i + 1] - cacDiem[i]).distance;
    }
    return d;
  }

  /// Nội suy vị trí và hướng di chuyển của George tại tỉ lệ `t` thuộc `[0, 1]`.
  ({Offset viTri, Offset huong}) noiSuy(double t) {
    if (cacDiem.isEmpty) {
      return (viTri: Offset.zero, huong: const Offset(0, 1));
    }
    if (cacDiem.length == 1) {
      return (viTri: cacDiem.first, huong: const Offset(0, 1));
    }
    final clamped = t.clamp(0.0, 1.0);
    final total = tongChieuDai;
    if (total <= 0.0001) {
      return (viTri: cacDiem.last, huong: const Offset(0, 1));
    }
    final mucTieu = total * clamped;
    var daQua = 0.0;
    for (var i = 0; i < cacDiem.length - 1; i++) {
      final a = cacDiem[i];
      final b = cacDiem[i + 1];
      final seg = (b - a).distance;
      if (seg <= 0.0001) continue;
      if (daQua + seg >= mucTieu || i == cacDiem.length - 2) {
        final localT = ((mucTieu - daQua) / seg).clamp(0.0, 1.0);
        return (
          viTri: Offset.lerp(a, b, localT)!,
          huong: (b - a) / seg,
        );
      }
      daQua += seg;
    }
    final truoc = cacDiem[cacDiem.length - 2];
    final cuoi = cacDiem.last;
    final delta = cuoi - truoc;
    final len = delta.distance;
    return (
      viTri: cuoi,
      huong: len > 0.0001 ? delta / len : const Offset(0, 1),
    );
  }
}

class CongTrinhWorldMap {
  final int id;
  final String anh;
  final Offset chan;
  final double chieuRong;
  const CongTrinhWorldMap(this.id, this.anh, this.chan, this.chieuRong);
}

/// Bố cục World Map mở rộng:
/// - Giữ vùng bản đồ cũ ở trung tâm với tỉ lệ gốc 1465×980 (không kéo giãn).
/// - Mở rộng thế giới lên 2930×1960 (gấp 4 lần diện tích cũ, lớn hơn viewport 3–4 lần).
/// - Phân chia 6 vùng pixel-art liên tiếp nối bằng mạng đường mòn uốn lượn tự nhiên.
class BoCucWorldMap {
  BoCucWorldMap._();

  static const kichThuocCu = Size(1465, 980);
  static const kichThuoc = Size(2930, 1960);
  static const vungBanDoCu = Rect.fromLTWH(732.5, 490, 1465, 980);

  /// Sáu vùng địa lý tương ứng với màn 1–6.
  static const cacVung = <VungWorldMap>[
    VungWorldMap(
      idManChinh: 1,
      loai: LoaiVungWorldMap.langKhoiDau,
      ten: 'Làng khởi đầu',
      diaDanh: 'Thảo nguyên & Cối xay gió',
      phamVi: Rect.fromLTWH(80, 820, 920, 1040),
      mauNenChinh: Color(0xFF476E40),
      mauNenPhu: Color(0xFF5B844E),
      mauVien: Color(0xFFA8C67C),
      viTriBienBao: Offset(560, 860),
    ),
    VungWorldMap(
      idManChinh: 2,
      loai: LoaiVungWorldMap.khuRung,
      ten: 'Khu rừng',
      diaDanh: 'Rừng Cổ Thụ & Suối Ngàn',
      phamVi: Rect.fromLTWH(80, 90, 940, 710),
      mauNenChinh: Color(0xFF2B5335),
      mauNenPhu: Color(0xFF396944),
      mauVien: Color(0xFF7CB37D),
      viTriBienBao: Offset(580, 325),
    ),
    VungWorldMap(
      idManChinh: 3,
      loai: LoaiVungWorldMap.nuiDaMoVang,
      ten: 'Núi đá / Mỏ vàng',
      diaDanh: 'Đèo Đá Xám & Hầm Mỏ',
      phamVi: Rect.fromLTWH(1040, 90, 860, 730),
      mauNenChinh: Color(0xFF54524C),
      mauNenPhu: Color(0xFF6B655B),
      mauVien: Color(0xFFD2B36B),
      viTriBienBao: Offset(1440, 235),
    ),
    VungWorldMap(
      idManChinh: 4,
      loai: LoaiVungWorldMap.nuiLua,
      ten: 'Núi lửa',
      diaDanh: 'Hỏa Sơn & Khe Dung Nham',
      phamVi: Rect.fromLTWH(1920, 90, 930, 810),
      mauNenChinh: Color(0xFF432622),
      mauNenPhu: Color(0xFF5C3128),
      mauVien: Color(0xFFFF7A33),
      viTriBienBao: Offset(2340, 355),
    ),
    VungWorldMap(
      idManChinh: 5,
      loai: LoaiVungWorldMap.denCoTanTich,
      ten: 'Đền cổ / Tàn tích',
      diaDanh: 'Thung Lũng Cổ Ngữ',
      phamVi: Rect.fromLTWH(1920, 920, 930, 940),
      mauNenChinh: Color(0xFF3A4952),
      mauNenPhu: Color(0xFF4D5F69),
      mauVien: Color(0xFF7CE0D3),
      viTriBienBao: Offset(2360, 1065),
    ),
    VungWorldMap(
      idManChinh: 6,
      loai: LoaiVungWorldMap.vungKhoBau,
      ten: 'Vùng kho báu',
      diaDanh: 'Đỉnh Kho Báu Hoàng Kim',
      phamVi: Rect.fromLTWH(1020, 920, 880, 940),
      mauNenChinh: Color(0xFF665329),
      mauNenPhu: Color(0xFF826A34),
      mauVien: Color(0xFFFFD966),
      viTriBienBao: Offset(1460, 1150),
    ),
  ];

  /// Tâm thực của 20 khoảng đất trống trong bức `terrain_khu_nha_v3.png` (hệ tọa độ 1465×980).
  static const cacTamSanGoc1465 = <Offset>[
    Offset(676, 472), // 1: Quảng trường bát giác đá trung tâm
    Offset(530, 594), // 2
    Offset(745, 637), // 3
    Offset(888, 538), // 4
    Offset(340, 273), // 5: Đài đá tròn lớn có bậc thang
    Offset(1155, 381), // 6
    Offset(1390, 203), // 7
    Offset(230, 718), // 8
    Offset(140, 483), // 9
    Offset(480, 428), // 10
    Offset(660, 273), // 11
    Offset(860, 273), // 12
    Offset(1120, 568), // 13
    Offset(1390, 578), // 14
    Offset(1360, 808), // 15
    Offset(1150, 898), // 16
    Offset(930, 868), // 17
    Offset(710, 818), // 18
    Offset(490, 878), // 19
    Offset(100, 858), // 20
  ];

  /// 20 công trình đặt chính giữa các khoảng đất trống thực tế trên bản đồ 2930×1960:
  /// - Màn 1–6 là 6 cứ điểm trung tâm của 6 vùng chính.
  /// - Màn 7–20 đặt cân đối chính giữa các khoảng đất trống ở từng khu vực.
  static const congTrinh = <CongTrinhWorldMap>[
    // 6 màn chính tương ứng 6 vùng (đặt chính giữa khoảng đất trống của từng vùng):
    CongTrinhWorldMap(1, 'lau_dai.png', Offset(590.5, 1006), 148),
    CongTrinhWorldMap(2, 'nha_quan_tro_v3.png', Offset(345.0, 272), 98),
    CongTrinhWorldMap(3, 'nha_tho_ren_v3.png', Offset(1392.5, 228), 98),
    CongTrinhWorldMap(4, 'nha_thu_vien_v3.png', Offset(2272.5, 712), 98),
    CongTrinhWorldMap(5, 'nha_don_gac_v3.png', Offset(2302.5, 1318), 118),
    CongTrinhWorldMap(6, 'nha_kho_mo_v4.png', Offset(1442.5, 1328), 110),
    // 14 địa điểm mở rộng đặt chính giữa các khoảng đất trống:
    CongTrinhWorldMap(7, 'nha_tho_ren_v3.png', Offset(1412.5, 968), 134),
    CongTrinhWorldMap(8, 'nha_quan_tro_dai_v4.png', Offset(242.5, 1402), 116),
    CongTrinhWorldMap(9, 'nha_don_gac_v3.png', Offset(345.0, 762), 106),
    CongTrinhWorldMap(10, 'nha_tho_san_v4.png', Offset(1120.0, 762), 104),
    CongTrinhWorldMap(11, 'nha_thu_vien_v3.png', Offset(1120.0, 272), 104),
    CongTrinhWorldMap(12, 'nha_coi_nuoc_v4.png', Offset(1592.5, 228), 106),
    CongTrinhWorldMap(13, 'nha_gia_kim_v4.png', Offset(2122.5, 712), 104),
    CongTrinhWorldMap(14, 'nha_phao_dai_v4.png', Offset(2507.5, 890), 114),
    CongTrinhWorldMap(15, 'nha_dinh_thu_v4.png', Offset(2512.5, 1562), 112),
    CongTrinhWorldMap(16, 'nha_quan_tro_v3.png', Offset(2092.5, 1662), 104),
    CongTrinhWorldMap(17, 'nha_coi_gio_v4.png', Offset(1662.5, 1592), 102),
    CongTrinhWorldMap(18, 'nha_nha_kinh_v4.png', Offset(1222.5, 1595), 106),
    CongTrinhWorldMap(19, 'nha_phap_su_v4.png', Offset(832.5, 1605), 64),
    CongTrinhWorldMap(20, 'nha_thanh_tri_v4.png', Offset(242.5, 1588), 116),
  ];

  static final viTriMan = Map<int, Offset>.unmodifiable({
    for (final c in congTrinh) c.id: c.chan + const Offset(0, 14),
  });

  /// Lộ trình di chuyển giữa các màn chơi (phục vụ tìm đường cho George).
  static final cacTuyenDuong = List<DoanDuongWorldMap>.unmodifiable([
    DoanDuongWorldMap(
      tuMan: 1,
      denMan: 2,
      cacDiem: [
        viTriMan[1]!,
        const Offset(490, 880),
        const Offset(420, 620),
        const Offset(392.5, 420),
        viTriMan[2]!,
      ],
      loaiTungChang: const [
        LoaiDuongWorldMap.duongDatLang,
        LoaiDuongWorldMap.duongMonRung,
        LoaiDuongWorldMap.duongMonRung,
        LoaiDuongWorldMap.duongMonRung,
      ],
    ),
    DoanDuongWorldMap(
      tuMan: 2,
      denMan: 3,
      cacDiem: [
        viTriMan[2]!,
        const Offset(730, 255),
        const Offset(1072.5, 255),
        viTriMan[3]!,
      ],
      loaiTungChang: const [
        LoaiDuongWorldMap.duongMonRung,
        LoaiDuongWorldMap.duongDaNui,
        LoaiDuongWorldMap.duongDaNui,
      ],
    ),
    DoanDuongWorldMap(
      tuMan: 3,
      denMan: 4,
      cacDiem: [
        viTriMan[3]!,
        const Offset(1592.5, 255),
        const Offset(1950, 480),
        viTriMan[4]!,
      ],
      loaiTungChang: const [
        LoaiDuongWorldMap.duongDaNui,
        LoaiDuongWorldMap.duongDaNui,
        LoaiDuongWorldMap.duongDaNui,
      ],
    ),
    DoanDuongWorldMap(
      tuMan: 4,
      denMan: 5,
      cacDiem: [
        viTriMan[4]!,
        const Offset(2350, 980),
        viTriMan[5]!,
      ],
      loaiTungChang: const [
        LoaiDuongWorldMap.duongDaNui,
        LoaiDuongWorldMap.duongCoDen,
      ],
    ),
    DoanDuongWorldMap(
      tuMan: 5,
      denMan: 6,
      cacDiem: [
        viTriMan[5]!,
        const Offset(1880, 1340),
        viTriMan[6]!,
      ],
      loaiTungChang: const [
        LoaiDuongWorldMap.duongCoDen,
        LoaiDuongWorldMap.duongKhoBau,
      ],
    ),
    DoanDuongWorldMap(
      tuMan: 1,
      denMan: 6,
      cacDiem: [
        viTriMan[1]!,
        const Offset(1020, 1220),
        viTriMan[6]!,
      ],
      loaiTungChang: const [
        LoaiDuongWorldMap.duongDatLang,
        LoaiDuongWorldMap.duongKhoBau,
      ],
    ),
    DoanDuongWorldMap(
      tuMan: 3,
      denMan: 7,
      cacDiem: [viTriMan[3]!, viTriMan[7]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDaNui],
    ),
    DoanDuongWorldMap(
      tuMan: 7,
      denMan: 10,
      cacDiem: [viTriMan[7]!, viTriMan[10]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongMonRung],
    ),
    DoanDuongWorldMap(
      tuMan: 2,
      denMan: 10,
      cacDiem: [viTriMan[2]!, viTriMan[10]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongMonRung],
    ),
    DoanDuongWorldMap(
      tuMan: 2,
      denMan: 9,
      cacDiem: [viTriMan[2]!, viTriMan[9]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongMonRung],
    ),
    DoanDuongWorldMap(
      tuMan: 1,
      denMan: 8,
      cacDiem: [viTriMan[1]!, viTriMan[8]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDatLang],
    ),
    DoanDuongWorldMap(
      tuMan: 8,
      denMan: 20,
      cacDiem: [viTriMan[8]!, viTriMan[20]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDatLang],
    ),
    DoanDuongWorldMap(
      tuMan: 20,
      denMan: 19,
      cacDiem: [viTriMan[20]!, viTriMan[19]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDatLang],
    ),
    DoanDuongWorldMap(
      tuMan: 19,
      denMan: 18,
      cacDiem: [viTriMan[19]!, viTriMan[18]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongKhoBau],
    ),
    DoanDuongWorldMap(
      tuMan: 6,
      denMan: 18,
      cacDiem: [viTriMan[6]!, viTriMan[18]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongKhoBau],
    ),
    DoanDuongWorldMap(
      tuMan: 18,
      denMan: 17,
      cacDiem: [viTriMan[18]!, viTriMan[17]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongKhoBau],
    ),
    DoanDuongWorldMap(
      tuMan: 17,
      denMan: 16,
      cacDiem: [viTriMan[17]!, viTriMan[16]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongCoDen],
    ),
    DoanDuongWorldMap(
      tuMan: 16,
      denMan: 15,
      cacDiem: [viTriMan[16]!, viTriMan[15]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongCoDen],
    ),
    DoanDuongWorldMap(
      tuMan: 5,
      denMan: 15,
      cacDiem: [viTriMan[5]!, viTriMan[15]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongCoDen],
    ),
    DoanDuongWorldMap(
      tuMan: 4,
      denMan: 14,
      cacDiem: [viTriMan[4]!, viTriMan[14]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDaNui],
    ),
    DoanDuongWorldMap(
      tuMan: 14,
      denMan: 5,
      cacDiem: [viTriMan[14]!, viTriMan[5]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongCoDen],
    ),
    DoanDuongWorldMap(
      tuMan: 4,
      denMan: 13,
      cacDiem: [viTriMan[4]!, viTriMan[13]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDaNui],
    ),
    DoanDuongWorldMap(
      tuMan: 3,
      denMan: 12,
      cacDiem: [viTriMan[3]!, viTriMan[12]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDaNui],
    ),
    DoanDuongWorldMap(
      tuMan: 2,
      denMan: 11,
      cacDiem: [viTriMan[2]!, viTriMan[11]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDaNui],
    ),
    DoanDuongWorldMap(
      tuMan: 11,
      denMan: 3,
      cacDiem: [viTriMan[11]!, viTriMan[3]!],
      loaiTungChang: const [LoaiDuongWorldMap.duongDaNui],
    ),
  ]);

  /// Trả về vùng địa lý tương ứng với một ID màn chơi.
  static VungWorldMap vungCuaMan(int idMan) {
    for (final v in cacVung) {
      if (v.idManChinh == idMan) return v;
    }
    final pos = viTriMan[idMan];
    if (pos != null) {
      for (final v in cacVung) {
        if (v.phamVi.contains(pos)) return v;
      }
    }
    return cacVung[(idMan - 1).clamp(0, cacVung.length - 1)];
  }

  /// Tìm lộ trình đường đi ngắn nhất cho George giữa hai màn ĐÃ MỞ.
  static LoTrinhGeorgeWorldMap? timLoTrinh(
    int tuMan,
    int denMan,
    Map<int, TrangThaiMan> trangThaiCacMan,
  ) {
    bool daMo(int id) {
      final st = trangThaiCacMan[id];
      return st == TrangThaiMan.daMo || st == TrangThaiMan.hoanThanh;
    }

    if (!daMo(tuMan) || !daMo(denMan)) return null;
    if (!viTriMan.containsKey(tuMan) || !viTriMan.containsKey(denMan)) {
      return null;
    }
    if (tuMan == denMan) {
      return LoTrinhGeorgeWorldMap(
        tuMan: tuMan,
        denMan: denMan,
        cacManDiQua: [tuMan],
        cacDiem: [viTriMan[tuMan]!],
      );
    }

    final hangDoi = <int>[tuMan];
    final daTham = <int>{tuMan};
    final cha = <int, ({int tu, DoanDuongWorldMap doan})>{};

    while (hangDoi.isNotEmpty) {
      final hienTai = hangDoi.removeAt(0);
      if (hienTai == denMan) break;

      for (final t in cacTuyenDuong) {
        DoanDuongWorldMap? canh;
        if (t.tuMan == hienTai && daMo(t.denMan)) {
          canh = t;
        } else if (t.denMan == hienTai && daMo(t.tuMan)) {
          canh = t.daoChieu();
        }
        if (canh == null || daTham.contains(canh.denMan)) continue;
        daTham.add(canh.denMan);
        cha[canh.denMan] = (tu: hienTai, doan: canh);
        hangDoi.add(canh.denMan);
      }
    }

    if (!cha.containsKey(denMan)) return null;

    final cacDoan = <DoanDuongWorldMap>[];
    final cacNode = <int>[denMan];
    var cur = denMan;
    while (cur != tuMan) {
      final buoc = cha[cur]!;
      cacDoan.add(buoc.doan);
      cur = buoc.tu;
      cacNode.add(cur);
    }

    final cacDoanXuoi = cacDoan.reversed.toList();
    final cacNodeXuoi = cacNode.reversed.toList();
    final cacDiem = <Offset>[];
    for (var i = 0; i < cacDoanXuoi.length; i++) {
      final d = cacDoanXuoi[i].cacDiem;
      if (i == 0) {
        cacDiem.addAll(d);
      } else {
        cacDiem.addAll(d.skip(1));
      }
    }

    return LoTrinhGeorgeWorldMap(
      tuMan: tuMan,
      denMan: denMan,
      cacManDiQua: cacNodeXuoi,
      cacDiem: List.unmodifiable(cacDiem),
    );
  }

  /// Kiểm tra một điểm tọa độ có nằm trên mạng đường mòn hay không.
  static bool diemNamTrenDuongDi(Offset diem, {double saiSo = 20.0}) {
    final maxDistSq = saiSo * saiSo;
    for (final tuyen in cacTuyenDuong) {
      for (var i = 0; i < tuyen.cacDiem.length - 1; i++) {
        final a = tuyen.cacDiem[i];
        final b = tuyen.cacDiem[i + 1];
        if (_khoangCachBinhPhuongDenDoanThang(diem, a, b) <= maxDistSq) {
          return true;
        }
      }
    }
    return false;
  }

  static double _khoangCachBinhPhuongDenDoanThang(
    Offset p,
    Offset a,
    Offset b,
  ) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq <= 0.0001) return (p - a).distanceSquared;
    final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    final proj = Offset.lerp(a, b, t.clamp(0.0, 1.0))!;
    return (p - proj).distanceSquared;
  }

  /// Kẹp vector dịch chuyển camera để khung nhìn không đi ra ngoài phạm vi bản đồ.
  static Offset gioiHanDichChuyenCamera({
    required double tiLe,
    required Offset dichChuyen,
    required Size kichThuocKhung,
    double le = 0.0,
  }) {
    final mapW = kichThuoc.width * tiLe;
    final mapH = kichThuoc.height * tiLe;

    final double x;
    if (mapW <= kichThuocKhung.width) {
      final tamX = (kichThuocKhung.width - mapW) / 2;
      x = dichChuyen.dx.clamp(tamX - le, tamX + le).toDouble();
    } else {
      x = dichChuyen.dx
          .clamp(kichThuocKhung.width - mapW - le, le)
          .toDouble();
    }

    final double y;
    if (mapH <= kichThuocKhung.height) {
      final tamY = (kichThuocKhung.height - mapH) / 2;
      y = dichChuyen.dy.clamp(tamY - le, tamY + le).toDouble();
    } else {
      y = dichChuyen.dy
          .clamp(kichThuocKhung.height - mapH - le, le)
          .toDouble();
    }

    return Offset(x, y);
  }

  /// Tính dịch chuyển camera để ưu tiên hiển thị `diemTheGioi` mà vẫn nằm trong giới hạn bản đồ.
  static Offset tinhDichChuyenTapTrungDiem({
    required Offset diemTheGioi,
    required double tiLe,
    required Size kichThuocKhung,
  }) {
    final lyTuong = Offset(
      kichThuocKhung.width / 2 - diemTheGioi.dx * tiLe,
      kichThuocKhung.height / 2 - diemTheGioi.dy * tiLe,
    );
    return gioiHanDichChuyenCamera(
      tiLe: tiLe,
      dichChuyen: lyTuong,
      kichThuocKhung: kichThuocKhung,
    );
  }
}

/// Chỉ nạp lâu đài gốc, terrain mới và 15 mẫu nhà. Các PNG trang trí cũ
/// không còn được tham chiếu/render nhưng được giữ nguyên trên đĩa.
class TaiNguyenWorldMap {
  TaiNguyenWorldMap._();

  static const thuMuc = 'assets/images/world_map/';
  static const tenAnh = <String>[
    'lau_dai.png',
    'terrain_khu_nha_v3.png',
    'nha_tho_ren_v3.png',
    'nha_quan_tro_v3.png',
    'nha_thu_vien_v3.png',
    'nha_don_gac_v3.png',
    'nha_kho_mo_v4.png',
    'nha_quan_tro_dai_v4.png',
    'nha_tho_san_v4.png',
    'nha_coi_nuoc_v4.png',
    'nha_gia_kim_v4.png',
    'nha_phao_dai_v4.png',
    'nha_dinh_thu_v4.png',
    'nha_coi_gio_v4.png',
    'nha_nha_kinh_v4.png',
    'nha_phap_su_v4.png',
    'nha_thanh_tri_v4.png',
  ];

  static const khungNguon = <String, Rect>{
    'nha_kho_mo_v4.png': Rect.fromLTRB(
      17 / 1536,
      131 / 1024,
      1519 / 1536,
      896 / 1024,
    ),
    'nha_quan_tro_dai_v4.png': Rect.fromLTRB(
      10 / 1774,
      15 / 887,
      1766 / 1774,
      871 / 887,
    ),
    'nha_tho_san_v4.png': Rect.fromLTRB(
      7 / 1301,
      8 / 1209,
      1294 / 1301,
      1177 / 1209,
    ),
    'nha_coi_nuoc_v4.png': Rect.fromLTRB(
      23 / 1312,
      7 / 1199,
      1290 / 1312,
      1179 / 1199,
    ),
    'nha_gia_kim_v4.png': Rect.fromLTRB(
      116 / 1312,
      3 / 1199,
      1231 / 1312,
      1181 / 1199,
    ),
    'nha_phao_dai_v4.png': Rect.fromLTRB(
      119 / 1536,
      4 / 1024,
      1393 / 1536,
      1009 / 1024,
    ),
    'nha_dinh_thu_v4.png': Rect.fromLTRB(
      55 / 1312,
      5 / 1199,
      1255 / 1312,
      1171 / 1199,
    ),
    'nha_coi_gio_v4.png': Rect.fromLTRB(
      105 / 1218,
      9 / 1292,
      1071 / 1218,
      1271 / 1292,
    ),
    'nha_nha_kinh_v4.png': Rect.fromLTRB(
      91 / 1254,
      3 / 1254,
      1140 / 1254,
      1240 / 1254,
    ),
    'nha_phap_su_v4.png': Rect.fromLTRB(
      215 / 1024,
      5 / 1536,
      804 / 1024,
      1514 / 1536,
    ),
    'nha_thanh_tri_v4.png': Rect.fromLTRB(
      1 / 1312,
      1 / 1199,
      1310 / 1312,
      1183 / 1199,
    ),
  };

  static Future<Map<String, ui.Image>>? _boNho;
  static Map<String, ui.Image>? _anhDaNap;
  static final Map<String, Future<ui.Image?>> _boNhoGeorge = {};
  static final Map<String, ui.Image> _anhGeorgeDaNap = {};

  static Map<String, ui.Image>? get anhDaNap => _anhDaNap;
  static ui.Image? anhGeorgeDaNap([String tep = 'george.png']) =>
      _anhGeorgeDaNap[tep];

  static Future<Map<String, ui.Image>> nap() => _boNho ??= _napTatCa();

  static Future<ui.Image?> napAnhGeorge([String tep = 'george.png']) {
    return _boNhoGeorge[tep] ??= _napMotAnhGeorge(tep);
  }

  static Future<ui.Image?> _napMotAnhGeorge(String tep) async {
    try {
      final data = await rootBundle.load('assets/images/$tep');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        final image = (await codec.getNextFrame()).image;
        _anhGeorgeDaNap[tep] = image;
        return image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, ui.Image>> _napTatCa() async {
    final daNap = <String, ui.Image>{};
    try {
      for (final ten in tenAnh) {
        final data = await rootBundle.load('$thuMuc$ten');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          targetWidth: ten.startsWith('nha_') ? 256 : null,
        );
        try {
          daNap[ten] = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }
      return _anhDaNap = Map.unmodifiable(daNap);
    } catch (_) {
      for (final anh in daNap.values) {
        anh.dispose();
      }
      _boNho = null;
      rethrow;
    }
  }
}

/// Lớp vẽ nền thế giới pixel-art liền mạch, 6 vùng địa hình, mạng đường mòn
/// và 20 công trình.
class CanhQuanWorldMap extends CustomPainter {
  final Map<String, ui.Image> anh;
  final Map<int, TrangThaiMan> trangThaiCacMan;

  CanhQuanWorldMap(this.anh, {required this.trangThaiCacMan});

  static const _maTranDonVi = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  static const _maTranRung = <double>[
    0.80, 0.05, 0.00, 0, -6,
    0.04, 1.08, 0.04, 0, 5,
    0.02, 0.10, 0.94, 0, 3,
    0, 0, 0, 1, 0,
  ];

  static const _maTranLang = <double>[
    1.04, 0.05, 0.00, 0, 5,
    0.04, 1.04, 0.02, 0, 4,
    0.00, 0.02, 0.90, 0, -3,
    0, 0, 0, 1, 0,
  ];

  static const _maTranMoVang = <double>[
    0.96, 0.16, 0.06, 0, 8,
    0.14, 0.86, 0.08, 0, 3,
    0.06, 0.12, 0.76, 0, -4,
    0, 0, 0, 1, 0,
  ];

  static const _maTranNuiLua = <double>[
    0.72, 0.22, 0.08, 0, 12,
    0.14, 0.38, 0.06, 0, -8,
    0.08, 0.12, 0.34, 0, -12,
    0, 0, 0, 1, 0,
  ];

  static const _maTranDenCo = <double>[
    0.72, 0.14, 0.12, 0, -2,
    0.08, 0.88, 0.16, 0, 4,
    0.10, 0.22, 0.90, 0, 8,
    0, 0, 0, 1, 0,
  ];

  static const _maTranKhoBau = <double>[
    1.06, 0.16, 0.02, 0, 12,
    0.10, 0.96, 0.04, 0, 6,
    0.02, 0.08, 0.72, 0, -8,
    0, 0, 0, 1, 0,
  ];

  static ColorFilter _noiSuyLocMau(List<double> dich, double t) {
    final k = t.clamp(0.0, 1.0);
    return ColorFilter.matrix([
      for (var i = 0; i < 20; i++)
        _maTranDonVi[i] * (1.0 - k) + dich[i] * k,
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final terrain = anh['terrain_khu_nha_v3.png'];

    // 1. Vẽ nền địa hình pixel-art liền mạch toàn thế giới 2930×1960.
    _veNenDiaHinhLienMach(canvas, size, terrain);

    // 2. Giữ nguyên 20 khoảng đất trống có đặt nhà, chỉ lấp các khoảng đất dư không có nhà.
    if (terrain != null) {
      _veHoaTronTuNhienVaLapKhoangSan(canvas, terrain);
    }

    // 3. Vẽ 20 công trình đặt chính giữa khoảng đất trống theo thứ tự chiều sâu Y.
    final sorted = [...BoCucWorldMap.congTrinh]
      ..sort((a, b) => a.chan.dy.compareTo(b.chan.dy));
    for (final c in sorted) {
      if (!trangThaiCacMan.containsKey(c.id)) continue;
      _veCongTrinh(canvas, c, trangThaiCacMan[c.id] == TrangThaiMan.chuaMo);
    }

    // 4. Viền khung bản đồ cổ điển bao ngoài thế giới.
    _veKhungVienTheGioi(canvas, size);

    canvas.restore();
  }

  Rect _khungNguonTerrain(
    ui.Image terrain,
    double left,
    double top,
    double width,
    double height,
  ) {
    final sx = terrain.width / 1605.0;
    final sy = terrain.height / 980.0;
    return Rect.fromLTWH(left * sx, top * sy, width * sx, height * sy);
  }

  /// Vẽ toàn bộ lưới 3×3 đối xứng gương tỉ lệ 1:1 quanh `vungBanDoCu`.
  /// Nhờ đối xứng gương qua 4 cạnh (x = 732.5, x = 2197.5, y = 490, y = 1470),
  /// mọi pixel cây cối, vách đá, bờ sông ở biên đều khớp 100% không có vết cắt.
  void _veLuoiGuongTerrain11(
    Canvas canvas,
    ui.Image terrain, {
    ColorFilter? locMau,
    Rect? gioiHanVung,
  }) {
    final srcFull = _khungNguonTerrain(terrain, 70, 0, 1465, 980);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (locMau != null) {
      paint.colorFilter = locMau;
    }

    const w = 1465.0;
    const h = 980.0;
    const cLeft = 732.5;
    const cTop = 490.0;

    for (var gy = -1; gy <= 1; gy++) {
      for (var gx = -1; gx <= 1; gx++) {
        final cellRect = Rect.fromLTWH(cLeft + gx * w, cTop + gy * h, w, h);
        if (gioiHanVung != null && !cellRect.overlaps(gioiHanVung)) continue;

        final cx = cellRect.center.dx;
        final cy = cellRect.center.dy;
        final fx = gx == 0 ? 1.0 : -1.0;
        final fy = gy == 0 ? 1.0 : -1.0;

        canvas.save();
        canvas.translate(cx, cy);
        canvas.scale(fx, fy);
        canvas.drawImageRect(
          terrain,
          srcFull,
          const Rect.fromLTWH(-w / 2, -h / 2, w, h),
          paint,
        );
        canvas.restore();
      }
    }
  }

  /// Tạo đường biên hữu cơ uốn lượn quanh một vùng địa lý để chuyển màu mượt mà,
  /// tuyệt đối không tạo cạnh thẳng.
  Path _taoMatNaVungHuuCo(
    Offset tam,
    double banKinhX,
    double banKinhY, {
    int hatGiong = 1,
  }) {
    final path = Path();
    const soDiem = 16;
    final cacDiem = <Offset>[];
    for (var i = 0; i < soDiem; i++) {
      final goc = i * (math.pi * 2 / soDiem);
      final song1 = math.sin(goc * 3 + hatGiong * 1.7) * 0.08;
      final song2 = math.cos(goc * 5 - hatGiong * 0.9) * 0.05;
      final heSo = 1.0 + song1 + song2;
      cacDiem.add(
        Offset(
          tam.dx + math.cos(goc) * banKinhX * heSo,
          tam.dy + math.sin(goc) * banKinhY * heSo,
        ),
      );
    }
    final dau = Offset.lerp(cacDiem.last, cacDiem.first, 0.5)!;
    path.moveTo(dau.dx, dau.dy);
    for (var i = 0; i < soDiem; i++) {
      final p0 = cacDiem[i];
      final p1 = cacDiem[(i + 1) % soDiem];
      final giua = Offset.lerp(p0, p1, 0.5)!;
      path.quadraticBezierTo(p0.dx, p0.dy, giua.dx, giua.dy);
    }
    path.close();
    return path;
  }

  void _veVungChuyenSacMem(
    Canvas canvas,
    ui.Image terrain, {
    required Offset tam,
    required double rx,
    required double ry,
    required List<double> maTranDich,
    required int hatGiong,
  }) {
    // 5 lớp mặt nạ hữu cơ đồng tâm với cường độ màu tăng dần từ biên vào tâm (0.2 -> 1.0)
    // giúp ranh giới giữa các vùng hòa trộn mềm mại như tranh vẽ tay.
    for (final (buoc, t) in const [
      (1.16, 0.22),
      (1.04, 0.44),
      (0.92, 0.66),
      (0.80, 0.85),
      (0.68, 1.00),
    ]) {
      final rX = rx * buoc;
      final rY = ry * buoc;
      final matNa = _taoMatNaVungHuuCo(tam, rX, rY, hatGiong: hatGiong);
      canvas.save();
      canvas.clipPath(matNa);
      _veLuoiGuongTerrain11(
        canvas,
        terrain,
        locMau: _noiSuyLocMau(maTranDich, t),
        gioiHanVung: Rect.fromCenter(
          center: tam,
          width: rX * 2.3,
          height: rY * 2.3,
        ),
      );
      canvas.restore();
    }
  }

  void _veNenDiaHinhLienMach(Canvas canvas, Size size, ui.Image? terrain) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF233824),
    );
    if (terrain == null) return;

    // 1. Lớp địa hình gốc liền mạch 100% trên toàn bản đồ 2930×1960.
    _veLuoiGuongTerrain11(canvas, terrain);

    // 2. Chuyển sắc hữu cơ mềm mại cho 6 vùng địa lý xung quanh:
    // Vùng 2 — Khu rừng cổ thụ (Tây Bắc):
    _veVungChuyenSacMem(
      canvas,
      terrain,
      tam: const Offset(420, 360),
      rx: 520,
      ry: 420,
      maTranDich: _maTranRung,
      hatGiong: 2,
    );
    // Vùng 1 — Làng khởi đầu & Thảo nguyên (Tây Nam):
    _veVungChuyenSacMem(
      canvas,
      terrain,
      tam: const Offset(430, 1420),
      rx: 520,
      ry: 520,
      maTranDich: _maTranLang,
      hatGiong: 1,
    );
    // Vùng 3 — Núi đá / Mỏ vàng (Bắc):
    _veVungChuyenSacMem(
      canvas,
      terrain,
      tam: const Offset(1460, 220),
      rx: 520,
      ry: 310,
      maTranDich: _maTranMoVang,
      hatGiong: 3,
    );
    // Vùng 4 — Núi lửa & Đá Bazan (Đông Bắc):
    _veVungChuyenSacMem(
      canvas,
      terrain,
      tam: const Offset(2460, 420),
      rx: 560,
      ry: 480,
      maTranDich: _maTranNuiLua,
      hatGiong: 4,
    );
    // Vùng 5 — Đền cổ / Tàn tích (Đông Nam):
    _veVungChuyenSacMem(
      canvas,
      terrain,
      tam: const Offset(2460, 1480),
      rx: 540,
      ry: 520,
      maTranDich: _maTranDenCo,
      hatGiong: 5,
    );
    // Vùng 6 — Vùng kho báu Hoàng Kim (Nam):
    _veVungChuyenSacMem(
      canvas,
      terrain,
      tam: const Offset(1460, 1680),
      rx: 520,
      ry: 360,
      maTranDich: _maTranKhoBau,
      hatGiong: 6,
    );
  }

  void _veManhTerrainHuuCo(
    Canvas canvas,
    ui.Image terrain, {
    required Rect nguon1605,
    required Offset tamDich,
    List<double>? maTranMau,
    int hatGiong = 1,
  }) {
    final w = nguon1605.width;
    final h = nguon1605.height;
    final dst = Rect.fromCenter(center: tamDich, width: w, height: h);
    final matNa = _taoMatNaVungHuuCo(
      tamDich,
      w * 0.46,
      h * 0.46,
      hatGiong: hatGiong,
    );
    canvas.save();
    canvas.clipPath(matNa);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (maTranMau != null) {
      paint.colorFilter = ColorFilter.matrix(maTranMau);
    }
    canvas.drawImageRect(
      terrain,
      _khungNguonTerrain(
        terrain,
        nguon1605.left,
        nguon1605.top,
        nguon1605.width,
        nguon1605.height,
      ),
      dst,
      paint,
    );
    canvas.restore();
  }

  List<double>? _maTranTheoToaDo(Offset p) {
    if (p.dx < 950 && p.dy < 820) return _maTranRung;
    if (p.dx < 950 && p.dy >= 820) return _maTranLang;
    if (p.dx >= 950 && p.dx < 1920 && p.dy < 620) return _maTranMoVang;
    if (p.dx >= 1920 && p.dy < 920) return _maTranNuiLua;
    if (p.dx >= 1920 && p.dy >= 920) return _maTranDenCo;
    if (p.dx >= 950 && p.dx < 1920 && p.dy >= 1220) return _maTranKhoBau;
    return null;
  }

  /// Lấp các khoảng đất trống dư (không có ngôi nhà nào trong 20 màn đặt lên)
  /// và giữ nguyên vẹn 100% 20 khoảng đất trống nơi đặt 20 ngôi nhà.
  void _veHoaTronTuNhienVaLapKhoangSan(Canvas canvas, ui.Image terrain) {
    const manhTanCay = Rect.fromLTWH(85, 35, 190, 145);
    const manhThamCo = Rect.fromLTWH(90, 535, 185, 140);
    const manhVachDa = Rect.fromLTWH(760, 15, 175, 125);

    var hat = 10;
    for (var gy = -1; gy <= 1; gy++) {
      for (var gx = -1; gx <= 1; gx++) {
        for (final (idx, goc) in BoCucWorldMap.cacTamSanGoc1465.indexed) {
          final cx = switch (gx) {
            -1 => 732.5 - goc.dx,
            0 => 732.5 + goc.dx,
            _ => 3662.5 - goc.dx,
          };
          final cy = switch (gy) {
            -1 => 490.0 - goc.dy,
            0 => 490.0 + goc.dy,
            _ => 2450.0 - goc.dy,
          };
          final san = Offset(cx, cy);
          if (!(Offset.zero & BoCucWorldMap.kichThuoc)
              .inflate(80)
              .contains(san)) {
            continue;
          }

          // Nếu khoảng đất trống này có đặt 1 trong 20 ngôi nhà thì giữ nguyên tuyệt đối.
          final coNha = BoCucWorldMap.congTrinh.any(
            (c) => (c.chan - const Offset(0, 22) - san).distance < 78,
          );
          if (coNha) continue;

          // Không đè lên khoảng đất trống của ngôi nhà lân cận.
          final ganNha = BoCucWorldMap.congTrinh.any(
            (c) => (c.chan - const Offset(0, 22) - san).distance < 115,
          );
          if (ganNha) continue;

          final laVungNui = san.dx > 1550 && san.dy < 900;
          _veManhTerrainHuuCo(
            canvas,
            terrain,
            nguon1605: laVungNui
                ? manhVachDa
                : (idx.isEven ? manhTanCay : manhThamCo),
            tamDich: san,
            maTranMau: _maTranTheoToaDo(san),
            hatGiong: hat++,
          );
        }
      }
    }
  }

  void _veKhungVienTheGioi(Canvas canvas, Size size) {
    final vienNgoai = Paint()
      ..color = const Color(0xFF172219)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    canvas.drawRect(Offset.zero & size, vienNgoai);

    final vienVang = Paint()
      ..color = const Color(0x66C8A862)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRect((Offset.zero & size).deflate(16), vienVang);
  }

  void _veCongTrinh(Canvas canvas, CongTrinhWorldMap c, bool biKhoa) {
    final image = anh[c.anh];
    if (image == null) return;
    final crop =
        TaiNguyenWorldMap.khungNguon[c.anh] ?? const Rect.fromLTWH(0, 0, 1, 1);
    final source = Rect.fromLTRB(
      crop.left * image.width,
      crop.top * image.height,
      crop.right * image.width,
      crop.bottom * image.height,
    );
    final height = c.chieuRong * source.height / source.width;
    final rect = Rect.fromLTWH(
      c.chan.dx - c.chieuRong / 2,
      c.chan.dy - height,
      c.chieuRong,
      height,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: c.chan - const Offset(0, 5),
        width: c.chieuRong * 0.82,
        height: c.chieuRong * 0.18,
      ),
      Paint()
        ..color = const Color(0x660A140D)
        ..isAntiAlias = false,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (biKhoa) {
      paint.colorFilter = const ColorFilter.matrix([
        0.65,
        0.12,
        0.05,
        0,
        0,
        0.08,
        0.68,
        0.06,
        0,
        0,
        0.08,
        0.14,
        0.65,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    } else {
      paint.colorFilter = const ColorFilter.mode(
        Color(0xFFF7EED7),
        BlendMode.modulate,
      );
    }
    canvas.drawImageRect(image, source, rect, paint);
  }

  @override
  bool shouldRepaint(CanhQuanWorldMap oldDelegate) =>
      oldDelegate.anh != anh ||
      !mapEquals(oldDelegate.trangThaiCacMan, trangThaiCacMan);
}
