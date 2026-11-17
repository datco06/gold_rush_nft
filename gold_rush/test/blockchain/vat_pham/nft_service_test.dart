import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gold_rush/blockchain/abi.dart' as abi;
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/blockchain/vat_pham/nft_model.dart';
import 'package:gold_rush/blockchain/vat_pham/nft_service.dart';
import 'package:gold_rush/blockchain/vi.dart';
import 'package:gold_rush/blockchain/vi_khong_ho_tro.dart' as khong_ho_tro;

import '../vi_gia.dart';

final fixture = jsonDecode(
  File('test/blockchain/vat_pham/nft_abi_mau.json').readAsStringSync(),
) as Map<String, dynamic>;
final calls = Map<String, String>.from(fixture['calls'] as Map);
final results = Map<String, String>.from(fixture['results'] as Map);
final errors = Map<String, String>.from(fixture['errors'] as Map);
final config = CauHinhNFT(
  chainId: fixture['chainId'] as int,
  hopDong: fixture['contract'] as String,
);
final voucher = PhieuVatPham.fromJson(
  Map<String, dynamic>.from(fixture['voucher'] as Map),
);
final recipient = fixture['recipient'] as String;
final tokenId = voucher.tokenId;

VatPhamNFT metadata({BigInt? id, CauHinhNFT? cauHinh}) => VatPhamNFT(
  tokenId: id ?? tokenId,
  name: 'Kiếm Vàng',
  description: 'Metadata hiển thị, không chứng minh sở hữu.',
  category: LoaiVatPhamNFT.vuKhi,
  chainId: (cauHinh ?? config).chainId,
  contractAddress: (cauHinh ?? config).hopDong,
);
PhieuVatPhamDaKy signed({PhieuVatPham? phieu, CauHinhNFT? cauHinh}) =>
    PhieuVatPhamDaKy(
      phieu: phieu ?? voucher,
      chuKy: fixture['signature'] as String,
      cauHinh: cauHinh ?? config,
    );
Matcher loi({LoaiLoiVi? loai, String? text}) {
  var m = isA<LoiVi>();
  if (loai != null) m = m.having((e) => e.loai, 'loai', loai);
  if (text != null) m = m.having((e) => e.thongBao, 'thongBao', contains(text));
  return throwsA(m);
}

class ViNFTGia extends ViGia {
  final events = StreamController<SuKienVi>.broadcast(sync: true);
  final overrides = <String, String>{};
  final balances = <String, BigInt>{};
  final readCalls = <String>[];
  final toAddresses = <String>[];
  bool hoTro = true;
  bool capNhatSauReceipt = true;
  bool used = false;
  bool registered = true;
  BigInt minted = BigInt.from(7);
  BigInt cap = BigInt.from(100);
  void Function(String)? sauKhiDoc;
  void Function()? truocGui;
  Completer<void>? receiptGate;
  String? _pending;

  ViNFTGia() : super(taiKhoan: [voucher.player]) {
    balances[voucher.player.toLowerCase()] = BigInt.from(5);
    balances[recipient.toLowerCase()] = BigInt.from(2);
  }
  @override
  bool get coSan => hoTro;
  @override
  Stream<SuKienVi> get suKien => events.stream;
  BigInt word(String data, int index) =>
      BigInt.parse(data.substring(10 + index * 64, 74 + index * 64), radix: 16);
  String addressWord(String data, int index) =>
      '0x${data.substring(34 + index * 64, 74 + index * 64)}'.toLowerCase();

  @override
  Future<String> goi({
    required String toi,
    required String duLieu,
    String? tu,
  }) async {
    toAddresses.add(toi);
    if (tu != null) return super.goi(toi: toi, duLieu: duLieu, tu: tu);
    readCalls.add(duLieu);
    final String answer;
    if (overrides.containsKey(duLieu)) {
      answer = overrides[duLieu]!;
    } else if (duLieu == calls['typehash'] ||
        duLieu == calls['domain'] ||
        duLieu == calls['supports']) {
      answer = results[calls.entries.firstWhere((e) => e.value == duLieu).key]!;
    } else if (duLieu.startsWith('0x00fdd58e')) {
      answer =
          '0x${abi.tu(word(duLieu, 1) == tokenId ? balances[addressWord(duLieu, 0)] ?? BigInt.zero : BigInt.zero)}';
    } else if (duLieu.startsWith('0x4e1273f4')) {
      final n = word(duLieu, 2).toInt();
      final offsetIds = word(duLieu, 1).toInt() ~/ 32;
      final b = List.generate(
        n,
        (i) => word(duLieu, offsetIds + 1 + i) == tokenId
            ? balances[addressWord(duLieu, 3 + i)] ?? BigInt.zero
            : BigInt.zero,
      );
      answer =
          '0x${abi.tu(BigInt.from(32))}${abi.tu(BigInt.from(n))}${b.map(abi.tu).join()}';
    } else if (duLieu.startsWith('0xe6cf1346')) {
      answer =
          '0x${abi.tu(registered && word(duLieu, 0) == tokenId ? BigInt.one : BigInt.zero)}';
    } else if (duLieu.startsWith('0x869f7594')) {
      answer =
          '0x${abi.tu(registered && word(duLieu, 0) == tokenId ? cap : BigInt.zero)}';
    } else if (duLieu.startsWith('0x9d7f4ebf')) {
      answer =
          '0x${abi.tu(registered && word(duLieu, 0) == tokenId ? minted : BigInt.zero)}';
    } else if (duLieu.startsWith('0x0e89341c')) {
      answer = results['uri']!;
    } else if (duLieu.startsWith('0xfeb61724')) {
      answer = '0x${abi.tu(used ? BigInt.one : BigInt.zero)}';
    } else {
      throw StateError('Mock không hỗ trợ RPC: $duLieu');
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
    truocGui?.call();
    final hash = await super.guiGiaoDich(
      tu: tu,
      toi: toi,
      duLieu: duLieu,
      gas: gas,
    );
    _pending = duLieu;
    return hash;
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    await receiptGate?.future;
    final bl = await super.bienLai(maGiaoDich);
    if (bl?.thanhCong == true && capNhatSauReceipt && _pending != null) {
      final data = _pending!;
      if (data.startsWith('0xbf60e081')) {
        final player = addressWord(data, 0);
        final amount = word(data, 2);
        balances[player] = (balances[player] ?? BigInt.zero) + amount;
        minted += amount;
        used = true;
      } else if (data.startsWith('0xf242432a')) {
        final from = addressWord(data, 0);
        final to = addressWord(data, 1);
        final amount = word(data, 3);
        balances[from] = (balances[from] ?? BigInt.zero) - amount;
        balances[to] = (balances[to] ?? BigInt.zero) + amount;
      }
      _pending = null;
    }
    return bl;
  }
}

({DichVuNFT service, PhienVi phien, ViNFTGia vi}) setup({
  ViNFTGia? wallet,
  String? player,
}) {
  final vi = wallet ?? ViNFTGia();
  final client = MockClient(
    (_) async => throw StateError(
      'NFT không được gọi endpoint vàng hoặc Backend giả định.',
    ),
  );
  final phien = PhienVi(
    vi: vi,
    mayChu: MayChuPhieu(mayChu: '', client: client),
  )..diaChi = player ?? voucher.player;
  final service = DichVuNFT(
    phienVi: phien,
    cauHinh: config,
    choToiDa: const Duration(seconds: 3),
    nhipKiemTra: const Duration(seconds: 1),
    ngu: (_) async {},
  );
  addTearDown(() async {
    service.dispose();
    phien.dispose();
    client.close();
    await vi.events.close();
  });
  return (service: service, phien: phien, vi: vi);
}

Future<void> pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Cấu hình, phiếu và ABI độc lập từ viem', () {
    test(
      'phiếu uint256 lớn giữ chính xác qua JSON, không có ký hoặc xin API',
      () {
        expect(
          PhieuVatPham.fromJson(
            jsonDecode(jsonEncode(voucher.toJson())) as Map<String, dynamic>,
          ).toJson(),
          fixture['voucher'],
        );
        expect(voucher.tokenId.bitLength, greaterThan(100));
        for (final field in ['tokenId', 'amount', 'deadline']) {
          for (final value in [
            -1,
            1.5,
            9007199254740992,
            (BigInt.one << 256).toString(),
          ]) {
            expect(
              () => PhieuVatPham.fromJson({...voucher.toJson(), field: value}),
              throwsA(anything),
            );
          }
        }
      },
    );
    test('từ chối chain, địa chỉ, nonce, chữ ký và số lượng sai', () {
      expect(
        () => CauHinhNFT(chainId: 0, hopDong: config.hopDong),
        throwsArgumentError,
      );
      expect(
        () => CauHinhNFT(chainId: 9007199254740992, hopDong: config.hopDong),
        throwsArgumentError,
      );
      for (final address in ['', '0x123', '0x${'0' * 40}']) {
        expect(
          () => CauHinhNFT(chainId: 31337, hopDong: address),
          throwsFormatException,
        );
      }
      for (final invalid in ['0x1234', '0x${'z' * 130}']) {
        expect(
          () =>
              PhieuVatPhamDaKy(phieu: voucher, chuKy: invalid, cauHinh: config),
          throwsFormatException,
        );
      }
      for (final entry in <Map<String, dynamic>>[
        {'nonce': '0x123'},
        {'nonce': 'd' * 64},
        {'amount': '0'},
        {'tokenId': '0'},
      ]) {
        expect(
          () => PhieuVatPham.fromJson({...voucher.toJson(), ...entry}),
          throwsA(anything),
        );
      }
    });
    test('claimItem calldata chính xác từng byte với viem', () async {
      final f = setup();
      await f.service.nhanVatPham(metadata(), phieu: signed());
      expect(f.vi.daGui.single, calls['claim']);
      expect(f.vi.toAddresses.every((x) => x == config.hopDong), isTrue);
    });
    test('safeTransferFrom calldata chính xác từng byte với viem', () async {
      final f = setup();
      await f.service.chuyenVatPham(
        tokenId: tokenId,
        nguoiNhan: recipient,
        amount: voucher.amount,
        metadata: metadata(),
      );
      expect(f.vi.daGui.single, calls['transfer']);
    });
  });

  group('Đọc quyền sở hữu và metadata', () {
    test('đọc số dư, URI và cap từ chuỗi, bỏ cache cũ', () async {
      final f = setup();
      final model = await f.service.taiVatPham(
        metadata().copyWith(
          balance: BigInt.from(999),
          metadataUri: 'ipfs://fake',
          maxSupply: BigInt.from(999),
        ),
      );
      expect(model.verifiedBalance, BigInt.from(5));
      expect(model.owned, isTrue);
      expect(model.metadataUri, 'ipfs://goldrush/kiem-vang.json');
      expect(model.maxSupply, BigInt.from(100));
      expect(model.walletAddress, voucher.player);
      expect(model.name, metadata().name);
      final info = await f.service.docThongTinVatPham(tokenId);
      expect(info.totalMinted, BigInt.from(7));
      expect(info.registered, isTrue);
    });
    test('số dư 0 thực sự vẫn được đánh dấu đã đọc', () async {
      final f = setup();
      f.vi.balances[voucher.player] = BigInt.zero;
      final model = await f.service.taiVatPham(metadata());
      expect(model.verifiedBalance, BigInt.zero);
      expect(model.balanceStatus, TrangThaiSoDuNFT.daKiemTra);
      expect(model.owned, isFalse);
    });
    test('model chưa đọc không được xác nhận sở hữu', () {
      expect(metadata().balance, isNull);
      expect(metadata().verifiedBalance, isNull);
      expect(metadata().owned, isFalse);
    });
    test('balanceOfBatch mã hóa viem, giữ thứ tự và số dư 0', () async {
      final f = setup();
      expect(await f.service.docSoDuBatch([tokenId, BigInt.two]), [
        BigInt.from(5),
        BigInt.zero,
      ]);
      expect(f.vi.readCalls, contains(calls['batch']));
      expect(await f.service.docSoDuBatch([]), isEmpty);
    });
    test(
      'loại chưa đăng ký không gọi uri, không giữ metadata on-chain giả',
      () async {
        final f = setup();
        final v = await f.service.taiVatPham(
          metadata(id: BigInt.two)
              .copyWith(maxSupply: BigInt.one, metadataUri: 'ipfs://cached'),
        );
        expect(v.verifiedBalance, BigInt.zero);
        expect(v.maxSupply, isNull);
        expect(v.metadataUri, isNull);
        expect(
          f.vi.readCalls.where((x) => x.startsWith('0x0e89341c')),
          isEmpty,
        );
      },
    );
    test('uint256 tối đa không chuyển sang int', () async {
      final f = setup();
      final max = (BigInt.one << 256) - BigInt.one;
      f.vi.balances[voucher.player] = max;
      f.vi.cap = max;
      f.vi.minted = max;
      expect(await f.service.docSoDu(tokenId), max);
      expect((await f.service.taiVatPham(metadata())).verifiedBalance, max);
    });
    test('RPC rỗng/sai độ dài không được biến thành số dư 0', () async {
      final f = setup();
      for (final invalid in ['0x', '0x12', '0x${'0' * 128}', '0x${'z' * 64}']) {
        f.vi.overrides[calls['balance']!] = invalid;
        await expectLater(
          f.service.taiVatPham(metadata()),
          throwsA(
            isA<LoiNFT>().having(
              (e) => e.nguyenNhan,
              'nguyenNhan',
              NguyenNhanLoiNFT.duLieu,
            ),
          ),
        );
      }
    });
    test('từ chối bool/offset/mảng/nguồn cung sai dạng', () async {
      final f = setup();
      f.vi.overrides[calls['registered']!] = '0x${abi.tu(BigInt.two)}';
      await expectLater(f.service.taiVatPham(metadata()), loi(text: 'bool'));
      f.vi.overrides.clear();
      f.vi.overrides[calls['batch']!] =
          '0x${abi.tu(BigInt.from(32))}${abi.tu(BigInt.from(999))}';
      await expectLater(
        f.service.docSoDuBatch([tokenId, BigInt.two]),
        loi(text: 'balanceOfBatch'),
      );
      f.vi.overrides.clear();
      f.vi.minted = f.vi.cap + BigInt.one;
      await expectLater(
        f.service.taiVatPham(metadata()),
        loi(text: 'Nguồn cung'),
      );
      f.vi.minted = BigInt.zero;
      f.vi.overrides[calls['uri']!] =
          '0x${abi.tu((BigInt.one << 256) - BigInt.one)}';
      await expectLater(f.service.taiVatPham(metadata()), loi(text: 'Offset'));
    });
    test(
      'không kết nối hoặc nền tảng không hỗ trợ không giả lập số dư',
      () async {
        final f = setup();
        f.phien.diaChi = null;
        await expectLater(
          f.service.docSoDu(tokenId),
          loi(text: 'Chưa kết nối'),
        );
        f.phien.diaChi = voucher.player;
        f.vi.hoTro = false;
        await expectLater(f.service.docSoDu(tokenId), loi(text: 'chưa hỗ trợ'));
        final phien = PhienVi(vi: khong_ho_tro.taoVi(), mayChu: f.phien.mayChu);
        final service = DichVuNFT(phienVi: phien, cauHinh: config);
        await expectLater(service.docSoDu(tokenId), loi(text: 'chưa hỗ trợ'));
        service.dispose();
        phien.dispose();
      },
    );
    test('sai mạng khi đọc không mở yêu cầu chuyển mạng', () async {
      final f = setup();
      f.vi.mang = 1;
      await expectLater(
        f.service.taiVatPham(metadata()),
        loi(text: 'sai mạng'),
      );
      expect(f.vi.soLanChuyenMang, 0);
    });
    test('sai hợp đồng, typehash, domain hoặc model bị chặn', () async {
      final f = setup();
      f.vi.maByte = '0x';
      await expectLater(
        f.service.docSoDu(tokenId),
        loi(text: 'Không thấy hợp đồng'),
      );
      f.vi.maByte = '0x1234';
      f.vi.overrides[calls['typehash']!] = '0x${'0' * 64}';
      await expectLater(
        f.service.docSoDu(tokenId),
        loi(text: 'VatPhamGoldRush'),
      );
      f.vi.overrides.clear();
      final old = results['domain']!;
      f.vi.overrides[calls['domain']!] = old.replaceFirst(
        abi.tu(BigInt.from(31337)),
        abi.tu(BigInt.one),
      );
      await expectLater(f.service.docSoDu(tokenId), loi(text: 'domain'));
      f.vi.overrides.clear();
      await expectLater(
        f.service.taiVatPham(
          metadata(cauHinh: CauHinhNFT(chainId: 1, hopDong: config.hopDong)),
        ),
        loi(text: 'mạng/hợp đồng khác'),
      );
    });
  });

  group('Phiên ví và vô hiệu hóa dữ liệu', () {
    test('lamMoi của UI không bị lượt tự tải ghi đè sau sự kiện ví', () async {
      final f = setup();
      await f.service.taiDanhSach([metadata()]);
      f.vi.events.add(const DoiMang(31337));
      final list = await f.service.lamMoi();
      expect(list.single.verifiedBalance, BigInt.from(5));
      await pump();
      expect(f.service.danhSach.single.owned, isTrue);
      expect(f.service.loiTai, isNull);
    });

    test(
      'phát hiện sai chain khi provider không phát sự kiện cũng xóa xác minh',
      () async {
        final f = setup();
        await f.service.taiDanhSach([metadata()]);
        f.vi.mang = 1;
        await expectLater(f.service.docSoDu(tokenId), loi(text: 'sai mạng'));
        expect(f.service.danhSach.single.owned, isFalse);
        expect(f.service.danhSach.single.verifiedBalance, isNull);
      },
    );
    test('đổi ví vô hiệu hóa ngay rồi tự đọc lại đúng ví', () async {
      final f = setup();
      await f.service.taiDanhSach([metadata()]);
      expect(f.service.danhSach.single.owned, isTrue);
      f.vi.danhSachTaiKhoan = [recipient];
      f.phien.diaChi = recipient;
      f.phien.veLai();
      expect(f.service.danhSach.single.verifiedBalance, isNull);
      await pump();
      expect(f.service.danhSach.single.walletAddress, recipient);
      expect(f.service.danhSach.single.verifiedBalance, BigInt.two);
    });
    test('đổi chain xóa xác minh, về đúng chain tự tải lại', () async {
      final f = setup();
      await f.service.taiDanhSach([metadata()]);
      f.vi.mang = 1;
      f.vi.events.add(const DoiMang(1));
      expect(f.service.danhSach.single.verifiedBalance, isNull);
      await pump();
      expect(f.service.loiTai, isNotNull);
      expect(f.service.danhSach.single.owned, isFalse);
      f.vi.mang = 31337;
      f.vi.events.add(const DoiMang(31337));
      await pump();
      expect(f.service.loiTai, isNull);
      expect(f.service.danhSach.single.owned, isTrue);
    });
    test('đổi tài khoản trong lúc đọc không trả model đã xác minh', () async {
      final f = setup();
      f.vi.sauKhiDoc = (data) {
        if (data == calls['balance']) f.vi.danhSachTaiKhoan = [recipient];
      };
      await expectLater(
        f.service.taiVatPham(metadata()),
        loi(loai: LoaiLoiVi.doiTaiKhoan),
      );
    });
    test('đổi chain đi rồi về trong một lần đọc vẫn hủy kết quả cũ', () async {
      final f = setup();
      f.vi.sauKhiDoc = (data) {
        if (data == calls['balance']) {
          f.vi.events.add(const DoiMang(1));
          f.vi.events.add(const DoiMang(31337));
        }
      };
      await expectLater(
        f.service.taiVatPham(metadata()),
        loi(loai: LoaiLoiVi.doiTaiKhoan),
      );
    });
    test('ngắt kết nối bỏ xác minh và không gọi API giả', () async {
      final f = setup();
      await f.service.taiDanhSach([metadata()]);
      f.phien.diaChi = null;
      f.phien.veLai();
      await pump();
      expect(f.service.danhSach.single.owned, isFalse);
      expect(f.service.danhSach.single.walletAddress, isNull);
      expect(f.service.loiTai?.thongBao, contains('Chưa kết nối'));
    });
  });

  group('Nhận NFT và receipt', () {
    test(
      'phiếu thiếu hoặc sai domain không mở hộp thoại chuyển mạng',
      () async {
        final f = setup();
        f.vi.mang = 1;
        await expectLater(
          f.service.nhanVatPham(metadata()),
          loi(text: 'Chưa có phiếu'),
        );
        await expectLater(
          f.service.nhanVatPham(
            metadata(),
            phieu: signed(
              cauHinh: CauHinhNFT(chainId: 1, hopDong: config.hopDong),
            ),
          ),
          loi(text: 'mạng/hợp đồng khác'),
        );
        expect(f.vi.soLanChuyenMang, 0);
        expect(f.vi.daGui, isEmpty);
        expect(f.vi.readCalls, isEmpty);
      },
    );
    test('phiếu hợp lệ, hash, receipt và đọc lại số dư', () async {
      final f = setup();
      final hashes = <String>[];
      final statuses = <TrangThaiGiaoDichNFT>[];
      final result = await f.service.nhanVatPham(
        metadata(),
        phieu: signed(),
        khiDaGui: hashes.add,
        khiCapNhat: statuses.add,
      );
      expect(result.transactionHash, hashes.single);
      expect(result.receipt.thanhCong, isTrue);
      expect(result.vatPham.verifiedBalance, BigInt.from(8));
      expect(
        statuses,
        containsAllInOrder([
          TrangThaiGiaoDichNFT.choXacNhanVi,
          TrangThaiGiaoDichNFT.choXacNhanChuoi,
          TrangThaiGiaoDichNFT.daXacNhan,
          TrangThaiGiaoDichNFT.thanhCong,
        ]),
      );
      expect(f.phien.dangXuLy, isFalse);
    });
    test('không có phiếu thì không gửi', () async {
      final f = setup();
      await expectLater(
        f.service.nhanVatPham(metadata()),
        loi(text: 'Chưa có phiếu'),
      );
      expect(f.vi.daGui, isEmpty);
    });
    test('phiếu sai người/ID/mạng/hợp đồng không gửi', () async {
      final f = setup();
      for (final entry in <Map<String, dynamic>>[
        {'player': recipient},
        {'tokenId': '2'},
      ]) {
        await expectLater(
          f.service.nhanVatPham(
            metadata(),
            phieu: signed(
              phieu: PhieuVatPham.fromJson({...voucher.toJson(), ...entry}),
            ),
          ),
          loi(text: 'không dành'),
        );
      }
      for (final c in [
        CauHinhNFT(chainId: 1, hopDong: config.hopDong),
        CauHinhNFT(chainId: 31337, hopDong: recipient),
      ]) {
        await expectLater(
          f.service.nhanVatPham(metadata(), phieu: signed(cauHinh: c)),
          loi(text: 'mạng/hợp đồng khác'),
        );
      }
      expect(f.vi.daGui, isEmpty);
    });
    test('người dùng từ chối MetaMask có trạng thái daHuy', () async {
      final f = setup();
      f.vi.loiKhiGui = const LoiVi(
        'Đã từ chối',
        ma: 4001,
        loai: LoaiLoiVi.tuChoi,
      );
      await expectLater(
        f.service.nhanVatPham(metadata(), phieu: signed()),
        loi(loai: LoaiLoiVi.tuChoi),
      );
      expect(f.service.trangThai, TrangThaiGiaoDichNFT.daHuy);
      expect(f.vi.daGui, isEmpty);
      expect(f.phien.dangXuLy, isFalse);
    });
    for (final name in [
      'InvalidSignature',
      'VoucherExpired',
      'NonceAlreadyUsed',
      'WrongPlayer',
      'ItemNotRegistered',
      'MaxSupplyExceeded',
      'ERC1155InvalidReceiver',
      'ERC1155InsufficientBalance',
    ]) {
      test('dịch đúng custom error $name, không mở gửi giao dịch', () async {
        final f = setup();
        f.vi.loiMoPhong = LoiVi(
          'RPC revert',
          duLieu: {
            'originalError': {'data': errors[name]},
          },
          loai: LoaiLoiVi.hopDongTuChoi,
        );
        await expectLater(
          f.service.nhanVatPham(metadata(), phieu: signed()),
          loi(loai: LoaiLoiVi.hopDongTuChoi, text: name),
        );
        expect(f.vi.daGui, isEmpty);
        expect(f.service.trangThai, TrangThaiGiaoDichNFT.thatBai);
      });
    }
    test('receipt revert không được báo thành công', () async {
      final f = setup();
      f.vi.bienLaiLanLuot = [const BienLai(thanhCong: false, soKhoi: 9)];
      await expectLater(
        f.service.nhanVatPham(metadata(), phieu: signed()),
        loi(loai: LoaiLoiVi.hopDongTuChoi),
      );
      expect(f.service.trangThai, TrangThaiGiaoDichNFT.thatBai);
    });
    test('mới có hash chưa có receipt vẫn đang chờ', () async {
      final f = setup();
      final gate = Completer<void>();
      f.vi.receiptGate = gate;
      final future = f.service.nhanVatPham(metadata(), phieu: signed());
      await pump();
      expect(f.vi.daGui, hasLength(1));
      expect(f.service.trangThai, TrangThaiGiaoDichNFT.choXacNhanChuoi);
      expect(f.phien.dangXuLy, isTrue);
      gate.complete();
      expect((await future).receipt.thanhCong, isTrue);
    });
    test(
      'timeout giữ hash và không tự gửi lại; theo dõi receipt riêng',
      () async {
        final f = setup();
        f.vi.bienLaiLanLuot = [null];
        try {
          await f.service.nhanVatPham(metadata(), phieu: signed());
          fail('Phải timeout');
        } on LoiGiaoDichNFT catch (e) {
          expect(e.transactionHash, isNotNull);
          expect(e.receipt, isNull);
          expect(e.loai, LoaiLoiVi.chuaXacNhan);
        }
        expect(f.service.trangThai, TrangThaiGiaoDichNFT.hetThoiGianCho);
        await expectLater(
          f.service.nhanVatPham(metadata(), phieu: signed()),
          loi(loai: LoaiLoiVi.chuaXacNhan),
        );
        expect(f.vi.daGui, hasLength(1));
        f.vi.bienLaiLanLuot = [const BienLai(thanhCong: true, soKhoi: 10)];
        expect(
          (await f.service.docBienLai(f.service.transactionHash!))?.thanhCong,
          isTrue,
        );
        expect(f.service.trangThai, TrangThaiGiaoDichNFT.daXacNhan);
      },
    );
    test(
      'receipt thành công nhưng dữ liệu cũ phải phân biệt với revert',
      () async {
        final f = setup();
        f.vi.capNhatSauReceipt = false;
        try {
          await f.service.nhanVatPham(metadata(), phieu: signed());
          fail('Phải báo dữ liệu chưa cập nhật');
        } on LoiGiaoDichNFT catch (e) {
          expect(e.receipt?.thanhCong, isTrue);
          expect(e.transactionHash, isNotNull);
          expect(e.loai, LoaiLoiVi.chuaXacNhan);
        }
        expect(f.service.trangThai, TrangThaiGiaoDichNFT.duLieuChuaCapNhat);
      },
    );
    test(
      'đổi tài khoản sau khi gửi giữ hash và không xác minh sở hữu cho ví mới',
      () async {
        final f = setup();
        f.vi.truocGui = () {
          f.vi.danhSachTaiKhoan = [recipient];
        };
        await expectLater(
          f.service.nhanVatPham(metadata(), phieu: signed()),
          loi(loai: LoaiLoiVi.doiTaiKhoan),
        );
        expect(f.service.transactionHash, isNotNull);
        expect(f.service.trangThai, TrangThaiGiaoDichNFT.choXacNhanChuoi);
      },
    );
    test(
      'khóa giao dịch dùng chung PhienVi, không mở hai yêu cầu ví',
      () async {
        final f = setup();
        f.phien.dangXuLy = true;
        await expectLater(
          f.service.nhanVatPham(metadata(), phieu: signed()),
          loi(loai: LoaiLoiVi.dangCho),
        );
        expect(f.vi.daGui, isEmpty);
        f.phien.dangXuLy = false;
      },
    );
  });

  group('Chuyển ERC-1155', () {
    test(
      'chuyển thành công bằng ví hiện tại và đọc lại cả hai số dư',
      () async {
        final f = setup();
        await f.service.taiDanhSach([metadata()]);
        final r = await f.service.chuyenVatPham(
          tokenId: tokenId,
          nguoiNhan: recipient,
          amount: BigInt.from(3),
        );
        expect(r.receipt.thanhCong, isTrue);
        expect(r.vatPham.verifiedBalance, BigInt.two);
        expect(r.soDuNguoiNhan, BigInt.from(5));
        expect(f.service.danhSach.single.verifiedBalance, BigInt.two);
        expect(f.vi.minted, BigInt.from(7));
      },
    );
    test('ví chưa có NFT và chuyển quá số dư có lỗi riêng', () async {
      final f = setup();
      await expectLater(
        f.service.chuyenVatPham(
          tokenId: tokenId,
          nguoiNhan: recipient,
          amount: BigInt.from(6),
          metadata: metadata(),
        ),
        loi(text: 'Không đủ'),
      );
      f.vi.balances[voucher.player] = BigInt.zero;
      await expectLater(
        f.service.chuyenVatPham(
          tokenId: tokenId,
          nguoiNhan: recipient,
          amount: BigInt.one,
          metadata: metadata(),
        ),
        loi(text: 'chưa sở hữu'),
      );
      expect(f.vi.daGui, isEmpty);
    });
    test('amount/ID zero, âm hoặc tràn bị chặn', () async {
      final f = setup();
      for (final n in [BigInt.zero, -BigInt.one, BigInt.one << 256]) {
        await expectLater(
          f.service.chuyenVatPham(
            tokenId: tokenId,
            nguoiNhan: recipient,
            amount: n,
            metadata: metadata(),
          ),
          throwsArgumentError,
        );
        await expectLater(
          f.service.chuyenVatPham(
            tokenId: n,
            nguoiNhan: recipient,
            amount: BigInt.one,
            metadata: metadata(),
          ),
          throwsArgumentError,
        );
      }
      expect(f.vi.daGui, isEmpty);
    });
    test('người nhận zero, sai địa chỉ hoặc chính ví gửi bị chặn', () async {
      final f = setup();
      for (final address in ['0x123', '0x${'0' * 40}']) {
        await expectLater(
          f.service.chuyenVatPham(
            tokenId: tokenId,
            nguoiNhan: address,
            amount: BigInt.one,
            metadata: metadata(),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        f.service.chuyenVatPham(
          tokenId: tokenId,
          nguoiNhan: voucher.player,
          amount: BigInt.one,
          metadata: metadata(),
        ),
        loi(text: 'khác ví gửi'),
      );
      expect(f.vi.daGui, isEmpty);
    });
    test('chuyển uint256 lớn không làm tròn', () async {
      final f = setup();
      final n = BigInt.one << 200;
      f.vi.balances[voucher.player] = n + BigInt.one;
      f.vi.minted = n + BigInt.from(3);
      f.vi.cap = (BigInt.one << 256) - BigInt.one;
      final r = await f.service.chuyenVatPham(
        tokenId: tokenId,
        nguoiNhan: recipient,
        amount: n,
        metadata: metadata(),
      );
      expect(r.vatPham.verifiedBalance, BigInt.one);
      expect(r.soDuNguoiNhan, n + BigInt.two);
    });
    test(
      'xin chuyển mạng khi ghi, hủy chuyển mạng không gửi giao dịch',
      () async {
        final f = setup();
        f.vi.mang = 1;
        await f.service.chuyenVatPham(
          tokenId: tokenId,
          nguoiNhan: recipient,
          amount: BigInt.one,
          metadata: metadata(),
        );
        expect(f.vi.soLanChuyenMang, 1);
        f.vi.mang = 1;
        f.vi.mangSauKhiChuyen = 1;
        await expectLater(
          f.service.chuyenVatPham(
            tokenId: tokenId,
            nguoiNhan: recipient,
            amount: BigInt.one,
            metadata: metadata(),
          ),
          loi(text: 'mạng'),
        );
        expect(f.vi.daGui, hasLength(1));
      },
    );
  });
}
