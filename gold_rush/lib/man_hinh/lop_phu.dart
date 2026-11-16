import 'dart:async';

import 'package:flutter/material.dart';

import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import '../gold_rush_game.dart';
import '../huong_dan/huong_dan_tan_thu.dart';
import '../man_choi.dart';
import '../ngon_ngu/ngon_ngu.dart';
import 'main_lobby.dart';

/// Khung dùng chung cho Menu, Cài đặt, Tạm dừng và Kết thúc.
class _Khung extends StatelessWidget {
  final String tieuDe;
  final String? phuDe;
  final List<Widget> noiDung;

  const _Khung({required this.tieuDe, this.phuDe, required this.noiDung});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600 || size.height < 620;
    return Material(
      color: CauHinh.mauNenMo,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 8 : 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: CauHinh.mauNen,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: CauHinh.mauChinh.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 14 : 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChuGame(
                          tieuDe,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 26 : 32,
                            fontWeight: FontWeight.w900,
                            color: CauHinh.mauChinh,
                            letterSpacing: 1,
                          ),
                        ),
                        if (phuDe != null) ...[
                          const SizedBox(height: 12),
                          ChuGame(
                            phuDe!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Color(0xFFC9D2DB),
                            ),
                          ),
                        ],
                        SizedBox(height: compact ? 12 : 24),
                        ...noiDung,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Nut extends StatelessWidget {
  final String nhan;
  final IconData bieuTuong;
  final VoidCallback khiBam;
  final bool chinh;

  const _Nut({
    required this.nhan,
    required this.bieuTuong,
    required this.khiBam,
    this.chinh = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600 || size.height < 620;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 10),
      child: SizedBox(
        width: double.infinity,
        height: compact ? 44 : 50,
        child: chinh
            ? FilledButton.icon(
                onPressed: khiBam,
                icon: Icon(bieuTuong),
                label: ChuGame(nhan),
                style: FilledButton.styleFrom(
                  backgroundColor: CauHinh.mauChinh,
                  foregroundColor: const Color(0xFF241A05),
                  textStyle: TextStyle(
                    fontSize: compact ? 14 : 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : OutlinedButton.icon(
                onPressed: khiBam,
                icon: Icon(bieuTuong),
                label: ChuGame(nhan),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CauHinh.mauChu,
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                  textStyle: TextStyle(fontSize: compact ? 14 : 16),
                ),
              ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Menu
// ------------------------------------------------------------------

class ManHinhMenu extends StatelessWidget {
  final GoldRushGame game;

  const ManHinhMenu({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return HuongDanLanDau(
      sanSang: () =>
          game.overlays.isActive(LopPhu.menu) &&
          game.overlays.activeOverlays.length == 1,
      child: GoldRushMainLobby(game: game),
    );
  }
}

// ------------------------------------------------------------------
// Cài đặt
// ------------------------------------------------------------------

class ManHinhCaiDat extends StatefulWidget {
  final GoldRushGame game;

  const ManHinhCaiDat({super.key, required this.game});

  @override
  State<ManHinhCaiDat> createState() => _ManHinhCaiDatState();
}

class _ManHinhCaiDatState extends State<ManHinhCaiDat> {
  PhienHuongDan? _huongDan;

  @override
  void dispose() {
    _huongDan?.dong();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600 || size.height < 620;
    return _Khung(
      tieuDe: 'CÀI ĐẶT',
      noiDung: [
        const ChonNgonNgu(),
        const SizedBox(height: 12),
        _Nut(
          nhan: 'Xem lại hướng dẫn',
          bieuTuong: Icons.help_outline,
          khiBam: () {
            final phien = moHuongDanTanThu(context);
            if (phien != null) _huongDan = phien;
          },
        ),
        SwitchListTile(
          value: AmThanh.batNhac,
          onChanged: (v) {
            setState(() => AmThanh.batNhac = v);
            AmThanh.datBatNhac(v);
          },
          title: const ChuGame(
            'Nhạc nền',
            style: TextStyle(color: CauHinh.mauChu),
          ),
          subtitle: const ChuGame(
            'Bản nhạc lặp 8 giây, sinh bằng mã nguồn',
            style: TextStyle(color: Color(0xFF9FAEBC), fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
          dense: compact,
          visualDensity: compact
              ? VisualDensity.compact
              : VisualDensity.standard,
        ),
        SwitchListTile(
          value: AmThanh.batHieuUng,
          onChanged: (v) {
            setState(() => AmThanh.batHieuUng = v);
          },
          title: const ChuGame(
            'Hiệu ứng âm thanh',
            style: TextStyle(color: CauHinh.mauChu),
          ),
          subtitle: const ChuGame(
            'Tiếng nhặt xu, bước chân, kẻ địch nổ',
            style: TextStyle(color: Color(0xFF9FAEBC), fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
          dense: compact,
          visualDensity: compact
              ? VisualDensity.compact
              : VisualDensity.standard,
        ),
        SwitchListTile(
          value: widget.game.doKho.batThichUng,
          onChanged: widget.game.doKho.moHinh == null
              ? null
              : (v) {
                  setState(() => widget.game.doKho.batThichUng = v);
                },
          title: const ChuGame(
            'Độ khó thích ứng (AI)',
            style: TextStyle(color: CauHinh.mauChu),
          ),
          subtitle: ChuGame(
            widget.game.doKho.moHinh == null
                ? 'Chưa có mô hình trong assets/models/'
                : 'Kẻ địch nhanh/chậm trong khoảng 80–115% '
                      'theo phong độ của bạn',
            style: const TextStyle(color: Color(0xFF9FAEBC), fontSize: 12),
          ),
          contentPadding: EdgeInsets.zero,
          dense: compact,
          visualDensity: compact
              ? VisualDensity.compact
              : VisualDensity.standard,
        ),
        if (widget.game.auth != null) ...[
          const SizedBox(height: 12),
          _Nut(
            nhan: 'Đăng xuất & Ngắt kết nối ví',
            bieuTuong: Icons.logout_rounded,
            khiBam: () {
              widget.game.dongCaiDat();
              unawaited(widget.game.auth?.logout() ?? Future.value());
            },
          ),
        ],
        SizedBox(height: compact ? 10 : 18),
        _Nut(
          nhan: 'Quay lại',
          bieuTuong: Icons.arrow_back_rounded,
          khiBam: widget.game.dongCaiDat,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Tạm dừng
// ------------------------------------------------------------------

class ManHinhTamDung extends StatelessWidget {
  final GoldRushGame game;

  const ManHinhTamDung({super.key, required this.game});

  static const Duration _duPhong = Duration(seconds: 25);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) => _xay(),
    );
  }

  Widget _xay() {
    final m = game.manHienTai;
    var canhBao = '';
    final bd = game.batDauThat;

    if (!m.mienPhi && bd != null) {
      final con = bd.add(m.hanNopNhatKy - _duPhong).difference(DateTime.now());

      canhBao =
          '\nĐồng hồ trong game đã dừng, '
          'nhưng máy chủ tính giờ thật: '
          '${con.isNegative ? 'ĐÃ QUÁ hạn nộp — ván này sẽ không được trả vàng.' : 'còn ${dinhDangGiay(con.inSeconds)} để chơi xong.'}'
          '\nVề menu bây giờ là bỏ ván '
          '— MẤT ${m.coc} vàng cọc.';
    }

    return _Khung(
      tieuDe: 'TẠM DỪNG',
      phuDe:
          'Màn ${m.id} · ${m.ten} · '
          'Điểm hiện tại: ${game.george?.diem ?? 0} · '
          'Xu hiện tại: ${game.soXuDaNhat} / ${game.tongSoXu}$canhBao',
      noiDung: [
        _Nut(
          nhan: 'Chơi tiếp',
          bieuTuong: Icons.play_arrow_rounded,
          chinh: true,
          khiBam: game.tiepTuc,
        ),
        _Nut(
          nhan: 'Cài đặt',
          bieuTuong: Icons.tune_rounded,
          khiBam: game.moCaiDat,
        ),
        _Nut(
          nhan: m.mienPhi ? 'Về menu' : 'Bỏ ván (mất cọc)',
          bieuTuong: Icons.home_rounded,
          khiBam: game.veMenu,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Kết thúc
// ------------------------------------------------------------------

class ManHinhKetThuc extends StatelessWidget {
  final GoldRushGame game;

  const ManHinhKetThuc({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<KetQuaVan?>(
      valueListenable: game.ketQuaVan,
      builder: (context, kq, _) => _xay(kq),
    );
  }

  Widget _xay(KetQuaVan? kq) {
    final thang = game.trangThai == TrangThaiChoi.thang;
    final diem = game.george?.diem ?? 0;
    final m = game.manHienTai;

    final hetGio = !thang && game.giayConLai != null && game.giayConLai! <= 0;

    final String phuDe;

    if (thang) {
      phuDe = m.mienPhi
          ? 'George đã gom hết vàng và thoát ra an toàn.'
          : 'HOÀN THÀNH màn ${m.id}! '
                'Nhận lại ${m.coc} cọc + '
                '${m.soXu} xu + ${m.thuong} thưởng.';
    } else {
      final vi = hetGio ? 'Hết giờ!' : 'George đã gục ngã giữa đường tìm vàng.';

      phuDe = m.mienPhi
          ? vi
          : '$vi Không hoàn thành màn ${m.id} '
                '— mất ${m.coc} vàng cọc.';
    }

    return _Khung(
      tieuDe: thang ? 'THẮNG RỒI!' : (hetGio ? 'HẾT GIỜ' : 'KẾT THÚC'),
      phuDe: phuDe,
      noiDung: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _Dong('Màn', '${m.id} · ${m.ten}'),
              const SizedBox(height: 6),
              _Dong('Điểm ván này', '$diem'),
              const SizedBox(height: 6),
              _Dong('Xu đã nhặt', '${game.soXuDaNhat} / ${game.tongSoXu}'),
              if (!m.mienPhi) ...[
                const SizedBox(height: 6),
                _Dong(
                  'Vàng',
                  thang ? '+${m.nhanVeKhiHoanThanh}' : '−${m.coc} (cọc)',
                ),
              ],
              const SizedBox(height: 6),
              _Dong('Điểm cao nhất', '${game.diemCaoNhat}'),
              if (game.auth?.canEnterGame == true) ...[
                const SizedBox(height: 6),
                _Dong(
                  'Tiến trình AI',
                  '${game.tienTrinh.totalCompleted}/6 màn${game.tienTrinh.isCharacterUnlocked ? ' (Mở khóa AI)' : ''}',
                ),
              ],
            ],
          ),
        ),
        if (kq?.phieu != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ChuGame(
              kq!.phieu!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFC9D2DB),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        _Nut(
          nhan: m.mienPhi ? 'Chơi lại' : 'Chọn màn',
          bieuTuong: m.mienPhi
              ? Icons.refresh_rounded
              : Icons.grid_view_rounded,
          chinh: true,
          khiBam: m.mienPhi ? () => game.batDauVanMoi() : game.moChonMan,
        ),
        _Nut(
          nhan: 'Nhận vàng · Cửa hàng',
          bieuTuong: Icons.storefront_rounded,
          khiBam: game.moCuaHang,
        ),
        _Nut(
          nhan: 'Về menu',
          bieuTuong: Icons.home_rounded,
          khiBam: game.veMenu,
        ),
      ],
    );
  }
}

/// Popup huy hiệu hiển thị trước màn hình kết quả thắng.
class ManHinhHuyHieu extends StatelessWidget {
  final GoldRushGame game;

  const ManHinhHuyHieu({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final badge = game.ketQuaVan.value?.huyHieuMoi;
    if (badge == null) return const SizedBox.shrink();
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              decoration: BoxDecoration(
                color: const Color(0xFF171A31),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFFFD166), width: 4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChuGame(
                    '✧ CHÚC MỪNG! ✧',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFD166),
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const ChuGame(
                    'Bạn đã nhận được huy hiệu mới!',
                    style: TextStyle(color: Color(0xFFE7DCC8), fontSize: 22),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 260,
                      height: 260,
                      color: Colors.white,
                      padding: const EdgeInsets.all(18),
                      child: Image.asset(
                        badge['image'] as String,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.military_tech,
                          color: Color(0xFFFFB300),
                          size: 120,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ChuGame(
                    (badge['name'] as String).toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE09A),
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ChuGame(
                    '✓ Đã ghi nhận huy hiệu SBT',
                    style: TextStyle(color: Color(0xFF9FE4C2), fontSize: 20),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      onPressed: game.dongHuyHieu,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF0F0F0),
                        foregroundColor: Colors.black,
                      ),
                      child: const ChuGame(
                        'ĐÓNG',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dong extends StatelessWidget {
  final String nhan;
  final String giaTri;

  const _Dong(this.nhan, this.giaTri);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ChuGame(
          nhan,
          style: const TextStyle(color: Color(0xFFC9D2DB), fontSize: 14),
        ),
        ChuGame(
          giaTri,
          style: const TextStyle(
            color: CauHinh.mauChu,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
