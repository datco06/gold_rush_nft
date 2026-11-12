import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gold_rush/blockchain/abi.dart' as abi;
import 'package:gold_rush/blockchain/loi_hop_dong.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/blockchain/sbt/sbt_model.dart';
import 'package:gold_rush/blockchain/sbt/sbt_service.dart';
import 'package:gold_rush/blockchain/vi.dart';
import 'package:gold_rush/blockchain/vi_khong_ho_tro.dart'
    as nen_tang_khong_ho_tro;

import '../vi_gia.dart';

// Sinh bằng viem từ ABI biên dịch thật; không phải chữ ký Backend thật.
final mau = jsonDecode(
  File('test/blockchain/sbt/sbt_abi_mau.json').readAsStringSync(),
) as Map<String, dynamic>;
final calls = Map<String, String>.from(mau['calls'] as Map);
final results = Map<String, String>.from(mau['results'] as Map);
final errors = Map<String, String>.from(mau['errors'] as Map);
final cauHinh = CauHinhSBT(
  chainId: mau['chainId'] as int,
  hopDong: mau['contract'] as String,
);
final huyHieu = bangThanhTuuSBT[1];

PhieuSBTDaKy phieuThu({String? player, int? id, CauHinhSBT? config}) {
  final p = PhieuSBT.fromJson(Map<String, dynamic>.from(mau['voucher'] as Map));
  return PhieuSBTDaKy(
    phieu: PhieuSBT(
      player: player ?? p.player,
      achievementId: id ?? p.achievementId,
      nonce: p.nonce,
      deadline: p.deadline,
    ),
    chuKy: mau['signature'] as String,
    cauHinh: config ?? cauHinh,
  );
}

class ViSBTGia extends ViGia {
  bool hoTro = true;
  bool mintKhiCoBienLai = true;
  final Set<int> daCo = {};
  final List<String> diaChiDaGoi = [];
  void Function(String data)? sauKhiDoc;
  Future<void> Function()? truocGui;

  ViSBTGia() : super(taiKhoan: [mau['player'] as String]) {
    for (final key in [
      'typehash',
      'max',
      'domain',
      'signer',
      'achievementOfToken',
      'ownerOf',
    ]) {
      ketQuaGoi[calls[key]!] = results[key]!;
    }
  }

  @override
  bool get coSan => hoTro;

  @override
  Future<String> goi({
    required String toi,
    required String duLieu,
    String? tu,
  }) async {
    diaChiDaGoi.add(toi);
    if (tu != null) return super.goi(toi: toi, duLieu: duLieu, tu: tu);
    final String answer;
    if (ketQuaGoi.containsKey(duLieu)) {
      answer = ketQuaGoi[duLieu]!;
    } else if (duLieu.startsWith('0xab5eba16')) {
      final id = BigInt.parse(duLieu.substring(74), radix: 16).toInt();
      answer = daCo.contains(id) ? results['hasTrue']! : results['hasFalse']!;
    } else {
      throw StateError('RPC không được hỗ trợ trong mock: $duLieu');
    }
    sauKhiDoc?.call(duLieu);
    return answer;
  }

  @override
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  }) async {
    await truocGui?.call();
    return super.guiGiaoDich(tu: tu, toi: toi, duLieu: duLieu, gas: gas);
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    final receipt = await super.bienLai(maGiaoDich);
    if (receipt?.thanhCong == true && mintKhiCoBienLai) daCo.add(2);
    return receipt;
  }
}

class NguonGia implements NguonPhieuSBT {
  int soLan = 0;
  Map<String, Object>? yeuCau;
  PhieuSBTDaKy? traVe;
  @override
  Future<PhieuSBTDaKy> xinPhieu({
    required String player,
    required int achievementId,
    required int chainId,
    required String hopDong,
  }) async {
    soLan++;
    yeuCau = {
      'player': player,
      'achievementId': achievementId,
      'chainId': chainId,
      'hopDong': hopDong,
    };
    return traVe ?? phieuThu();
  }
}

({DichVuSBT service, PhienVi phien, ViSBTGia vi}) setup({
  NguonPhieuSBT? nguon,
  ViSBTGia? wallet,
}) {
  final vi = wallet ?? ViSBTGia();
  final client = MockClient(
    (_) async =>
        throw StateError('SBT không được gọi API vàng hoặc endpoint tự đặt.'),
  );
  final phien = PhienVi(
    vi: vi,
    mayChu: MayChuPhieu(mayChu: '', client: client),
  )..diaChi = mau['player'] as String;
  addTearDown(() {
    phien.dispose();
    client.close();
  });
  final service = DichVuSBT(
    phienVi: phien,
    cauHinh: cauHinh,
    nguonPhieu: nguon,
    choToiDa: const Duration(seconds: 3),
    nhipKiemTra: const Duration(seconds: 1),
    ngu: (_) async {},
  );
  return (service: service, phien: phien, vi: vi);
}

Matcher loiVi({LoaiLoiVi? loai, String? thongBao}) {
  var matcher = isA<LoiVi>();
  if (loai != null) matcher = matcher.having((e) => e.loai, 'loai', loai);
  if (thongBao != null) {
    matcher = matcher.having((e) => e.thongBao, 'thongBao', contains(thongBao));
  }
  return throwsA(matcher);
}

void main() {
  group('Dữ liệu Backend và cấu hình', () {
    test('không chấp nhận địa chỉ zero, sai dạng hoặc chain không hợp lệ', () {
      for (final address in ['', '0x123', '0x${'0' * 40}', '0x${'z' * 40}']) {
        expect(
          () => CauHinhSBT(chainId: 31337, hopDong: address),
          throwsFormatException,
        );
      }
      expect(
        () => CauHinhSBT(chainId: 0, hopDong: cauHinh.hopDong),
        throwsArgumentError,
      );
    });

    test('phiếu JSON giữ đúng bốn trường và deadline uint256 lớn', () {
      final p = phieuThu().phieu;
      expect(p.toJson(), {
        ...Map<String, dynamic>.from(mau['voucher'] as Map),
        'achievementId': 2,
      });
      expect(p.deadline, (BigInt.one << 100) + BigInt.from(123));
      for (final value in ['0', '6', (BigInt.one << 200).toString(), -1, 1.5]) {
        expect(
          () => PhieuSBT.fromJson({...p.toJson(), 'achievementId': value}),
          throwsA(isA<Exception>()),
        );
      }
      for (final deadline in [
        -1,
        (BigInt.one << 256).toString(),
        9007199254740992,
      ]) {
        expect(
          () => PhieuSBT.fromJson({...p.toJson(), 'deadline': deadline}),
          throwsA(anything),
        );
      }
    });

    test('từ chối nonce và chữ ký sai độ dài/không phải hex', () {
      final p = phieuThu().phieu;
      expect(
        () => PhieuSBT(
          player: p.player,
          achievementId: 2,
          nonce: '0x123',
          deadline: p.deadline,
        ),
        throwsFormatException,
      );
      for (final signature in ['0x', '0x${'g' * 130}']) {
        expect(
          () => PhieuSBTDaKy(phieu: p, chuKy: signature, cauHinh: cauHinh),
          throwsFormatException,
        );
      }
    });

    test(
      'interface Backend nhận đúng ví, chain, hợp đồng và achievement',
      () async {
        final source = NguonGia();
        final s = setup(nguon: source);
        final p = await s.service.xinPhieu(2);
        expect(p.phieu.achievementId, 2);
        expect(source.yeuCau, {
          'player': mau['player'],
          'achievementId': 2,
          'chainId': cauHinh.chainId,
          'hopDong': cauHinh.hopDong,
        });
        expect(s.vi.daGui, isEmpty);
      },
    );

    test(
      'không tự dựng endpoint Backend hoặc dùng eligible để tự mint',
      () async {
        final s = setup();
        await expectLater(
          s.service.nhanThanhTuu(
            huyHieu.copyWith(
              eligibilityStatus: TrangThaiDieuKienSBT.duDieuKien,
            ),
          ),
          loiVi(thongBao: 'nguồn phiếu'),
        );
        expect(s.vi.daGui, isEmpty);
        expect(s.phien.dangXuLy, isFalse);
      },
    );
  });

  group('Ví, chain và hợp đồng', () {
    test('nền tảng chưa hỗ trợ ví báo lỗi, không giả lập sở hữu hoặc nhận thành công', () async {
      final client = MockClient((_) async => throw StateError('Không gọi API'));
      final phien = PhienVi(
        vi: nen_tang_khong_ho_tro.taoVi(),
        mayChu: MayChuPhieu(mayChu: '', client: client),
      );
      addTearDown(() {
        phien.dispose();
        client.close();
      });
      final service = DichVuSBT(phienVi: phien, cauHinh: cauHinh);
      expect(service.coHoTroVi, isFalse);
      await expectLater(service.taiDanhSach(), loiVi(thongBao: 'chưa có ví'));
      final states = <ThanhTuuSBT>[];
      await expectLater(
        service.nhanThanhTuu(
          huyHieu,
          phieu: phieuThu(),
          khiCapNhat: states.add,
        ),
        loiVi(thongBao: 'chưa có ví'),
      );
      expect(states.last.claimStatus, TrangThaiNhanSBT.thatBai);
      expect(states.every((state) => !state.owned), isTrue);
    });

    test('không tự mở kết nối ví khi phiên chưa có địa chỉ', () async {
      final s = setup();
      s.phien.diaChi = null;
      await expectLater(
        s.service.taiDanhSach(),
        loiVi(thongBao: 'Chưa kết nối'),
      );
      expect(s.vi.diaChiDaGoi, isEmpty);
    });

    test(
      'đổi tài khoản được chọn, kể cả ví cũ còn được cấp quyền, phải dừng',
      () async {
        final s = setup();
        s.vi.danhSachTaiKhoan = ['0x${'e' * 40}', mau['player'] as String];
        await expectLater(
          s.service.taiThanhTuu(huyHieu),
          loiVi(loai: LoaiLoiVi.doiTaiKhoan),
        );
        expect(s.vi.daGui, isEmpty);
      },
    );

    test('đọc hồ sơ sai chain báo lỗi, không tự xin chuyển mạng', () async {
      final s = setup();
      s.vi.mang = 1;
      await expectLater(
        s.service.taiThanhTuu(huyHieu),
        loiVi(thongBao: 'sai mạng'),
      );
      expect(s.vi.soLanChuyenMang, 0);
    });

    test('nhận SBT tái sử dụng BoGiaoDich để chuyển sang đúng chain', () async {
      final s = setup();
      s.vi.mang = 1;
      expect(
        (await s.service.nhanThanhTuu(huyHieu, phieu: phieuThu())).owned,
        isTrue,
      );
      expect(s.vi.soLanChuyenMang, 1);
    });

    test('từ chối chuyển chain không gửi giao dịch', () async {
      final s = setup();
      s.vi
        ..mang = 1
        ..mangSauKhiChuyen = 1;
      await expectLater(
        s.service.nhanThanhTuu(huyHieu, phieu: phieuThu()),
        loiVi(thongBao: 'mạng'),
      );
      expect(s.vi.daGui, isEmpty);
      expect(s.phien.dangXuLy, isFalse);
    });

    test(
      'địa chỉ không có bytecode không được coi là chưa sở hữu hợp lệ',
      () async {
        final s = setup();
        s.vi.maByte = '0x';
        await expectLater(
          s.service.taiDanhSach(),
          loiVi(thongBao: 'Không thấy hợp đồng'),
        );
        await expectLater(
          s.service.nhanThanhTuu(huyHieu, phieu: phieuThu()),
          loiVi(thongBao: 'Không thấy hợp đồng'),
        );
        expect(s.vi.daGui, isEmpty);
      },
    );

    test(
      'hợp đồng khác có bytecode nhưng typehash sai vẫn bị từ chối',
      () async {
        final s = setup();
        s.vi.ketQuaGoi[calls['typehash']!] = '0x${'0' * 64}';
        await expectLater(
          s.service.taiDanhSach(),
          loiVi(thongBao: 'không khớp hợp đồng'),
        );
      },
    );

    test('domain EIP-712 sai name/version bị từ chối', () async {
      final s = setup();
      s.vi.ketQuaGoi[calls['domain']!] = results['wrongDomain']!;
      await expectLater(
        s.service.taiDanhSach(),
        loiVi(thongBao: 'EIP-712 domain'),
      );
    });

    for (final result in ['0x', '0x1234', '0x${abi.tu(BigInt.two)}']) {
      test(
        'không biến kết quả hasAchievement sai dạng thành owned: $result',
        () async {
          final s = setup();
          s.vi.ketQuaGoi[calls['hasAchievement']!] = result;
          await expectLater(s.service.taiThanhTuu(huyHieu), loiVi());
        },
      );
    }
  });

  group('Đọc model từ Blockchain', () {
    test('owned chỉ lấy từ hasAchievement; tokenId cache bị bỏ', () async {
      final s = setup();
      final cached = huyHieu.copyWith(
        ownershipStatus: TrangThaiSoHuuSBT.daSoHuu,
        tokenId: BigInt.from(999),
      );
      final no = await s.service.taiThanhTuu(cached);
      expect(no.ownershipStatus, TrangThaiSoHuuSBT.chuaSoHuu);
      expect(no.tokenId, isNull);
      s.vi.daCo.add(2);
      final yes = await s.service.taiThanhTuu(huyHieu);
      expect(yes.owned, isTrue);
      expect(yes.tokenId, isNull);
      expect(
        s.vi.diaChiDaGoi.every((address) => address == cauHinh.hopDong),
        isTrue,
      );
    });

    test('tải cả danh mục và đọc đúng signer/token ID lớn không phải achievementId', () async {
      final s = setup();
      s.vi.daCo.add(2);
      final list = await s.service.taiDanhSach();
      expect(list.length, 5);
      expect(list.where((sbt) => sbt.owned).map((sbt) => sbt.achievementId), [
        2,
      ]);
      expect(await s.service.docSigner(), mau['signer']);
      final tokenId = BigInt.parse(mau['tokenId'] as String);
      final token = await s.service.docToken(tokenId);
      expect(token.tokenId, tokenId);
      expect(token.achievementId, 2);
      expect(token.owner, mau['player']);
    });

    test('token không tồn tại trả custom error đúng', () async {
      final s = setup();
      s.vi.sauKhiDoc = (data) {
        if (data == calls['achievementOfToken']) {
          throw taoLoiVi(duLieu: {'data': errors['ERC721NonexistentToken']});
        }
      };
      await expectLater(
        s.service.docToken(BigInt.parse(mau['tokenId'] as String)),
        loiVi(
          loai: LoaiLoiVi.hopDongTuChoi,
          thongBao: 'ERC721NonexistentToken',
        ),
      );
    });

    test('đổi phiên trong lúc đọc không trả model sở hữu của ví cũ', () async {
      final s = setup();
      s.vi.daCo.add(2);
      s.vi.sauKhiDoc = (data) {
        if (data == calls['hasAchievement']) s.phien.diaChi = '0x${'e' * 40}';
      };
      await expectLater(
        s.service.taiThanhTuu(huyHieu),
        loiVi(loai: LoaiLoiVi.doiTaiKhoan),
      );
    });
  });

  group('Nhận SBT', () {
    test('calldata khớp từng byte với viem, chờ biên lai rồi mới owned và có đủ tiến độ', () async {
      final s = setup();
      s.vi.bienLaiLanLuot = [null, const BienLai(thanhCong: true)];
      final states = <ThanhTuuSBT>[];
      final hashes = <String>[];
      final result = await s.service.nhanThanhTuu(
        huyHieu,
        phieu: phieuThu(),
        khiCapNhat: (state) {
          states.add(state);
          if (s.vi.soLanHoiBienLai < 2) expect(state.owned, isFalse);
        },
        khiDaGui: hashes.add,
      );
      expect(s.vi.daGui, [calls['claimSBT']]);
      expect(s.vi.gasDaGui.single, BigInt.from(120000));
      expect(hashes, ['0x${'f' * 64}']);
      expect(states.map((sbt) => sbt.claimStatus), [
        TrangThaiNhanSBT.chuaBatDau,
        TrangThaiNhanSBT.choXacNhanVi,
        TrangThaiNhanSBT.dangGui,
        TrangThaiNhanSBT.choXacNhanChuoi,
        TrangThaiNhanSBT.thanhCong,
      ]);
      expect(result.owned, isTrue);
      expect(result.tokenId, isNull);
      expect(s.phien.dangXuLy, isFalse);
    });

    test('nhận qua nguồn inject và không gọi API cửa hàng', () async {
      final source = NguonGia();
      final s = setup(nguon: source);
      expect((await s.service.nhanThanhTuu(huyHieu)).owned, isTrue);
      expect(source.soLan, 1);
    });

    test(
      'đã sở hữu trên chuỗi không xin phiếu và không gửi lại giao dịch',
      () async {
        final source = NguonGia();
        final s = setup(nguon: source);
        s.vi.daCo.add(2);
        final result = await s.service.nhanThanhTuu(huyHieu);
        expect(result.owned, isTrue);
        expect(source.soLan, 0);
        expect(s.vi.daGui, isEmpty);
      },
    );

    for (final bad in ['player', 'achievementId', 'chainId', 'contract']) {
      test('phiếu sai $bad bị chặn trước khi gửi', () async {
        final s = setup();
        final phieu = phieuThu(
          player: bad == 'player' ? '0x${'e' * 40}' : null,
          id: bad == 'achievementId' ? 3 : null,
          config: bad == 'chainId'
              ? CauHinhSBT(chainId: 1, hopDong: cauHinh.hopDong)
              : bad == 'contract'
              ? CauHinhSBT(chainId: 31337, hopDong: '0x${'e' * 40}')
              : null,
        );
        await expectLater(
          s.service.nhanThanhTuu(huyHieu, phieu: phieu),
          loiVi(thongBao: 'Phiếu SBT'),
        );
        expect(s.vi.daGui, isEmpty);
      });
    }

    for (final name in errors.keys.where(
      (key) => key != 'ERC721NonexistentToken',
    )) {
      test(
        'mô phỏng từ chối $name có câu lỗi SBT, không mở giao dịch',
        () async {
          final s = setup();
          final states = <ThanhTuuSBT>[];
          s.vi.loiMoPhong = taoLoiVi(
            ma: -32603,
            duLieu: {
              'data': {
                'originalError': {'data': errors[name]},
              },
            },
          );
          await expectLater(
            s.service.nhanThanhTuu(
              huyHieu,
              phieu: phieuThu(),
              khiCapNhat: states.add,
            ),
            loiVi(loai: LoaiLoiVi.hopDongTuChoi, thongBao: name),
          );
          expect(s.vi.daGui, isEmpty);
          expect(states.last.claimStatus, TrangThaiNhanSBT.thatBai);
          expect(states.last.owned, isFalse);
        },
      );
    }

    test('MetaMask 4001 là đã hủy, không phải thành công', () async {
      final s = setup();
      s.vi.loiKhiGui = taoLoiVi(ma: 4001, thongDiep: 'User rejected');
      final states = <ThanhTuuSBT>[];
      await expectLater(
        s.service.nhanThanhTuu(
          huyHieu,
          phieu: phieuThu(),
          khiCapNhat: states.add,
        ),
        loiVi(loai: LoaiLoiVi.tuChoi),
      );
      expect(states.last.claimStatus, TrangThaiNhanSBT.daHuy);
      expect(states.last.owned, isFalse);
      expect(s.vi.daGui, isEmpty);
    });

    test('giao dịch vào khối nhưng thất bại không cấp quyền sở hữu', () async {
      final s = setup();
      s.vi.bienLaiLanLuot = [const BienLai(thanhCong: false)];
      final states = <ThanhTuuSBT>[];
      await expectLater(
        s.service.nhanThanhTuu(
          huyHieu,
          phieu: phieuThu(),
          khiCapNhat: states.add,
        ),
        loiVi(loai: LoaiLoiVi.hopDongTuChoi),
      );
      expect(states.last.claimStatus, TrangThaiNhanSBT.thatBai);
      expect(states.every((model) => !model.owned), isTrue);
    });

    test('không đủ ETH bị chặn trước khi mở MetaMask', () async {
      final s = setup();
      s.vi.soDuEth = BigInt.zero;
      await expectLater(
        s.service.nhanThanhTuu(huyHieu, phieu: phieuThu()),
        loiVi(loai: LoaiLoiVi.thieuEth),
      );
      expect(s.vi.daGui, isEmpty);
    });

    test(
      'timeout vẫn là đang xác nhận, không báo giao dịch thất bại hay owned',
      () async {
        final s = setup();
        s.vi.bienLaiLanLuot = [null];
        final states = <ThanhTuuSBT>[];
        await expectLater(
          s.service.nhanThanhTuu(
            huyHieu,
            phieu: phieuThu(),
            khiCapNhat: states.add,
          ),
          loiVi(loai: LoaiLoiVi.chuaXacNhan),
        );
        expect(states.last.claimStatus, TrangThaiNhanSBT.choXacNhanChuoi);
        expect(states.last.owned, isFalse);
      },
    );

    test('biên lai thành công vẫn phải đọc lại hasAchievement', () async {
      final s = setup();
      s.vi.mintKhiCoBienLai = false;
      final states = <ThanhTuuSBT>[];
      await expectLater(
        s.service.nhanThanhTuu(
          huyHieu,
          phieu: phieuThu(),
          khiCapNhat: states.add,
        ),
        loiVi(loai: LoaiLoiVi.chuaXacNhan),
      );
      expect(states.last.claimStatus, TrangThaiNhanSBT.choXacNhanChuoi);
      expect(states.last.owned, isFalse);
    });

    test('giao dịch tăng tốc được nhận ra từ trạng thái trên chuỗi', () async {
      final s = setup();
      s.vi.bienLaiLanLuot = [null];
      s.vi.khiGui = (_) => s.vi.daCo.add(2);
      expect(
        (await s.service.nhanThanhTuu(huyHieu, phieu: phieuThu())).owned,
        isTrue,
      );
    });

    test('đổi ví sau khi gửi không công bố owned cho ngữ cảnh mới', () async {
      final s = setup();
      s.vi.khiGui = (_) => s.phien.diaChi = '0x${'e' * 40}';
      final states = <ThanhTuuSBT>[];
      await expectLater(
        s.service.nhanThanhTuu(
          huyHieu,
          phieu: phieuThu(),
          khiCapNhat: states.add,
        ),
        loiVi(loai: LoaiLoiVi.doiTaiKhoan),
      );
      expect(states.every((state) => !state.owned), isTrue);
      expect(states.last.claimStatus, TrangThaiNhanSBT.choXacNhanChuoi);
      expect(s.phien.dangXuLy, isFalse);
    });

    test('đổi chain sau khi gửi không công bố owned trên sai mạng', () async {
      final s = setup();
      s.vi.khiGui = (_) => s.vi.mang = 1;
      final states = <ThanhTuuSBT>[];
      await expectLater(
        s.service.nhanThanhTuu(
          huyHieu,
          phieu: phieuThu(),
          khiCapNhat: states.add,
        ),
        loiVi(thongBao: 'sai mạng'),
      );
      expect(states.last.claimStatus, TrangThaiNhanSBT.choXacNhanChuoi);
      expect(states.last.owned, isFalse);
    });

    test(
      'tôn trọng khóa giao dịch và khóa xác nhận màn của phiên ví hiện tại',
      () async {
        final s = setup();
        s.phien.dangXuLy = true;
        await expectLater(
          s.service.nhanThanhTuu(huyHieu, phieu: phieuThu()),
          loiVi(loai: LoaiLoiVi.dangCho),
        );
        expect(s.phien.dangXuLy, isTrue);
        s.phien
          ..dangXuLy = false
          ..dangHoi = true;
        await expectLater(
          s.service.nhanThanhTuu(huyHieu, phieu: phieuThu()),
          loiVi(loai: LoaiLoiVi.dangCho),
        );
        expect(s.vi.daGui, isEmpty);
      },
    );

    test('hai service cùng phiên không mở hai giao dịch đồng thời', () async {
      final s = setup();
      final gate = Completer<void>();
      final entered = Completer<void>();
      s.vi.truocGui = () {
        entered.complete();
        return gate.future;
      };
      final first = s.service.nhanThanhTuu(huyHieu, phieu: phieuThu());
      await entered.future;
      final other = DichVuSBT(phienVi: s.phien, cauHinh: cauHinh);
      await expectLater(
        other.nhanThanhTuu(huyHieu, phieu: phieuThu()),
        loiVi(loai: LoaiLoiVi.dangCho),
      );
      gate.complete();
      expect((await first).owned, isTrue);
      expect(s.vi.daGui.length, 1);
    });
  });
}
