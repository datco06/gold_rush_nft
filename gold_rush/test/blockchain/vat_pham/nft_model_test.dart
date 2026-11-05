import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/vat_pham/nft_model.dart';

void main() {
  // Địa chỉ giả chỉ dùng kiểm tra model; không trỏ tới hợp đồng/ví triển khai.
  final contract = '0x${'a' * 40}';
  final walletA = '0x${'b' * 40}';
  final walletB = '0x${'c' * 40}';
  final maxUint256 = (BigInt.one << 256) - BigInt.one;

  Map<String, dynamic> metadata() => {
    'tokenId': '1',
    'name': 'Kiếm Vàng',
    'description': 'Vật phẩm ERC-1155 có thể chuyển nhượng.',
    'category': 'vuKhi',
    'contractAddress': contract,
    'chainId': 31337,
  };

  VatPhamNFT item() => VatPhamNFT.fromJson(metadata());

  VatPhamNFT verified({BigInt? balance}) => item().copyWith(
    walletAddress: walletA,
    balance: balance ?? BigInt.one,
    balanceStatus: TrangThaiSoDuNFT.daKiemTra,
  );

  group('Metadata và số dư NFT độc lập', () {
    test('danh mục không tự có số dư, ảnh, cap hoặc quyền sở hữu', () {
      final nft = item();
      expect(nft.tokenId, BigInt.one);
      expect(nft.name, 'Kiếm Vàng');
      expect(nft.category, LoaiVatPhamNFT.vuKhi);
      expect(nft.imageUrl, isNull);
      expect(nft.metadataUri, isNull);
      expect(nft.maxSupply, isNull);
      expect(nft.walletAddress, isNull);
      expect(nft.balance, isNull);
      expect(nft.verifiedBalance, isNull);
      expect(nft.balanceStatus, TrangThaiSoDuNFT.chuaKiemTra);
      expect(nft.owned, isFalse);
    });

    test('có số dư cache và cap không tự xác nhận sở hữu', () {
      final nft = item().copyWith(balance: BigInt.one, maxSupply: BigInt.one);
      expect(nft.balance, BigInt.one);
      expect(nft.maxSupply, BigInt.one);
      expect(nft.verifiedBalance, isNull);
      expect(nft.owned, isFalse);
    });

    test('số dư dương đã xác minh mới xác nhận sở hữu cho đúng ví', () {
      final nft = verified(balance: BigInt.from(3));
      expect(nft.walletAddress, walletA);
      expect(nft.verifiedBalance, BigInt.from(3));
      expect(nft.owned, isTrue);
    });

    test('số dư bằng 0 đã xác minh khác chưa đọc Blockchain', () {
      final nft = verified(balance: BigInt.zero);
      expect(nft.balance, BigInt.zero);
      expect(nft.verifiedBalance, BigInt.zero);
      expect(nft.balanceStatus, TrangThaiSoDuNFT.daKiemTra);
      expect(nft.owned, isFalse);
      expect(item().verifiedBalance, isNull);
    });

    test('hỗ trợ cả ba category và ID ngoài bốn hằng số danh mục', () {
      for (final category in LoaiVatPhamNFT.values) {
        final nft = VatPhamNFT.fromJson({
          ...metadata(),
          'category': category.name,
          'tokenId': '999',
        });
        expect(nft.category, category);
        expect(nft.tokenId, BigInt.from(999));
        expect(nft.owned, isFalse);
      }
    });

    test('trạng thái xác minh đòi hỏi ví và số dư', () {
      expect(
        () => item().copyWith(balanceStatus: TrangThaiSoDuNFT.daKiemTra),
        throwsArgumentError,
      );
      expect(
        () => item().copyWith(
          walletAddress: walletA,
          balanceStatus: TrangThaiSoDuNFT.daKiemTra,
        ),
        throwsArgumentError,
      );
      expect(
        () => item().copyWith(
          balance: BigInt.one,
          balanceStatus: TrangThaiSoDuNFT.daKiemTra,
        ),
        throwsArgumentError,
      );
    });
  });

  group('JSON và độ chính xác uint256', () {
    test(
      'round-trip qua jsonEncode/jsonDecode giữ metadata và các trường null',
      () {
        final original = item();
        final restored = VatPhamNFT.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );
        expect(restored.toJson(), original.toJson());
      },
    );

    test('uint256 tối đa không mất chính xác; nạp cache phải xác minh lại', () {
      final original = VatPhamNFT(
        tokenId: maxUint256,
        name: 'Vật phẩm thử',
        description: 'Kiểm tra uint256.',
        category: LoaiVatPhamNFT.giap,
        contractAddress: contract,
        chainId: 11155111,
        walletAddress: walletA,
        balance: maxUint256,
        maxSupply: maxUint256,
        imageUrl: 'ipfs://example/image.png',
        metadataUri: 'ipfs://example/metadata.json',
        balanceStatus: TrangThaiSoDuNFT.daKiemTra,
      );
      final json = original.toJson();
      for (final field in ['tokenId', 'balance', 'maxSupply']) {
        expect(json[field], maxUint256.toString());
        expect(json[field], isA<String>());
      }
      final restored = VatPhamNFT.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(restored.tokenId, maxUint256);
      expect(restored.balance, maxUint256);
      expect(restored.maxSupply, maxUint256);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.category, original.category);
      expect(restored.imageUrl, original.imageUrl);
      expect(restored.metadataUri, original.metadataUri);
      expect(restored.contractAddress, contract);
      expect(restored.chainId, 11155111);
      expect(restored.walletAddress, walletA);
      expect(original.owned, isTrue);
      expect(restored.balanceStatus, TrangThaiSoDuNFT.chuaKiemTra);
      expect(restored.verifiedBalance, isNull);
      expect(restored.owned, isFalse);
    });

    test('không tin trạng thái sở hữu hoặc trang bị được JSON khai báo', () {
      final nft = VatPhamNFT.fromJson({
        ...metadata(),
        'walletAddress': walletA,
        'balance': '12',
        'balanceStatus': 'daKiemTra',
        'owned': true,
        'equipped': true,
      });
      expect(nft.balance, BigInt.from(12));
      expect(nft.balanceStatus, TrangThaiSoDuNFT.chuaKiemTra);
      expect(nft.owned, isFalse);
      expect(nft.toJson().containsKey('equipped'), isFalse);
    });

    test('số dư 0 qua JSON giữ giá trị nhưng bỏ xác minh', () {
      final restored = VatPhamNFT.fromJson(
        jsonDecode(jsonEncode(verified(balance: BigInt.zero).toJson()))
            as Map<String, dynamic>,
      );
      expect(restored.balance, BigInt.zero);
      expect(restored.verifiedBalance, isNull);
      expect(restored.owned, isFalse);
    });

    test('nhận số JSON an toàn hoặc chuỗi, xuất uint256 thành chuỗi', () {
      final nft = VatPhamNFT.fromJson({
        ...metadata(),
        'tokenId': 9007199254740991,
        'balance': 0,
        'maxSupply': 1,
        'chainId': '31337',
      });
      expect(nft.tokenId.toString(), '9007199254740991');
      expect(nft.balance, BigInt.zero);
      expect(nft.toJson()['tokenId'], '9007199254740991');
      expect(nft.toJson()['balance'], '0');
      expect(nft.toJson()['maxSupply'], '1');
      expect(nft.chainId, 31337);
    });

    for (final field in ['tokenId', 'balance', 'maxSupply']) {
      test('$field từ chối số âm, số JSON không an toàn, tràn và sai kiểu', () {
        for (final invalid in [
          -1,
          '-1',
          1.5,
          1.0,
          '1.5',
          '1e3',
          '0x1',
          '',
          ' 1',
          true,
          9007199254740992,
          (BigInt.one << 256).toString(),
        ]) {
          expect(
            () => VatPhamNFT.fromJson({...metadata(), field: invalid}),
            throwsFormatException,
            reason: '$field = $invalid',
          );
        }
      });
    }

    test('tokenId/maxSupply phải dương; balance bằng 0 hợp lệ', () {
      for (final field in ['tokenId', 'maxSupply']) {
        for (final zero in [0, '0']) {
          expect(
            () => VatPhamNFT.fromJson({...metadata(), field: zero}),
            throwsFormatException,
          );
        }
      }
      expect(
        () => VatPhamNFT.fromJson({...metadata(), 'tokenId': null}),
        throwsFormatException,
      );
      expect(
        VatPhamNFT.fromJson({...metadata(), 'balance': '0'}).balance,
        BigInt.zero,
      );
    });

    test('chainId phải dương và trong phạm vi int JSON an toàn', () {
      for (final invalid in [
        null,
        0,
        -1,
        '0',
        '1.5',
        1.0,
        true,
        9007199254740992,
        maxUint256.toString(),
      ]) {
        expect(
          () => VatPhamNFT.fromJson({...metadata(), 'chainId': invalid}),
          throwsFormatException,
        );
      }
      expect(
        VatPhamNFT.fromJson({...metadata(), 'chainId': '9007199254740991'})
            .chainId,
        9007199254740991,
      );
    });

    test('từ chối metadata sai kiểu, category lạ, URI rỗng và địa chỉ sai', () {
      for (final invalid in <Map<String, dynamic>>[
        {'name': null},
        {'description': 12},
        {'category': 'unknown'},
        {'category': null},
        {'category': 1},
        {'imageUrl': 123},
        {'metadataUri': 123},
        {'metadataUri': ''},
        {'contractAddress': null},
        {'contractAddress': '0x123'},
        {'contractAddress': '0x${'0' * 40}'},
        {'walletAddress': false},
        {'walletAddress': '0x123'},
        {'walletAddress': '0x${'0' * 40}'},
      ]) {
        expect(
          () => VatPhamNFT.fromJson({...metadata(), ...invalid}),
          throwsFormatException,
          reason: invalid.toString(),
        );
      }
    });
  });

  group('copyWith và phiên ví', () {
    test('giữ trường không cập nhật, định danh và đối tượng gốc', () {
      final original = verified();
      final updated = original.copyWith(
        name: 'Tên mới',
        description: 'Mô tả mới',
        category: LoaiVatPhamNFT.khien,
        imageUrl: 'ipfs://example/khien.png',
        metadataUri: 'ipfs://example/khien.json',
        maxSupply: BigInt.from(10),
      );
      expect(updated.tokenId, original.tokenId);
      expect(updated.contractAddress, original.contractAddress);
      expect(updated.chainId, original.chainId);
      expect(updated.name, 'Tên mới');
      expect(updated.description, 'Mô tả mới');
      expect(updated.category, LoaiVatPhamNFT.khien);
      expect(updated.imageUrl, 'ipfs://example/khien.png');
      expect(updated.metadataUri, 'ipfs://example/khien.json');
      expect(updated.maxSupply, BigInt.from(10));
      expect(updated.balance, BigInt.one);
      expect(updated.owned, isTrue);
      expect(original.name, 'Kiếm Vàng');
      expect(original.maxSupply, isNull);
      expect(original.imageUrl, isNull);
      expect(original.copyWith().toJson(), original.toJson());
    });

    test(
      'xóa được các trường metadata nullable; cờ clear ưu tiên giá trị mới',
      () {
        final original = verified().copyWith(
          imageUrl: 'ipfs://image',
          metadataUri: 'ipfs://metadata',
          maxSupply: BigInt.from(10),
        );
        final cleared = original.copyWith(
          imageUrl: 'ipfs://replacement',
          clearImageUrl: true,
          metadataUri: 'ipfs://replacement',
          clearMetadataUri: true,
          maxSupply: BigInt.from(20),
          clearMaxSupply: true,
        );
        expect(cleared.imageUrl, isNull);
        expect(cleared.metadataUri, isNull);
        expect(cleared.maxSupply, isNull);
        expect(cleared.owned, isTrue);
        expect(original.maxSupply, BigInt.from(10));
      },
    );

    test('thay số dư tự bỏ xác minh nếu chưa xác nhận lại từ chuỗi', () {
      final original = verified();
      final updated = original.copyWith(balance: BigInt.from(2));
      expect(updated.balance, BigInt.from(2));
      expect(updated.walletAddress, walletA);
      expect(updated.verifiedBalance, isNull);
      expect(updated.owned, isFalse);
      expect(original.owned, isTrue);
    });

    test('cập nhật số dư 0 đã đọc từ chuỗi sẽ bỏ sở hữu', () {
      final updated = verified().copyWith(
        balance: BigInt.zero,
        balanceStatus: TrangThaiSoDuNFT.daKiemTra,
      );
      expect(updated.verifiedBalance, BigInt.zero);
      expect(updated.owned, isFalse);
    });

    test('đổi ví xóa số dư và xác minh cũ', () {
      final original = verified();
      final updated = original.copyWith(walletAddress: walletB);
      expect(updated.walletAddress, walletB);
      expect(updated.balance, isNull);
      expect(updated.balanceStatus, TrangThaiSoDuNFT.chuaKiemTra);
      expect(updated.owned, isFalse);
      expect(original.walletAddress, walletA);
      expect(original.owned, isTrue);
    });

    test(
      'đổi ví cùng số dư mới chỉ xác minh khi truyền trạng thái rõ ràng',
      () {
        final cached = verified().copyWith(
          walletAddress: walletB,
          balance: BigInt.from(2),
        );
        expect(cached.owned, isFalse);
        final updated = cached.copyWith(
          balanceStatus: TrangThaiSoDuNFT.daKiemTra,
        );
        expect(updated.walletAddress, walletB);
        expect(updated.verifiedBalance, BigInt.from(2));
        expect(updated.owned, isTrue);
      },
    );

    test('địa chỉ khác chữ hoa/thường vẫn là cùng một ví', () {
      final updated = verified().copyWith(walletAddress: '0x${'B' * 40}');
      expect(updated.balance, BigInt.one);
      expect(updated.owned, isTrue);
    });

    for (final clearWallet in [false, true]) {
      test('xóa ${clearWallet ? 'ví' : 'số dư'} luôn bỏ xác minh', () {
        final cleared = verified().copyWith(
          clearWalletAddress: clearWallet,
          clearBalance: !clearWallet,
          balanceStatus: TrangThaiSoDuNFT.daKiemTra,
        );
        expect(cleared.balance, isNull);
        expect(cleared.balanceStatus, TrangThaiSoDuNFT.chuaKiemTra);
        expect(cleared.owned, isFalse);
        expect(cleared.walletAddress, clearWallet ? null : walletA);
      });
    }

    test('bỏ xác minh thủ công vẫn giữ bản cache để tải lại', () {
      final cached = verified().copyWith(
        balanceStatus: TrangThaiSoDuNFT.chuaKiemTra,
      );
      expect(cached.balance, BigInt.one);
      expect(cached.verifiedBalance, isNull);
      expect(cached.owned, isFalse);
    });
  });

  group('Giới hạn constructor', () {
    test('tokenId dương và nằm trong uint256', () {
      for (final id in [BigInt.zero, -BigInt.one, BigInt.one << 256]) {
        expect(
          () => VatPhamNFT(
            tokenId: id,
            name: 'Tên',
            description: '',
            category: LoaiVatPhamNFT.vuKhi,
            contractAddress: contract,
            chainId: 31337,
          ),
          throwsArgumentError,
        );
      }
    });

    test('copyWith cũng kiểm tra balance/maxSupply và địa chỉ', () {
      for (final invalid in [-BigInt.one, BigInt.one << 256]) {
        expect(() => item().copyWith(balance: invalid), throwsArgumentError);
        expect(() => item().copyWith(maxSupply: invalid), throwsArgumentError);
      }
      expect(
        () => item().copyWith(maxSupply: BigInt.zero),
        throwsArgumentError,
      );
      expect(
        () => item().copyWith(walletAddress: '0x123'),
        throwsArgumentError,
      );
      expect(() => item().copyWith(metadataUri: ''), throwsArgumentError);
    });

    test('chainId không được zero, âm hoặc vượt int an toàn', () {
      for (final chain in [0, -1, 9007199254740992]) {
        expect(
          () => VatPhamNFT(
            tokenId: BigInt.one,
            name: 'Tên',
            description: '',
            category: LoaiVatPhamNFT.vuKhi,
            contractAddress: contract,
            chainId: chain,
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
