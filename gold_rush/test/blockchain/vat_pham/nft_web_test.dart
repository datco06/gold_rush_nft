@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/blockchain/vat_pham/nft_model.dart';
import 'package:gold_rush/blockchain/vat_pham/nft_service.dart';
import 'package:gold_rush/blockchain/vi.dart';

// Dùng lại provider EIP-1193 thử nghiệm, không sửa adapter MetaMask hiện có.
import '../sbt/sbt_web_test.dart' show ProviderThu;

const _fixtureJson = String.fromEnvironment('NFT_WEB_FIXTURE');

void main() {
  tearDown(() => globalContext.delete('ethereum'.toJS));

  test(
    'Chrome: JSON uint256 tối đa chính xác, cache không chứng minh sở hữu',
    () {
      final max = (BigInt.one << 256) - BigInt.one;
      final v = VatPhamNFT(
        tokenId: max,
        name: 'Kiếm Vàng',
        description: '',
        category: LoaiVatPhamNFT.vuKhi,
        contractAddress: '0x${'a' * 40}',
        chainId: 31337,
        walletAddress: '0x${'b' * 40}',
        balance: max,
        maxSupply: max,
        balanceStatus: TrangThaiSoDuNFT.daKiemTra,
      );
      final cached = VatPhamNFT.fromJson(
        jsonDecode(jsonEncode(v.toJson())) as Map<String, dynamic>,
      );
      expect(cached.tokenId, max);
      expect(cached.balance, max);
      expect(cached.maxSupply, max);
      expect(cached.owned, isFalse);
    },
  );

  test(
    'Chrome + vi_web + Hardhat: đọc, nhận, chuyển, lỗi phiếu và đổi ví',
    () async {
      final f = jsonDecode(_fixtureJson) as Map<String, dynamic>;
      final config = CauHinhNFT(
        chainId: f['chainId'] as int,
        hopDong: f['address'] as String,
      );
      final id = BigInt.parse(f['tokenId'] as String);
      var selected = f['player'] as String;
      var reject = false;
      final rpc = http.Client();
      final api = MockClient(
        (_) async => throw StateError('Không được gọi API giả định.'),
      );
      addTearDown(rpc.close);
      addTearDown(api.close);
      var rpcId = 0;
      final provider = ProviderThu((method, params) async {
        if (method == 'eth_requestAccounts' || method == 'eth_accounts') {
          return [selected];
        }
        if (method == 'eth_sendTransaction' && reject) {
          throw {'code': 4001, 'message': 'User rejected the request'};
        }
        final response = await rpc.post(
          Uri.parse(f['rpcUrl'] as String),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': ++rpcId,
            'method': method,
            'params': params,
          }),
        );
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['error'] != null) throw json['error']!;
        return json['result'];
      });
      final vi = taoViMacDinh();
      final phien = PhienVi(
        vi: vi,
        mayChu: MayChuPhieu(mayChu: '', client: api),
      )..diaChi = selected;
      final service = DichVuNFT(
        phienVi: phien,
        cauHinh: config,
        nhipKiemTra: const Duration(milliseconds: 30),
      );
      addTearDown(() {
        service.dispose();
        phien.dispose();
      });
      final metadata = VatPhamNFT(
        tokenId: id,
        name: 'Kiếm Vàng',
        description: '',
        category: LoaiVatPhamNFT.vuKhi,
        contractAddress: config.hopDong,
        chainId: config.chainId,
      );
      PhieuVatPhamDaKy signed(String key) {
        final data = f[key] as Map<String, dynamic>;
        return PhieuVatPhamDaKy(
          phieu: PhieuVatPham.fromJson(
            Map<String, dynamic>.from(data['phieu'] as Map),
          ),
          chuKy: data['chuKy'] as String,
          cauHinh: config,
        );
      }

      final initial = await service.taiDanhSach([metadata]);
      expect(initial.single.verifiedBalance, BigInt.zero);
      expect(initial.single.maxSupply, (BigInt.one << 256) - BigInt.one);
      expect(initial.single.metadataUri, 'ipfs://goldrush/kiem-vang.json');
      reject = true;
      await expectLater(
        service.nhanVatPham(metadata, phieu: signed('rejected')),
        throwsA(
          isA<LoiVi>().having((e) => e.nguoiDungTuChoi, 'tuChoi', isTrue),
        ),
      );
      expect(service.trangThai, TrangThaiGiaoDichNFT.daHuy);
      reject = false;
      for (final entry in {
        'invalid': 'InvalidSignature',
        'expired': 'VoucherExpired',
      }.entries) {
        await expectLater(
          service.nhanVatPham(metadata, phieu: signed(entry.key)),
          throwsA(
            isA<LoiVi>().having(
              (e) => e.thongBao,
              'custom error',
              contains(entry.value),
            ),
          ),
        );
      }
      final minted = await service.nhanVatPham(
        metadata,
        phieu: signed('valid'),
      );
      expect(minted.receipt.thanhCong, isTrue);
      expect(minted.receipt.soKhoi, isNotNull);
      expect(minted.vatPham.verifiedBalance, BigInt.from(3));
      await expectLater(
        service.nhanVatPham(metadata, phieu: signed('valid')),
        throwsA(
          isA<LoiVi>().having(
            (e) => e.thongBao,
            'replay',
            contains('NonceAlreadyUsed'),
          ),
        ),
      );
      final moved = await service.chuyenVatPham(
        tokenId: id,
        nguoiNhan: f['recipient'] as String,
        amount: BigInt.one,
        metadata: metadata,
      );
      expect(moved.receipt.thanhCong, isTrue);
      expect(moved.vatPham.verifiedBalance, BigInt.two);
      expect(moved.soDuNguoiNhan, BigInt.one);
      await expectLater(
        service.chuyenVatPham(
          tokenId: id,
          nguoiNhan: config.hopDong,
          amount: BigInt.one,
          metadata: metadata,
        ),
        throwsA(
          isA<LoiVi>().having(
            (e) => e.thongBao,
            'receiver',
            contains('ERC1155InvalidReceiver'),
          ),
        ),
      );
      final reloaded = Completer<void>();
      service.addListener(() {
        final models = service.danhSach;
        if (!service.dangTai &&
            models.isNotEmpty &&
            models.single.walletAddress?.toLowerCase() ==
                (f['recipient'] as String).toLowerCase() &&
            models.single.verifiedBalance == BigInt.one &&
            !reloaded.isCompleted) {
          reloaded.complete();
        }
      });
      selected = f['recipient'] as String;
      phien.diaChi = selected;
      phien.veLai();
      provider.emit('accountsChanged', [selected]);
      expect(service.danhSach.single.owned, isFalse);
      await reloaded.future.timeout(const Duration(seconds: 15));
      expect(service.danhSach.single.walletAddress, selected);
      expect(service.danhSach.single.verifiedBalance, BigInt.one);
      expect(provider.methods, isNot(contains('eth_signTypedData_v4')));
      expect(provider.methods, isNot(contains('eth_sign')));
    },
    skip: _fixtureJson.isEmpty
        ? 'Cần fixture từ chuan_bi_web.mjs và node Hardhat riêng.'
        : false,
  );
}
