import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/dieu_chinh_do_kho.dart';
import 'ai/gui_nhat_ky.dart';
import 'ai/may_chu_tien_trinh.dart';
import 'ai/may_chu_huy_hieu.dart';
import 'ai/mo_hinh_do_kho.dart';
import 'ai/nhat_ky_choi.dart';
import 'ai/tien_trinh_controller.dart';
import 'ai/tim_duong.dart';
import 'am_thanh/am_thanh.dart';
import 'auth/auth_controller.dart';
import 'blockchain/may_chu_phieu.dart';
import 'blockchain/cua_hang.dart';
import 'blockchain/nhan_vat.dart';
import 'blockchain/phien_vi.dart';
import 'blockchain/vi.dart';
import 'blockchain/vat_pham/nft_model.dart';
import 'blockchain/vat_pham/nft_service.dart';
import 'cau_hinh.dart';
import 'components/ban_do.dart';
import 'components/boss.dart';
import 'components/dan_ban.dart';
import 'components/dong_xu.dart';
import 'components/george.dart';
import 'components/hieu_ung.dart';
import 'components/hud.dart';
import 'components/ke_dich.dart';
import 'components/vat_pham_roi.dart' hide LoaiVatPham;
import 'dieu_khien/nut_tam_dung.dart';
import 'kho_do/vat_pham_hien_thi.dart';
import 'kho_do/danh_sach_trang_bi.dart';
import 'man_choi.dart';
import 'tai_nguyen.dart';
import 'the_gioi.dart';
import 'world_map/luu_tien_trinh.dart';

/// Tên các lớp phủ giao diện.
class LopPhu {
  LopPhu._();

  static const menu = 'menu';
  static const caiDat = 'caiDat';
  static const tamDung = 'tamDung';
  static const ketThuc = 'ketThuc';
  static const huyHieu = 'huyHieu';
  static const cuaHang = 'cuaHang';
  static const chonMan = 'chonMan';
  static const khoDo = 'khoDo';
  static const rungRuong = 'rungRuong';
  static const quaTang = 'quaTang';
  static const nutBan = 'nutBan';
}

/// Kết quả ván vừa xong.
class KetQuaVan {
  final ManChoi man;
  final String maVan;
  final bool thang;
  final int xu;

  /// Thống kê chiến đấu chuẩn hóa cho Progress/Backend (`stage_id`, `won`, `boss_defeated`, v.v.).
  final Map<String, Object> thongKe;

  /// Trạng thái phiếu vàng của ván (đang xin / đã có / không có) — cập nhật khi máy chủ trả lời.
  final String? phieu;
  final Map<String, dynamic>? huyHieuMoi;

  const KetQuaVan({
    required this.man,
    required this.thang,
    required this.xu,
    this.maVan = '',
    this.thongKe = const {},
    this.phieu,
    this.huyHieuMoi,
  });

  int get stageId => man.id;

  bool get matCoc => !man.mienPhi && !thang;

  KetQuaVan voiPhieu(String p) => KetQuaVan(
    man: man,
    maVan: maVan,
    thang: thang,
    xu: xu,
    thongKe: thongKe,
    phieu: p,
    huyHieuMoi: huyHieuMoi,
  );

  KetQuaVan voiHuyHieu(Map<String, dynamic> badge) => KetQuaVan(
    man: man,
    maVan: maVan,
    thang: thang,
    xu: xu,
    thongKe: thongKe,
    phieu: phieu,
    huyHieuMoi: badge,
  );
}

class GoldRushGame extends FlameGame
    with HasCollisionDetection, HasKeyboardHandlerComponents {
  GoldRushGame._(
    this.theGioi,
    this._vi, [
    this.auth,
    TienTrinhController? tienTrinh,
    bool? batBoss,
  ]) : _tienTrinhController = tienTrinh,
       coBoss = batBoss ?? CauHinh.batBoss,
       super(world: theGioi);

  factory GoldRushGame({
    Vi? vi,
    AuthController? auth,
    TienTrinhController? tienTrinh,
    bool? batBoss,
  }) => GoldRushGame._(TheGioi(), vi, auth, tienTrinh, batBoss);

  final Vi? _vi;
  final AuthController? auth;
  final TienTrinhController? _tienTrinhController;

  late final TienTrinhController tienTrinh =
      _tienTrinhController ??
      TienTrinhController(
        mayChu: MayChuTienTrinh(mayChu: GuiNhatKy.mayChu),
        authController: auth,
      );

  final TheGioi theGioi;

  /// Cho phép bật/tắt Boss cho phiên chơi hoặc kiểm thử (mặc định theo `CauHinh.batBoss`).
  bool coBoss;
  final TaiNguyen taiNguyen = TaiNguyen();
  final BoTienTrinhWorldMap tienTrinhWorldMap = BoTienTrinhWorldMap();

  late BanDo banDo;

  List<ManChoi> danhSachMan = const [ManChoi.macDinh];
  ManChoi manHienTai = ManChoi.macDinh;

  int veDangChoi = 0;
  double? giayConLai;
  DateTime? batDauThat;

  final List<Component> _thanhPhanVan = [];
  final Map<String, BanDo> _boNhoBanDo = {};
  int _soQuaiBanDau = 0;
  final List<String> _loaiQuaiGoc = [];
  int _chiSoQuaiTaiSinh = 0;
  final Random _ngauNhienSinhQuai = Random();
  double _demSinhQuai = 0;
  bool _congTraiTren = true;
  int _soQuaiThuongBoSung = 0;
  int _soQuaiKhongLo = 0;
  int _soQuaiGiap = 0;

  static const String phienBanApp = '1.3.0';

  static const String tepMoHinhDoKho = 'assets/models/do_kho_v1.json';
  static const String _khoaTrangBi = 'gold_rush.equipment.v1';

  late TimDuong timDuong;

  final DieuChinhDoKho doKho = DieuChinhDoKho();
  final NhatKyChoi nhatKy = NhatKyChoi();

  /// AI thích ứng chỉ áp dụng cho màn luyện tập đầu tiên.
  bool get _aiDoKhoDuocPhep => manHienTai.id == 1;

  double _heSoTocDoKeDich() =>
      (_aiDoKhoDuocPhep ? doKho.heSoTocDo : 1.0) * manHienTai.heSoKeDich;

  bool _vanDangDienRa = false;

  /// Ngoại hình dùng khi dựng ván tiếp theo.
  String nhanVatDangDung = georgeGoc.tepAnh;
  String tenNhanVatDangDung = georgeGoc.ten;

  static String khoaNhanVatAi(String characterId) => 'ai:$characterId';

  /// Tải sprite-sheet của nhân vật AI đã lưu và chọn làm ngoại hình cho ván sau.
  Future<void> trangBiNhanVatAi({
    required String characterId,
    required String tenNhanVat,
    required Uint8List spriteSheet,
  }) async {
    final khoa = khoaNhanVatAi(characterId);
    await taiNguyen.napNhanVatAi(khoa, spriteSheet);
    nhanVatDangDung = khoa;
    tenNhanVatDangDung = tenNhanVat;
  }

  /// Danh sách vật phẩm & trang bị đồng bộ giữa Main Lobby và Kho đồ.
  final ValueNotifier<List<VatPhamHienThi>> danhSachVatPham = ValueNotifier([]);

  /// Đồng bộ vật phẩm vừa mua thành công vào Kho đồ trong phiên hiện tại.
  /// Số dư on-chain/NFT vẫn là nguồn sự thật; notifier này chỉ cập nhật UI ngay.
  void themVatPhamVaoKho(VatPhamHienThi vatPham, {int soLuong = 1}) {
    if (soLuong < 1) return;
    final ds = danhSachVatPham.value;
    final index = ds.indexWhere((item) => item.id == vatPham.id);
    if (index < 0) {
      danhSachVatPham.value = [...ds, vatPham.voiSoLuong(soLuong)];
      return;
    }
    final hienTai = ds[index];
    final capNhat = hienTai.voiSoLuong(hienTai.soLuong + soLuong);
    danhSachVatPham.value = [
      for (var i = 0; i < ds.length; i++) i == index ? capNhat : ds[i],
    ];
  }

  /// Đồng bộ số lượng NFT đã đọc trên chuỗi, không cộng lặp khi mở lại Store.
  void dongBoSoLuongVatPham(VatPhamHienThi vatPham, int soLuong) {
    if (soLuong < 1) return;
    final ds = danhSachVatPham.value;
    final index = ds.indexWhere((item) => item.id == vatPham.id);
    if (index < 0) {
      danhSachVatPham.value = [...ds, vatPham.voiSoLuong(soLuong)];
      return;
    }
    if (ds[index].soLuong >= soLuong) return;
    danhSachVatPham.value = [
      for (var i = 0; i < ds.length; i++)
        i == index ? ds[i].voiSoLuong(soLuong) : ds[i],
    ];
  }

  int? tokenIdVatPham(String itemId) {
    final index = danhSachTrangBiCuaHang().indexWhere(
      (item) => item.id == itemId,
    );
    return index < 0 ? null : index + 1;
  }

  VatPhamNFT _metadataNFT(
    VatPhamHienThi vatPham,
    int tokenId,
    String hopDong,
    int chainId,
  ) => VatPhamNFT(
    tokenId: BigInt.from(tokenId),
    name: vatPham.ten,
    description: vatPham.moTa,
    category: vatPham.loai == LoaiVatPham.vuKhi
        ? LoaiVatPhamNFT.vuKhi
        : LoaiVatPhamNFT.giap,
    imageUrl: vatPham.duongDanAnh,
    contractAddress: hopDong,
    chainId: chainId,
  );

  VatPhamHienThi _danhDauNFT(
    VatPhamHienThi vatPham,
    int tokenId,
    String hopDong,
    int chainId,
    int soLuong,
  ) => VatPhamHienThi(
    id: vatPham.id,
    ten: vatPham.ten,
    moTa: vatPham.moTa,
    loai: vatPham.loai,
    doHiem: vatPham.doHiem,
    nguon: NguonVatPham.nft,
    bieuTuong: vatPham.bieuTuong,
    danhMuc: vatPham.danhMuc,
    soLuong: soLuong,
    duongDanAnh: vatPham.duongDanAnh,
    thuocTinh: vatPham.thuocTinh,
    satThuong: vatPham.satThuong,
    tamBan: vatPham.tamBan,
    hpCongThem: vatPham.hpCongThem,
    giamSatThuong: vatPham.giamSatThuong,
    tocDoCongThem: vatPham.tocDoCongThem,
    xuyenPha: vatPham.xuyenPha,
    oDangTrangBi: vatPham.oDangTrangBi,
    chainId: chainId,
    diaChiHopDong: hopDong,
    tokenId: '$tokenId',
  );

  Future<void> dongBoNFTKhoDo() async {
    final pv = phienVi;
    final cauHinh = pv?.cauHinh;
    final hopDong = cauHinh?.hopDongVatPham;
    if (pv == null ||
        !pv.daKetNoi ||
        cauHinh == null ||
        hopDong == null ||
        hopDong.isEmpty) {
      return;
    }

    final catalog = danhSachTrangBiCuaHang();
    final dichVu = DichVuNFT(
      phienVi: pv,
      cauHinh: CauHinhNFT(chainId: cauHinh.chainId, hopDong: hopDong),
    );
    try {
      final metadata = [
        for (var i = 0; i < catalog.length; i++)
          _metadataNFT(catalog[i], i + 1, hopDong, cauHinh.chainId),
      ];
      final nftDaDoc = await dichVu.taiDanhSach(metadata);
      var danhSachMoi = List<VatPhamHienThi>.of(danhSachVatPham.value);
      var coThayDoi = false;

      for (var i = 0; i < catalog.length; i++) {
        final item = catalog[i];
        final soLuong = nftDaDoc[i].balance?.toInt() ?? 0;
        final index = danhSachMoi.indexWhere((owned) => owned.id == item.id);
        if (soLuong <= 0) {
          if (index >= 0 && danhSachMoi[index].nguon == NguonVatPham.nft) {
            danhSachMoi.removeAt(index);
            coThayDoi = true;
          }
          continue;
        }

        final nftItem = _danhDauNFT(
          index >= 0 ? danhSachMoi[index] : item,
          i + 1,
          hopDong,
          cauHinh.chainId,
          soLuong,
        );
        if (index < 0) {
          danhSachMoi.add(nftItem);
          coThayDoi = true;
        } else if (danhSachMoi[index].soLuong != soLuong ||
            danhSachMoi[index].nguon != NguonVatPham.nft) {
          danhSachMoi[index] = nftItem;
          coThayDoi = true;
        }
      }

      try {
        await pv.mayChu.dongBoKhoNFT(
          vatPham: [
            for (var i = 0; i < catalog.length; i++)
              {
                'item_id': catalog[i].id,
                'item_type': switch (catalog[i].loai) {
                  LoaiVatPham.vuKhi => 'weapon',
                  LoaiVatPham.giap => 'armor',
                  LoaiVatPham.giay => 'shoes',
                  LoaiVatPham.vatPham => 'item',
                },
                'token_id': i + 1,
                'metadata': {
                  'name': catalog[i].ten,
                  'description': catalog[i].moTa,
                  'image_url': catalog[i].duongDanAnh,
                },
              },
          ],
        );
      } on LoiVi {
        // Blockchain vẫn là nguồn hiển thị chính; Backend sẽ thử lại ở lượt sau.
      }

      if (coThayDoi) {
        danhSachVatPham.value = danhSachMoi;
        _apDungTrangBiChoGeorge();
        await _luuTrangBi();
      }
    } finally {
      dichVu.dispose();
    }
  }

  Future<void> chuyenVatPhamNFT(
    VatPhamHienThi vatPham,
    String nguoiNhan,
    int soLuong,
  ) async {
    final pv = phienVi;
    final cauHinh = pv?.cauHinh;
    final hopDong = cauHinh?.hopDongVatPham;
    final tokenId = tokenIdVatPham(vatPham.id);
    if (pv == null || cauHinh == null || hopDong == null || hopDong.isEmpty) {
      throw const LoiVi('Chưa cấu hình hợp đồng NFT vật phẩm.');
    }
    if (tokenId == null) {
      throw const LoiVi('Không xác định được tokenId của vật phẩm.');
    }

    await pv.capEthTest();

    final dichVu = DichVuNFT(
      phienVi: pv,
      cauHinh: CauHinhNFT(chainId: cauHinh.chainId, hopDong: hopDong),
    );
    try {
      final metadata = _metadataNFT(vatPham, tokenId, hopDong, cauHinh.chainId);
      final ketQua = await dichVu.chuyenVatPham(
        tokenId: BigInt.from(tokenId),
        nguoiNhan: nguoiNhan,
        amount: BigInt.from(soLuong),
        metadata: metadata,
      );
      await capNhatSauKhiChuyenNFT(vatPham.id, ketQua.vatPham.balance);
      await dongBoNFTKhoDo();
    } finally {
      dichVu.dispose();
    }
  }

  /// Nộp các phiếu vàng quà tặng do Backend ký trong một giao dịch hiện có.
  Future<String> nhanQuaTangVang(List<PhieuCho> vouchers) async {
    final pv = phienVi;
    if (pv == null || !pv.daKetNoi || vouchers.isEmpty) {
      throw const LoiVi('Chưa kết nối ví hoặc voucher vàng không hợp lệ.');
    }
    await pv.lamMoi();
    await pv.capEthTest();
    await pv.cuaHang!.thucHien(diaChi: pv.diaChi!, phieu: vouchers);
    final hash = pv.cuaHang!.bo.maGiaoDichCuoi;
    await pv.lamMoi();
    if (hash == null || hash.isEmpty) {
      throw const LoiVi('Không lấy được mã giao dịch nhận vàng.');
    }
    return hash;
  }

  /// Claim NFT quà tặng bằng cơ chế claimItem hiện có của VatPhamGoldRush.
  Future<String> nhanQuaTangNFT(PhieuVatPhamQuaTang voucher) async {
    final pv = phienVi;
    final cauHinh = pv?.cauHinh;
    final hopDong = cauHinh?.hopDongVatPham;
    final tokenId = voucher.tokenId;
    final catalog = danhSachTrangBiCuaHang();
    if (pv == null ||
        !pv.daKetNoi ||
        cauHinh == null ||
        hopDong == null ||
        hopDong.isEmpty) {
      throw const LoiVi('Chưa cấu hình hợp đồng NFT vật phẩm.');
    }
    if (voucher.chainId != cauHinh.chainId ||
        voucher.contractAddress.toLowerCase() != hopDong.toLowerCase() ||
        tokenId < 1 ||
        tokenId > catalog.length) {
      throw const LoiVi('Voucher NFT không thuộc mạng hoặc danh mục hiện tại.');
    }
    await pv.capEthTest();
    final item = catalog[tokenId - 1];
    final dichVu = DichVuNFT(
      phienVi: pv,
      cauHinh: CauHinhNFT(chainId: cauHinh.chainId, hopDong: hopDong),
    );
    try {
      final ketQua = await dichVu.nhanVatPham(
        _metadataNFT(item, tokenId, hopDong, cauHinh.chainId),
        phieu: PhieuVatPhamDaKy(
          phieu: PhieuVatPham(
            player: voucher.player,
            tokenId: BigInt.from(tokenId),
            amount: BigInt.from(voucher.amount),
            nonce: voucher.nonce,
            deadline: BigInt.from(voucher.deadline),
          ),
          chuKy: voucher.signature,
          cauHinh: CauHinhNFT(
            chainId: voucher.chainId,
            hopDong: voucher.contractAddress,
          ),
        ),
      );
      await dongBoNFTKhoDo();
      return ketQua.transactionHash;
    } finally {
      dichVu.dispose();
    }
  }

  Future<void> capNhatSauKhiChuyenNFT(
    String itemId,
    BigInt? soLuongConLai,
  ) async {
    final ds = danhSachVatPham.value;
    final index = ds.indexWhere((item) => item.id == itemId);
    if (index < 0) return;

    final hienTai = ds[index];
    final conLai = soLuongConLai?.toInt() ?? 0;
    if (conLai <= 0) {
      danhSachVatPham.value = [
        for (var i = 0; i < ds.length; i++)
          if (i != index) ds[i],
      ];
      _apDungTrangBiChoGeorge();
      await _luuTrangBi();
      return;
    }

    danhSachVatPham.value = [
      for (var i = 0; i < ds.length; i++)
        i == index ? hienTai.voiSoLuong(conLai) : ds[i],
    ];
  }

  Future<void> trangBiVatPham(String itemId) async {
    final ds = danhSachVatPham.value;
    final idx = ds.indexWhere((vp) => vp.id == itemId);
    if (idx < 0) return;
    final vp = ds[idx];
    if (vp.nguon == NguonVatPham.nft && vp.tokenId == null) return;
    if (vp.loai != LoaiVatPham.vuKhi &&
        vp.loai != LoaiVatPham.giap &&
        vp.loai != LoaiVatPham.giay) {
      return;
    }

    final OTrangBi o;
    if (vp.loai == LoaiVatPham.giap) {
      o = OTrangBi.giap;
    } else if (vp.loai == LoaiVatPham.giay) {
      o = OTrangBi.giay;
    } else if (vp.bieuTuong == BieuTuongVatPham.cung) {
      o = OTrangBi.vuKhiPhu;
    } else {
      o = OTrangBi.vuKhiChinh;
    }

    danhSachVatPham.value = [
      for (final item in ds)
        if (item.id == itemId)
          item.voiTrangBi(o)
        else if (item.oDangTrangBi == o)
          item.voiTrangBi(null)
        else
          item,
    ];
    _apDungTrangBiChoGeorge();
    await _luuTrangBi();
  }

  Future<void> thaoVatPham(String itemId) async {
    final ds = danhSachVatPham.value;
    danhSachVatPham.value = [
      for (final item in ds)
        if (item.id == itemId) item.voiTrangBi(null) else item,
    ];
    _apDungTrangBiChoGeorge();
    await _luuTrangBi();
  }

  Future<void> _luuTrangBi() async {
    final dangMac = <String, String>{};
    for (final vp in danhSachVatPham.value) {
      final o = vp.oDangTrangBi;
      if (o != null) dangMac[o.name] = vp.id;
    }
    await SharedPreferencesAsync().setString(_khoaTrangBi, jsonEncode(dangMac));
  }

  Future<void> _napTrangBiDaLuu() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_khoaTrangBi);
      if (raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      var ds = [
        for (final item in danhSachVatPham.value) item.voiTrangBi(null),
      ];
      for (final entry in data.entries) {
        if (entry.key is! String || entry.value is! String) continue;
        OTrangBi? slot;
        for (final value in OTrangBi.values) {
          if (value.name == entry.key) slot = value;
        }
        if (slot == null) continue;
        ds = [
          for (final item in ds)
            if (item.id == entry.value)
              item.voiTrangBi(slot)
            else if (item.oDangTrangBi == slot)
              item.voiTrangBi(null)
            else
              item,
        ];
      }
      danhSachVatPham.value = ds;
    } catch (_) {
      // Dữ liệu lưu cũ/hỏng không được chặn việc vào game.
    }
  }

  void _apDungTrangBiChoGeorge() {
    final g = george;
    if (g == null) return;

    VatPhamHienThi? tim(OTrangBi o) {
      for (final vp in danhSachVatPham.value) {
        if (vp.oDangTrangBi == o) return vp;
      }
      return null;
    }

    final sung = tim(OTrangBi.vuKhiChinh) ?? tim(OTrangBi.vuKhiPhu);
    final giap = tim(OTrangBi.giap);
    final giay = tim(OTrangBi.giay);
    Map<HuongDi, SpriteAnimation> hoatAnh(VatPhamHienThi? vp) {
      final tep = vp?.duongDanAnh?.split('/').last;
      return tep == null ? const {} : taiNguyen.trangBiTheoTep[tep] ?? const {};
    }

    g.datChiSoTrangBi(
      satThuong: sung?.satThuong ?? 0,
      tamBan: sung?.tamBan ?? 0,
      hpCongThem: giap?.hpCongThem ?? 0,
      giamSatThuong: giap?.giamSatThuong ?? 0,
      tocDoCongThem: giay?.tocDoCongThem ?? 0,
      xuyenPha: sung?.xuyenPha ?? false,
    );
    g.capNhatTrangBiHienThi(
      vuKhi: hoatAnh(sung),
      giap: hoatAnh(giap),
      giay: hoatAnh(giay),
    );
  }

  /// Phiên ví dùng chung, không tạo riêng cho từng màn hình.
  late final PhienVi? phienVi = PhienVi(
    vi: _vi ?? taoViMacDinh(),
    mayChu: MayChuPhieu(
      mayChu: GuiNhatKy.mayChu,
      layCsrfToken: () => auth?.csrfToken,
    ),
  );

  final ValueNotifier<KetQuaVan?> ketQuaVan = ValueNotifier(null);

  /// Huy hiệu đã được backend xác nhận trong phiên hiện tại.
  final ValueNotifier<Set<int>> huyHieuDaNhan = ValueNotifier(<int>{});

  int _mauTruoc = CauHinh.mauToiDa;
  int _diemTruoc = 0;

  George? george;
  JoystickComponent? joystick;
  Hud? hud;

  /// Boss của ván hiện tại. Boss chỉ được sinh từ màn 7 trở đi.
  Boss? _boss;

  TrangThaiChoi trangThai = TrangThaiChoi.tamDung;
  bool _daGuiVaXinPhieu = false;
  Future<void>? _dangNhanThuong;
  Future<void>? _dangDongBoVi;

  int tongSoXu = 0;
  int soXuDaNhat = 0;

  /// Điểm cao nhất trong phiên hiện tại.
  int diemCaoNhat = 0;

  @override
  Color backgroundColor() => CauHinh.mauNen;

  // ------------------------------------------------------------------
  // Nạp tài nguyên
  // ------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    await taiNguyen.nap();
    await AmThanh.napTruoc();
    await _napTrangBiDaLuu();
    unawaited(phienVi?.napVangDaLuu());

    await _napDanhSachMan();
    await tienTrinhWorldMap.nap(danhSachMan);

    banDo = await _layBanDo(manHienTai.tep);
    theGioi.add(banDo.thanhPhan);

    timDuong = _dungTimDuong();

    await _napMoHinhDoKho();
    unawaited(napHuyHieu());
    if (auth?.canEnterGame == true && auth?.walletAddress != null) {
      final pv = phienVi;
      pv?.diaChi ??= auth!.walletAddress!;
      if (pv != null) {
        final dongBo = () async {
          final daKetNoi = await pv.ketNoiDaXacThuc(auth!.walletAddress!);
          if (daKetNoi) await dongBoNFTKhoDo();
        }();
        _dangDongBoVi = dongBo;
        unawaited(dongBo);
      }
    }

    theGioi.khiChamVaoBanDo = (viTri) {
      george?.viTriDich = viTri;
    };

    _capNhatZoom();

    hud = Hud(
      layMau: () => george?.mau ?? 0,
      layDiem: () => george?.diem ?? 0,
      layXuConLai: () => tongSoXu - soXuDaNhat,
      layGiayConLai: () => giayConLai,
    );

    camera.viewport.add(hud!);

    joystick = JoystickComponent(
      knob: SpriteComponent(
        sprite: taiNguyen.joystickNum,
        size: Vector2.all(30),
      ),
      background: SpriteComponent(
        sprite: taiNguyen.joystickNen,
        size: Vector2.all(72),
      ),
      margin: const EdgeInsets.only(left: 26, bottom: 26),
      priority: 100,
    );

    camera.viewport.add(joystick!);
    camera.viewport.add(NutTamDung(khiBam: tamDung));

    // Dựng cảnh phía sau Menu.
    _dungVan();
    _anTatCaLopPhu();
    overlays.add(LopPhu.menu);

    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);
  }

  TimDuong _dungTimDuong() => TimDuong(
    soCot: banDo.soCot,
    soHang: banDo.soHang,
    biChan: banDo.luoi.biChanO,
  );

  Future<void> napHuyHieu() async {
    if (auth == null) return;
    final client = MayChuHuyHieu();
    final data = await client.taiDanhSach();
    client.dong();
    final badges = data?['badges'];
    if (badges is! List) return;
    final ids = <int>{};
    for (final item in badges) {
      if (item is Map && item['eligible'] == true && item['badge_id'] is int) {
        ids.add(item['badge_id'] as int);
      }
    }
    if (ids.isNotEmpty) huyHieuDaNhan.value = ids;
  }

  /// Khởi tạo bộ nhớ bản đồ và trạng thái ván cho kiểm thử đơn vị mà không cần nạp `.tmx` hay âm thanh.
  @visibleForTesting
  void khoiTaoChoKiemThu({
    required BanDo banDoDau,
    Map<String, BanDo>? cacBanDoKhac,
    List<ManChoi>? danhSachMan,
  }) {
    for (final ten in [
      LopPhu.menu,
      LopPhu.caiDat,
      LopPhu.tamDung,
      LopPhu.ketThuc,
      LopPhu.huyHieu,
      LopPhu.cuaHang,
      LopPhu.chonMan,
      LopPhu.rungRuong,
      LopPhu.quaTang,
      LopPhu.nutBan,
    ]) {
      overlays.addEntry(ten, (_, _) => const SizedBox.shrink());
    }
    _boNhoBanDo.clear();
    _boNhoBanDo[banDoDau.tep] = banDoDau;
    if (cacBanDoKhac != null) _boNhoBanDo.addAll(cacBanDoKhac);
    if (danhSachMan != null && danhSachMan.isNotEmpty) {
      this.danhSachMan = danhSachMan;
      manHienTai = danhSachMan.first;
    }
    banDo = banDoDau;
    theGioi.add(banDo.thanhPhan);
    timDuong = _dungTimDuong();
    final ids = (danhSachMan != null && danhSachMan.isNotEmpty)
        ? danhSachMan.map((m) => m.id).toList()
        : [1, 2, 3, 4, 5, 6];
    // ignore: invalid_use_of_visible_for_testing_member
    tienTrinhWorldMap.khoiTaoChoKiemThu(ids);
  }

  @visibleForTesting
  bool get daGuiVaXinPhieu => _daGuiVaXinPhieu;

  @visibleForTesting
  Future<void> guiVaXinPhieuChoKiemThu({
    required Map<String, Object> nk,
    required String maVan,
    required KetQuaVan kq,
    required bool coPhieu,
  }) async {
    _daGuiVaXinPhieu = true;
    await _guiVaXinPhieu(nk, maVan, kq, coPhieu);
  }

  Future<void> _napDanhSachMan() async {
    try {
      // Một manifest dùng chung cho Flutter, Backend và Hardhat.
      danhSachMan = ManChoi.docDanhSach(
        await rootBundle.loadString('assets/tiles/man_choi.json'),
      );
      manHienTai = danhSachMan.first;
    } catch (e) {
      debugPrint(
        'Không nạp được man_choi.json ($e) '
        '— chỉ có màn mặc định.',
      );
    }
  }

  Future<BanDo> _layBanDo(String tep) async =>
      _boNhoBanDo[tep] ??= await BanDo.nap(tep);

  /// Kiểm tra bản đồ trước khi đặt cọc.
  Future<bool> napTruocBanDo(ManChoi m) async {
    try {
      await _layBanDo(m.tep);
      return true;
    } catch (e) {
      debugPrint('Không nạp được ${m.tep}: $e');
      return false;
    }
  }

  Future<void> _doiBanDo(ManChoi m) async {
    if (banDo.tep == m.tep) return;

    final moi = await _layBanDo(m.tep);

    banDo.thanhPhan.removeFromParent();
    banDo = moi;

    theGioi.add(banDo.thanhPhan);
    timDuong = _dungTimDuong();
  }

  Future<void> _napMoHinhDoKho() async {
    try {
      final chuoi = await rootBundle.loadString(tepMoHinhDoKho);
      doKho.moHinh = MoHinhDoKho.tuJson(
        jsonDecode(chuoi) as Map<String, dynamic>,
      );
      debugPrint('Đã nạp mô hình độ khó ${doKho.moHinh!.phienBan}');
    } catch (e) {
      debugPrint(
        'Không nạp được mô hình độ khó ($e) '
        '— dùng độ khó cố định.',
      );
    }
  }

  @override
  void onMount() {
    super.onMount();
    pauseEngine();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _capNhatZoom();
  }

  void _capNhatZoom() {
    if (size.x <= 0) return;

    final z = size.x / (CauHinh.soONhinThayNgang * CauHinh.kichThuocO);
    camera.viewfinder.zoom = z
        .clamp(CauHinh.zoomToiThieu, CauHinh.zoomToiDa)
        .toDouble();
  }

  // ==================================================================
  // Dựng ván chơi
  // ==================================================================
  Boss? get boss => _boss;

  void _dungVan({String? maVan}) {
    for (final c in _thanhPhanVan) {
      c.removeFromParent();
    }
    _thanhPhanVan.clear();
    // Dọn dẹp mọi đạn, vật phẩm rơi hoặc hiệu ứng nổ động còn sót trong theGioi từ ván trước.
    for (final c in theGioi.children.toList()) {
      if (c is DanBan ||
          c is VatPhamRoi ||
          c is HieuUngNoKeDich ||
          c is HieuUngNhatXu) {
        c.removeFromParent();
      }
    }
    _boss = null;
    _demSinhQuai = 0;
    _congTraiTren = true;
    _soQuaiBanDau = 0;
    _loaiQuaiGoc.clear();
    _chiSoQuaiTaiSinh = 0;
    _soQuaiThuongBoSung = 0;
    _soQuaiKhongLo = 0;
    _soQuaiGiap = 0;

    soXuDaNhat = 0;
    tongSoXu = 0;

    final diemGeorge = banDo.diemXuatHien.firstWhere(
      (d) => d.ten == 'george',
      orElse: () => DiemXuatHien('george', banDo.kichThuoc / 2),
    );

    VatPhamHienThi? timTrangBi(OTrangBi o) {
      for (final vp in danhSachVatPham.value) {
        if (vp.oDangTrangBi == o) return vp;
      }
      return null;
    }

    String? tenTep(VatPhamHienThi? vp) => vp?.duongDanAnh?.split('/').last;
    Map<HuongDi, SpriteAnimation> hoatAnhTrangBi(VatPhamHienThi? vp) {
      final tep = tenTep(vp);
      return tep == null ? const {} : taiNguyen.trangBiTheoTep[tep] ?? const {};
    }

    final sung =
        timTrangBi(OTrangBi.vuKhiChinh) ?? timTrangBi(OTrangBi.vuKhiPhu);
    final giap = timTrangBi(OTrangBi.giap);
    final giay = timTrangBi(OTrangBi.giay);

    george = George(
      banDo: banDo,
      hoatAnh: taiNguyen.georgeTheoTep[nhanVatDangDung] ?? taiNguyen.george,
      viTri: diemGeorge.viTri.clone(),
      khiChiSoDoi: _khiChiSoDoi,
      khiChet: _khiGeorgeChet,
      trangBiVuKhi: hoatAnhTrangBi(sung),
      trangBiGiap: hoatAnhTrangBi(giap),
      trangBiGiay: hoatAnhTrangBi(giay),
    );
    _apDungTrangBiChoGeorge();

    _them(george!);

    // Đếm số mục tiêu George hạ được (quái và Boss) cho thống kê chiến đấu.
    george!.khiHaMucTieu = (_) => nhatKy.ghiHaKeDich();

    Vector2 viTriNguoiChoi() => george?.position ?? Vector2.zero();

    for (final d in banDo.diemXuatHien) {
      switch (d.ten) {
        case 'coin':
          tongSoXu++;
          _them(DongXu(hoatAnh: taiNguyen.dongXu, viTri: d.viTri.clone()));
          break;

        case 'zombie':
        case 'skeleton':
        case 'thuong':
        case 'giap':
        case 'khong_lo':
          _soQuaiBanDau++;
          _loaiQuaiGoc.add(d.ten);
          _sinhQuai(
            d.ten,
            viTriNguoiChoi,
            _heSoTocDoKeDich,
            viTri: d.viTri.clone(),
          );
          break;
      }
    }

    // Boss chỉ xuất hiện từ màn 7; sáu màn gốc không thay đổi. Chưa có điểm 'boss' trong .tmx thì
    // dùng tạm điểm skeleton đầu tiên (chắc chắn đi được), hoặc tâm bản đồ.
    if (coBoss && manHienTai.id >= 7) {
      final diemBoss = banDo.diemXuatHien.firstWhere(
        (d) => d.ten == 'boss',
        orElse: () => banDo.diemXuatHien.firstWhere(
          (d) => d.ten == 'skeleton',
          orElse: () => DiemXuatHien('boss', banDo.kichThuoc / 2),
        ),
      );
      _boss = Boss(
        banDo: banDo,
        hoatAnh: taiNguyen.skeleton,
        viTri: diemBoss.viTri.clone(),
        viTriNguoiChoi: viTriNguoiChoi,
        gayDame: (l) => george?.nhanSatThuong(l),
        khiChet: _khiBossChet,
      );
      _them(_boss!);
    }

    camera.follow(george!, snap: true);
    _ghimCameraTrongBanDo();

    nhatKy.batDau(tongSoXu, maVanCoSan: maVan);
    giayConLai = manHienTai.gioiHanGiay > 0
        ? manHienTai.gioiHanGiay.toDouble()
        : null;
    doKho.datLai();
    _mauTruoc = george!.mau;
    _diemTruoc = 0;
  }

  void _them(Component c) {
    _thanhPhanVan.add(c);
    theGioi.add(c);
  }

  int get _giaiDoanSinhQuai => manHienTai.id <= 3
      ? 1
      : (manHienTai.id <= 7 ? 2 : (manHienTai.id <= 15 ? 3 : 4));

  int get _soQuaiDangSong =>
      theGioi.children.whereType<KeDich>().where((q) => !q.isDead).length;

  /// Chu kỳ sinh bổ sung (giây) theo nhóm màn 2–20; màn 1 không sinh thêm.
  /// Mỗi lần đến chu kỳ, hệ thống sinh tối đa một quái theo logic hiện có.
  double get _chuKySinhQuai => switch (manHienTai.id) {
    <= 6 => 20,
    <= 10 => 10,
    <= 15 => 5,
    _ => 3,
  };

  int get _soThuongToiDa => switch (manHienTai.id) {
    4 || 5 => 2,
    6 || 7 => 3,
    8 || 9 => 3,
    10 || 11 => 3,
    12 => 4,
    13 || 14 || 15 => 5,
    16 || 17 || 18 => 5,
    19 || 20 => 6,
    _ => 0,
  };

  int get _soGiapBatBuoc => switch (manHienTai.id) {
    16 => 1,
    17 => 2,
    18 || 19 => 3,
    20 => 4,
    _ => 0,
  };

  void _capNhatSinhQuai(
    double dt,
    Vector2 Function() viTriNguoiChoi,
    double Function() heSoTocDo,
  ) {
    // Màn 1 chỉ có quái ban đầu, không sinh bù hoặc sinh bổ sung.
    if (manHienTai.id == 1) return;

    _demSinhQuai += dt;
    if (_demSinhQuai < _chuKySinhQuai) return;
    _demSinhQuai = 0;

    // Nếu số quái sống hiện tại < số quái ban đầu, sinh bù theo thời gian cố định.
    // Nếu đã đủ (>= _soQuaiBanDau) thì không sinh quái gốc nữa.
    if (_soQuaiDangSong < _soQuaiBanDau && _loaiQuaiGoc.isNotEmpty) {
      final loai = _loaiQuaiGoc[_chiSoQuaiTaiSinh % _loaiQuaiGoc.length];
      _chiSoQuaiTaiSinh++;
      _sinhQuai(loai, viTriNguoiChoi, heSoTocDo);
      return;
    }

    final tienTrinh = manHienTai.gioiHanGiay <= 0
        ? 1.0
        : (nhatKy.giay / manHienTai.gioiHanGiay).clamp(0.0, 1.0);

    if (_giaiDoanSinhQuai == 4 &&
        tienTrinh >= 0.7 &&
        _soQuaiGiap < _soGiapBatBuoc &&
        theGioi.children
                .whereType<KeDich>()
                .where((q) => q.maxHp == 100)
                .length <
            2) {
      _soQuaiGiap++;
      _sinhQuai('giap', viTriNguoiChoi, heSoTocDo);
      return;
    }

    final loai = _chonQuaiBoSung(tienTrinh);
    if (loai == 'khong_lo') _soQuaiKhongLo++;
    if (loai == 'thuong') _soQuaiThuongBoSung++;
    _sinhQuai(loai, viTriNguoiChoi, heSoTocDo);
  }

  String _chonQuaiBoSung(double tienTrinh) {
    final loai = _chonQuaiBoSungTheoTyLe(tienTrinh);
    if (loai == 'khong_lo' && manHienTai.id == 9 && coBoss) {
      return 'thuong';
    }
    if (loai == 'thuong' && _soQuaiThuongBoSung >= _soThuongToiDa) {
      return 'zombie';
    }
    return loai;
  }

  String _chonQuaiBoSungTheoTyLe(double tienTrinh) {
    final r = _ngauNhienSinhQuai.nextDouble();
    if (_giaiDoanSinhQuai == 1) return 'zombie';

    if (_giaiDoanSinhQuai == 2) {
      final tiLeThuong = switch (manHienTai.id) {
        4 => 0.20,
        5 => 0.25,
        6 => 0.30,
        _ => 0.35,
      };
      return r < tiLeThuong ? 'thuong' : 'zombie';
    }

    if (_giaiDoanSinhQuai == 3) {
      if (tienTrinh < 0.5) return r < 0.55 ? 'zombie' : 'thuong';
      final tiLeKhongLo = switch (manHienTai.id) {
        8 || 9 => 0.05,
        10 || 11 => 0.08,
        12 => 0.10,
        13 => 0.10,
        14 => 0.13,
        _ => 0.15,
      };
      if (r < tiLeKhongLo && _soQuaiKhongLo == 0) return 'khong_lo';
      return r < tiLeKhongLo + 0.5 ? 'thuong' : 'zombie';
    }

    final tiLeKhongLo = switch (manHienTai.id) {
      16 => 0.10,
      17 => 0.12,
      18 => 0.15,
      _ => 0.20,
    };
    if (r < tiLeKhongLo && _soQuaiKhongLo == 0) return 'khong_lo';
    return r < tiLeKhongLo + 0.6 ? 'thuong' : 'zombie';
  }

  Vector2 _viTriCongSinh() {
    final le = CauHinh.kichThuocO;
    final traiTren = _congTraiTren;
    final diemGoc = traiTren
        ? Vector2(le, le)
        : Vector2(banDo.kichThuoc.x - le, banDo.kichThuoc.y - le);
    _congTraiTren = !_congTraiTren;
    if (banDo.diDuoc(diemGoc, Vector2.all(2))) return diemGoc;

    // Nếu đúng ô góc là tường, tìm ô đi được gần cổng nhất trên đường chéo.
    for (var i = 1; i < 12; i++) {
      final diem = traiTren
          ? Vector2(le * (i + 1), le * (i + 1))
          : Vector2(
              banDo.kichThuoc.x - le * (i + 1),
              banDo.kichThuoc.y - le * (i + 1),
            );
      if (banDo.diDuoc(diem, Vector2.all(2))) return diem;
    }
    return banDo.kichThuoc / 2;
  }

  void _sinhQuai(
    String loai,
    Vector2 Function() viTriNguoiChoi,
    double Function() heSoTocDo, {
    Vector2? viTri,
  }) {
    final viTriSinh = viTri ?? _viTriCongSinh();
    final tim = timDuong;
    final component = switch (loai) {
      'skeleton' => KeDich.skeleton(
        banDo: banDo,
        hoatAnh: taiNguyen.skeleton,
        viTri: viTriSinh,
        viTriNguoiChoi: viTriNguoiChoi,
        timDuong: tim,
        heSoTocDo: heSoTocDo,
      ),
      'thuong' => KeDich.thuong(
        banDo: banDo,
        hoatAnh: taiNguyen.quaiThuong,
        viTri: viTriSinh,
        viTriNguoiChoi: viTriNguoiChoi,
        timDuong: tim,
        heSoTocDo: heSoTocDo,
      ),
      'giap' => KeDich.giap(
        banDo: banDo,
        hoatAnh: taiNguyen.quaiGiap,
        viTri: viTriSinh,
        viTriNguoiChoi: viTriNguoiChoi,
        timDuong: tim,
        heSoTocDo: heSoTocDo,
      ),
      'khong_lo' => KeDich.khongLo(
        banDo: banDo,
        hoatAnh: taiNguyen.quaiKhongLo,
        viTri: viTriSinh,
        viTriNguoiChoi: viTriNguoiChoi,
        timDuong: tim,
        heSoTocDo: heSoTocDo,
      ),
      _ => KeDich.zombie(
        banDo: banDo,
        hoatAnh: taiNguyen.zombie,
        viTri: viTriSinh,
        viTriNguoiChoi: viTriNguoiChoi,
        timDuong: tim,
        heSoTocDo: heSoTocDo,
      ),
    };
    _them(component);
  }

  void _khiChiSoDoi() {
    final g = george;
    if (g == null) return;

    // Ghi nhật ký: điểm tăng = vừa nhặt xu, máu giảm = vừa trúng đòn.
    if (g.diem > _diemTruoc) nhatKy.ghiNhatXu(g.position.x, g.position.y);
    if (g.mau < _mauTruoc) {
      nhatKy.ghiTrungDon(g.position.x, g.position.y);
      nhatKy.satThuongNhan += _mauTruoc - g.mau;
    }
    _diemTruoc = g.diem;
    _mauTruoc = g.mau;

    final nhat = g.diem ~/ CauHinh.diemMoiDongXu;

    if (nhat != soXuDaNhat) {
      soXuDaNhat = nhat;
      _kiemTraThang();
    }
  }

  bool get _bossConSong => _boss != null && _boss!.sucKhoe.conSong;

  /// Thắng khi đủ xu VÀ không còn Boss. Không có Boss thì y hệt luồng cũ.
  void _kiemTraThang() {
    if (trangThai != TrangThaiChoi.dangChoi) return;
    final daSinhDuQuai = _soQuaiGiap >= _soGiapBatBuoc;
    if (tongSoXu > 0 &&
        soXuDaNhat >= tongSoXu &&
        !_bossConSong &&
        daSinhDuQuai) {
      _khiThangCuoc();
    }
  }

  void _khiBossChet(Boss b) {
    nhatKy.bossDaHa = true;
    _kiemTraThang();
  }

  void _khiGeorgeChet() {
    trangThai = TrangThaiChoi.thua;
    _ketThucVan();
  }

  void _khiThangCuoc() {
    if (_vanDangDienRa) {
      unawaited(tienTrinhWorldMap.ghiNhanThang(manHienTai.id));
    }
    trangThai = TrangThaiChoi.thang;
    _ketThucVan();
  }

  void _khiHetGio() {
    giayConLai = 0;
    trangThai = TrangThaiChoi.thua;
    _ketThucVan();
  }

  void _ketThucVan() {
    _guiNhatKy(trangThai == TrangThaiChoi.thang ? 'thang' : 'thua');

    diemCaoNhat = max(diemCaoNhat, george?.diem ?? 0);

    _datDieuKhien(false);
    AmThanh.dungNhacNen();
    overlays.add(LopPhu.ketThuc);
    pauseEngine();
  }

  // ------------------------------------------------------------------
  // Vòng lặp
  // ------------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);

    if (trangThai != TrangThaiChoi.dangChoi) return;

    _docJoystick();
    _ghimCameraTrongBanDo();

    final con = giayConLai;

    if (con != null) {
      giayConLai = con - dt;

      if (giayConLai! <= 0) {
        _khiHetGio();
        return;
      }
    }

    final g = george;

    if (g != null) {
      Vector2 viTriNguoiChoi() => g.position;
      _capNhatSinhQuai(dt, viTriNguoiChoi, _heSoTocDoKeDich);
      _kiemTraThang();
    }

    if (g != null && nhatKy.troiThoiGian(dt)) {
      final dacTrung = nhatKy.chup(g.mau, CauHinh.mauToiDa);
      if (_aiDoKhoDuocPhep) doKho.capNhat(dacTrung);
    }
  }

  void _guiNhatKy(String ketQua) {
    if (!_vanDangDienRa) return;

    _vanDangDienRa = false;

    final g = george;
    if (g != null) nhatKy.chup(g.mau, CauHinh.mauToiDa);

    // Thống kê chiến đấu: chỉ ghi log cục bộ, CHƯA gửi lên máy chủ
    if (g != null) nhatKy.trangBi = g.trangBi.idDangTrang;
    final thangVan = ketQua == 'thang';
    final thongKe = nhatKy.thongKeChienDau(
      stageId: manHienTai.id,
      won: thangVan,
    );
    debugPrint('Chiến đấu: $thongKe');

    final nk = nhatKy.thanhJson(
      ketQua: ketQua,
      diem: g?.diem ?? 0,
      phienBanApp: phienBanApp,
      doKhoThichUng:
          _aiDoKhoDuocPhep && doKho.batThichUng && doKho.moHinh != null,
      banDo: banDo.tep,
      man: manHienTai.id,
    );
    debugPrint(
      'Ván ${nk['ma_van']}: $ketQua, ${nk['giay']} giây, '
      '${nhatKy.anhChup.length} ảnh chụp, ${nhatKy.suKien.length} sự kiện',
    );
    final maVan = nhatKy.maVan;
    final man = manHienTai;
    final thang = ketQua == 'thang';
    var kq = KetQuaVan(
      man: man,
      maVan: maVan,
      thang: thang,
      xu: nhatKy.soXu,
      thongKe: thongKe,
    );
    // Màn 1 không đặt cọc nhưng vẫn là ván chính thức: chỉ ván thắng hợp lệ
    // mới được xin phiếu vàng. Ván thua vẫn gửi nhật ký để giữ dữ liệu AI,
    // nhưng tuyệt đối không phát thưởng.
    final coPhieu = !man.chiChoiLocal && thang;
    final guiNhatKy = !man.chiChoiLocal;
    if (coPhieu) {
      kq = kq.voiPhieu('Đang gửi ván lên máy chủ trọng tài…');
    }
    ketQuaVan.value = kq;

    if (thang || guiNhatKy) {
      if (!_daGuiVaXinPhieu) {
        _daGuiVaXinPhieu = true;
        final dangNhan = _guiVaXinPhieu(nk, maVan, kq, coPhieu);
        _dangNhanThuong = dangNhan;
        unawaited(dangNhan);
      }
    }
  }

  Future<void> _guiVaXinPhieu(
    Map<String, Object> nk,
    String maVan,
    KetQuaVan kq,
    bool coPhieu,
  ) async {
    final pv = phienVi;
    final daGui = GuiNhatKy.daCauHinh
        ? await GuiNhatKy.gui(nk, csrfToken: auth?.csrfToken)
        : false;

    if (daGui && kq.thang && auth != null && maVan.isNotEmpty) {
      final mayChuHuyHieu = MayChuHuyHieu();
      final badge = await mayChuHuyHieu.danhGia(
        maVan: maVan,
        csrfToken: auth?.csrfToken,
      );
      mayChuHuyHieu.dong();
      final moi = (badge?['new_badges'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList();
      if (moi != null && moi.isNotEmpty && identical(ketQuaVan.value, kq)) {
        final badgeId = moi.first['badge_id'];
        if (badgeId is int) {
          huyHieuDaNhan.value = {...huyHieuDaNhan.value, badgeId};
        }
        kq = kq.voiHuyHieu(moi.first);
        ketQuaVan.value = kq;
        overlays.remove(LopPhu.ketThuc);
        overlays.add(LopPhu.huyHieu);
      }
    }

    void datTrangThai(String p) {
      if (!identical(ketQuaVan.value, kq)) return;
      kq = kq.voiPhieu(p);
      ketQuaVan.value = kq;
    }

    BigInt? soVang;
    if (pv != null && coPhieu && daGui) {
      if (!pv.daKetNoi) {
        if (auth?.canEnterGame == true && auth?.walletAddress != null) {
          await pv.ketNoiDaXacThuc(auth!.walletAddress!);
        }
      }
      if (pv.daKetNoi) {
        soVang = await pv.xinPhieuChoVan(maVan);
      } else {
        // ketNoiDaXacThuc có thể hoàn tất kết nối ngay trong nhánh trên.
        // Khi đó phải xin lại phiếu và giữ kết quả để luồng claim/faucet chạy;
        // trước đây kết quả bị bỏ nên màn thắng báo thiếu phiếu dù máy chủ đã cấp.
        final phieu = await pv.xinPhieuChoVan(maVan);
        if (pv.daKetNoi) soVang = phieu;
      }
    }

    final soVangCong = soVang != null
        ? (soVang + (kq.man.mienPhi ? BigInt.zero : BigInt.from(kq.man.coc)))
        : (kq.thang && !kq.man.chiChoiLocal
              ? BigInt.from(
                  kq.xu + (kq.man.mienPhi ? 0 : (kq.man.coc + kq.man.thuong)),
                )
              : BigInt.zero);

    // Phiếu chỉ là bằng chứng thưởng đã ký, chưa phải số dư ví. Khi đã có ví
    // kết nối, claim ngay bằng giao dịch nhanVang; PhienVi chỉ cập nhật topbar
    // sau khi đọc lại số dư on-chain thành công. Nếu thiếu ETH/từ chối giao
    // dịch, phiếu vẫn chờ nhận và tuyệt đối không cộng vàng local.
    var daGhiOnChain = false;
    if (soVang != null && pv != null && pv.daKetNoi) {
      daGhiOnChain = await pv.nhanTatCa();
    }

    if (daGhiOnChain) {
      datTrangThai(
        'Đã ghi +$soVang vàng lên blockchain'
        '${kq.man.mienPhi ? '' : ' (+${kq.man.coc} cọc hoàn lại)'}.',
      );
    } else if (soVang != null) {
      final lyDo = pv?.thongBao;
      datTrangThai(
        lyDo == null || lyDo.isEmpty
            ? 'Phiếu +$soVang vàng đang chờ nhận on-chain.'
            : 'Phiếu +$soVang vàng chưa ghi on-chain: $lyDo',
      );
    } else if (soVangCong > BigInt.zero) {
      // Xin phiếu có thể bị trọng tài từ chối (ví dụ đã chạm hạn mức vàng
      // trong ngày). Không che mất lý do thật bằng thông báo "chưa có phiếu",
      // vì người chơi không thể tự biết cần chờ hay sửa cấu hình nào.
      final lyDo = pv?.thongBao;
      datTrangThai(
        lyDo == null || lyDo.isEmpty
            ? 'Đủ điều kiện nhưng chưa có phiếu blockchain; chưa cộng vàng vào topbar.'
            : 'Chưa cấp phiếu blockchain: $lyDo',
      );
    } else if (!daGui && coPhieu) {
      datTrangThai(
        'Không gửi được ván lên máy chủ '
        '— ván này không đổi được thành vàng.',
      );
    } else if (pv != null && !pv.daKetNoi && coPhieu) {
      datTrangThai(
        'Kết nối MetaMask (Cửa hàng) '
        'để nhận vàng của ván này.',
      );
    }

    // Ghi nhận tiến trình khi thắng màn:
    if (kq.thang && kq.man.id >= 1 && kq.man.id <= 6) {
      unawaited(
        tienTrinh
            .xacNhanHoanThanhMan(
              stageId: kq.man.id,
              evidenceType: 'referee_log',
              evidence: maVan,
            )
            .catchError((Object e, StackTrace s) {
              debugPrint('Lỗi đồng bộ tiến trình màn ${kq.man.id}: $e');
              return false;
            }),
      );
    }
  }

  void _docJoystick() {
    final j = joystick;
    final g = george;

    if (j == null || g == null) return;

    if (j.direction == JoystickDirection.idle) {
      g.huongJoystick.setZero();
    } else {
      g.huongJoystick.setFrom(j.relativeDelta);
    }
  }

  void _ghimCameraTrongBanDo() {
    if (!hasLayout) return;
    final zoom = camera.viewfinder.zoom;
    if (zoom <= 0) return;

    final nuaW = size.x / (2 * zoom);
    final nuaH = size.y / (2 * zoom);
    final bd = banDo.kichThuoc;
    final vf = camera.viewfinder;

    if (bd.x <= nuaW * 2) {
      vf.position.x = bd.x / 2;
    } else {
      vf.position.x = vf.position.x.clamp(nuaW, bd.x - nuaW);
    }

    if (bd.y <= nuaH * 2) {
      vf.position.y = bd.y / 2;
    } else {
      vf.position.y = vf.position.y.clamp(nuaH, max(nuaH, bd.y - nuaH));
    }
  }

  // ------------------------------------------------------------------
  // Điều hướng
  // ------------------------------------------------------------------

  void _datDieuKhien(bool bat) {
    theGioi.nhanCham = bat;
    george?.dieuKhienDuoc = bat;

    if (!bat) george?.viTriDich = null;
  }

  void _anTatCaLopPhu() {
    overlays.remove(LopPhu.menu);
    overlays.remove(LopPhu.caiDat);
    overlays.remove(LopPhu.tamDung);
    overlays.remove(LopPhu.ketThuc);
    overlays.remove(LopPhu.huyHieu);
    overlays.remove(LopPhu.cuaHang);
    overlays.remove(LopPhu.chonMan);
    overlays.remove(LopPhu.khoDo);
    overlays.remove(LopPhu.rungRuong);
    overlays.remove(LopPhu.quaTang);
    overlays.remove(LopPhu.nutBan);
  }

  /// Chơi màn [m]. Màn có cọc: [maVan] và [ve] đã đăng ký với máy chủ (PhienVi.chuanBiMan).
  /// false = không nạp được bản đồ hoặc màn chưa được mở khóa (màn đang chơi giữ nguyên).
  Future<bool> choiMan(
    ManChoi m, {
    String? maVan,
    int ve = 0,
    DateTime? batDauThat,
  }) async {
    if (!tienTrinhWorldMap.duocChoi(m.id)) return false;
    try {
      await _doiBanDo(
        m,
      ); // đổi bản đồ TRƯỚC, rồi mới đổi màn — hai thứ luôn khớp nhau
    } catch (e) {
      debugPrint('Không đổi được bản đồ ${m.tep}: $e');
      return false;
    }

    manHienTai = m;
    veDangChoi = ve;

    this.batDauThat = maVan == null ? null : (batDauThat ?? DateTime.now());

    batDauVanMoi(maVan: maVan);
    return true;
  }

  Future<void> batDauVanMoi({String? maVan}) async {
    if (!tienTrinhWorldMap.duocChoi(manHienTai.id)) {
      moChonMan();
      return;
    }
    if (!manHienTai.mienPhi && maVan == null) {
      moChonMan();
      return;
    }

    // Nút "Chơi lại" từ màn thắng đi thẳng vào đây, không qua màn chọn màn.
    // Đăng ký ticket trước khi dựng ván để một chiến thắng mới luôn đủ điều
    // kiện xin phiếu vàng như luồng "Chơi" ở màn chọn màn.
    if (!manHienTai.chiChoiLocal && maVan == null) {
      final pv = phienVi;
      final authController = auth;
      if (pv == null ||
          authController == null ||
          !authController.canEnterGame ||
          authController.walletAddress == null) {
        pv?.baoLoi('Cần đăng nhập và xác thực ví để nhận vàng từ ván chơi.');
        return;
      }
      if (!pv.daKetNoi) {
        final daKetNoi = await pv.ketNoiDaXacThuc(
          authController.walletAddress!,
        );
        if (!daKetNoi) return;
      }
      final maVanMoi = nhatKy.sinhMaVan();
      try {
        await pv.mayChu.batDauMan(
          maVan: maVanMoi,
          vi: pv.diaChi!,
          man: manHienTai.id,
          ve: 0,
        );
        maVan = maVanMoi;
      } catch (e) {
        pv.baoLoi('Không đăng ký được màn chơi với máy chủ: $e');
        return;
      }
    }

    ketQuaVan.value = null;
    _daGuiVaXinPhieu = false;

    _dungVan(maVan: maVan);
    _vanDangDienRa = true;

    _anTatCaLopPhu();
    overlays.add(LopPhu.nutBan);

    trangThai = TrangThaiChoi.dangChoi;
    _datDieuKhien(true);

    resumeEngine();
    AmThanh.batNhacNen();
  }

  void tamDung() {
    if (trangThai != TrangThaiChoi.dangChoi) return;

    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);

    george?.huongJoystick.setZero();

    AmThanh.tamDungNhac();
    overlays.remove(LopPhu.nutBan);
    overlays.add(LopPhu.tamDung);
    pauseEngine();
  }

  void tiepTuc() {
    if (trangThai != TrangThaiChoi.tamDung) return;

    overlays.remove(LopPhu.tamDung);
    overlays.add(LopPhu.nutBan);
    trangThai = TrangThaiChoi.dangChoi;

    _datDieuKhien(true);
    AmThanh.tiepTucNhac();
    resumeEngine();
  }

  void veMenu() {
    _guiNhatKy('bo');

    _anTatCaLopPhu();
    overlays.add(LopPhu.menu);

    trangThai = TrangThaiChoi.tamDung;
    _datDieuKhien(false);

    AmThanh.dungNhacNen();
    _dungVan();
    pauseEngine();
  }

  void moCuaHang() {
    final dangNhan = _dangNhanThuong;
    final dangDongBo = _dangDongBoVi;
    if (dangNhan == null && dangDongBo == null) {
      overlays.add(LopPhu.cuaHang);
      return;
    }

    // Không mở cửa hàng khi ví đăng nhập hoặc phiếu của ván vừa thắng vẫn
    // đang được đồng bộ. Nếu mở quá sớm, giao diện có thể tạm hiện 0 và
    // giao dịch mua có thể dùng danh sách phiếu chưa đầy đủ.
    final cho = <Future<void>>[
      if (dangDongBo != null) dangDongBo,
      if (dangNhan != null) dangNhan,
    ];
    unawaited(() async {
      await Future.wait(cho);
      if (isMounted) overlays.add(LopPhu.cuaHang);
    }());
  }

  void moRungRuong() {
    // Đợi hết lượt xử lý pointer/layout hiện tại rồi mới đổi overlay, tránh
    // assertion của Flutter khi vừa xóa overlay cũ vừa thêm overlay mới.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final menuDangMo = overlays.isActive(LopPhu.menu);
      _anTatCaLopPhu();
      if (menuDangMo) overlays.add(LopPhu.menu);
      if (!overlays.isActive(LopPhu.rungRuong)) {
        overlays.add(LopPhu.rungRuong);
      }
    });
  }

  void moQuaTang() => overlays.add(LopPhu.quaTang);

  void dongHuyHieu() {
    overlays.remove(LopPhu.huyHieu);
    overlays.add(LopPhu.ketThuc);
  }

  void dongCuaHang() => overlays.remove(LopPhu.cuaHang);

  void dongRungRuong() => overlays.remove(LopPhu.rungRuong);

  void dongQuaTang() => overlays.remove(LopPhu.quaTang);

  void moChonMan() => overlays.add(LopPhu.chonMan);

  void dongChonMan() => overlays.remove(LopPhu.chonMan);

  void moCaiDat() => overlays.add(LopPhu.caiDat);

  void dongCaiDat() => overlays.remove(LopPhu.caiDat);

  /// Kho đồ chỉ mở từ Menu, không mở giữa ván.
  void moKhoDo() {
    if (trangThai != TrangThaiChoi.tamDung) return;
    if (!overlays.isActive(LopPhu.menu)) overlays.add(LopPhu.menu);

    overlays.add(LopPhu.khoDo);
  }

  /// Menu ở bên dưới nên đóng Kho đồ sẽ trở lại Menu.
  void dongKhoDo() {
    overlays.remove(LopPhu.khoDo);
  }
}
