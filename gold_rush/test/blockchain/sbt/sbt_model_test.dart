import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/sbt/sbt_model.dart';

void main() {
  Map<String, dynamic> metadata() => {
    'achievementId': 1,
    'name': 'Thợ Mỏ Tập Sự',
    'description': 'Hoàn thành màn 1.',
  };

  group('Danh mục SBT', () {
    test('khớp năm ID của hợp đồng và không gán ảnh hay quyền sở hữu giả', () {
      expect(bangThanhTuuSBT.map((sbt) => sbt.achievementId), [1, 2, 3, 4, 5]);
      expect(bangThanhTuuSBT.map((sbt) => sbt.name), [
        'Thợ Mỏ Tập Sự',
        'Nhà Thám Hiểm Rừng Xanh',
        'Kẻ Săn Boss',
        'Chiến Binh Bất Bại',
        'Huyền Thoại Gold Rush',
      ]);
      for (final sbt in bangThanhTuuSBT) {
        expect(sbt.imagePath, isNull);
        expect(sbt.tokenId, isNull);
        expect(sbt.owned, isFalse);
        expect(sbt.eligible, isFalse);
        expect(sbt.displayed, isFalse);
        expect(sbt.ownershipStatus, TrangThaiSoHuuSBT.chuaKiemTra);
      }
      expect(() => bangThanhTuuSBT.clear(), throwsUnsupportedError);
    });
  });

  group('Trạng thái độc lập', () {
    test('đủ điều kiện, có tokenId và giao dịch thành công không tự cấp quyền sở hữu', () {
      final sbt = bangThanhTuuSBT.first.copyWith(
        eligibilityStatus: TrangThaiDieuKienSBT.duDieuKien,
        claimStatus: TrangThaiNhanSBT.thanhCong,
        tokenId: BigInt.one,
        selectedForDisplay: true,
      );
      expect(sbt.eligible, isTrue);
      expect(sbt.owned, isFalse);
      expect(sbt.selectedForDisplay, isTrue);
      expect(sbt.displayed, isFalse);
    });

    test('quyền sở hữu đã xác minh không phụ thuộc điều kiện hoặc việc biết tokenId', () {
      final sbt = bangThanhTuuSBT.first.copyWith(
        ownershipStatus: TrangThaiSoHuuSBT.daSoHuu,
      );
      expect(sbt.owned, isTrue);
      expect(sbt.eligible, isFalse);
      expect(sbt.tokenId, isNull);
      expect(sbt.displayed, isFalse);
      expect(sbt.copyWith(selectedForDisplay: true).displayed, isTrue);
      expect(
        sbt.copyWith(ownershipStatus: TrangThaiSoHuuSBT.chuaSoHuu).owned,
        isFalse,
      );
    });
  });

  group('JSON', () {
    test('đọc metadata tối thiểu với trạng thái mặc định chưa kiểm tra', () {
      final sbt = ThanhTuuSBT.fromJson(metadata());
      expect(sbt.achievementId, 1);
      expect(sbt.name, metadata()['name']);
      expect(sbt.description, metadata()['description']);
      expect(sbt.eligibilityStatus, TrangThaiDieuKienSBT.chuaKiemTra);
      expect(sbt.ownershipStatus, TrangThaiSoHuuSBT.chuaKiemTra);
      expect(sbt.claimStatus, TrangThaiNhanSBT.chuaBatDau);
      expect(sbt.owned, isFalse);
    });

    test('không tin owned/ownershipStatus/displayed từ JSON', () {
      final sbt = ThanhTuuSBT.fromJson({
        ...metadata(),
        'owned': true,
        'ownershipStatus': 'daSoHuu',
        'displayed': true,
        'selectedForDisplay': true,
        'eligibilityStatus': 'duDieuKien',
        'claimStatus': 'thanhCong',
        'tokenId': '123',
      });
      expect(sbt.tokenId, BigInt.from(123));
      expect(sbt.eligible, isTrue);
      expect(sbt.selectedForDisplay, isTrue);
      expect(sbt.ownershipStatus, TrangThaiSoHuuSBT.chuaKiemTra);
      expect(sbt.owned, isFalse);
      expect(sbt.displayed, isFalse);
    });

    test(
      'round-trip JSON giữ uint256 chính xác nhưng yêu cầu xác minh lại sở hữu',
      () {
        final maxTokenId = (BigInt.one << 256) - BigInt.one;
        final original = bangThanhTuuSBT.first.copyWith(
          tokenId: maxTokenId,
          ownershipStatus: TrangThaiSoHuuSBT.daSoHuu,
          eligibilityStatus: TrangThaiDieuKienSBT.duDieuKien,
          claimStatus: TrangThaiNhanSBT.thanhCong,
          selectedForDisplay: true,
        );
        final json = original.toJson();
        expect(json['tokenId'], maxTokenId.toString());
        expect(json['owned'], isTrue);
        expect(json['displayed'], isTrue);
        final restored = ThanhTuuSBT.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        );
        expect(restored.achievementId, original.achievementId);
        expect(restored.name, original.name);
        expect(restored.description, original.description);
        expect(restored.tokenId, maxTokenId);
        expect(restored.imagePath, isNull);
        expect(restored.eligibilityStatus, original.eligibilityStatus);
        expect(restored.claimStatus, original.claimStatus);
        expect(restored.selectedForDisplay, isTrue);
        expect(restored.owned, isFalse);
        expect(restored.displayed, isFalse);
        expect(
          restored
              .copyWith(ownershipStatus: TrangThaiSoHuuSBT.daSoHuu)
              .displayed,
          isTrue,
        );
      },
    );

    test(
      'đọc ID thành tích dạng số hoặc chuỗi thập phân và tokenId nhỏ dạng số',
      () {
        for (final id in [1, '1']) {
          final sbt = ThanhTuuSBT.fromJson({
            ...metadata(),
            'achievementId': id,
            'tokenId': 17,
          });
          expect(sbt.achievementId, 1);
          expect(sbt.tokenId, BigInt.from(17));
          expect(sbt.owned, isFalse);
        }
      },
    );

    test('không suy ra tokenId từ achievementId', () {
      final sbt = ThanhTuuSBT.fromJson({
        ...metadata(),
        'achievementId': 3,
        'tokenId': '42',
      });
      expect(sbt.achievementId, 3);
      expect(sbt.tokenId, BigInt.from(42));
      expect(ThanhTuuSBT.fromJson(metadata()).tokenId, isNull);
    });

    test('từ chối ID thành tích sai kiểu hoặc ngoài phạm vi hợp đồng', () {
      for (final id in [null, 0, 6, -1, 1.5, '1.0', '0x1', true]) {
        expect(
          () => ThanhTuuSBT.fromJson({...metadata(), 'achievementId': id}),
          throwsFormatException,
        );
      }
    });

    test('từ chối tokenId âm, zero, tràn uint256, số JSON không an toàn hoặc sai kiểu', () {
      for (final tokenId in [
        0,
        -1,
        '0',
        '-1',
        '1.5',
        '0x1',
        1.5,
        true,
        '',
        9007199254740992,
        (BigInt.one << 256).toString(),
      ]) {
        expect(
          () => ThanhTuuSBT.fromJson({...metadata(), 'tokenId': tokenId}),
          throwsFormatException,
        );
      }
    });

    test('từ chối metadata, lựa chọn và enum sai kiểu; không tự nâng quyền trạng thái', () {
      for (final invalid in <Map<String, dynamic>>[
        {'name': 1},
        {'description': null},
        {'imagePath': 123},
        {'selectedForDisplay': 'true'},
        {'eligibilityStatus': 'unknown'},
        {'claimStatus': 1},
      ]) {
        expect(
          () => ThanhTuuSBT.fromJson({...metadata(), ...invalid}),
          throwsFormatException,
        );
      }
    });

    test('lưu và nạp tất cả trạng thái điều kiện/giao dịch theo tên enum', () {
      for (final status in TrangThaiDieuKienSBT.values) {
        final sbt = bangThanhTuuSBT.first.copyWith(eligibilityStatus: status);
        expect(ThanhTuuSBT.fromJson(sbt.toJson()).eligibilityStatus, status);
      }
      for (final status in TrangThaiNhanSBT.values) {
        final sbt = bangThanhTuuSBT.first.copyWith(claimStatus: status);
        expect(ThanhTuuSBT.fromJson(sbt.toJson()).claimStatus, status);
      }
    });
  });

  group('copyWith', () {
    test('giữ nguyên giá trị không cập nhật và không sửa đối tượng gốc', () {
      final original = bangThanhTuuSBT.first.copyWith(tokenId: BigInt.from(42));
      final updated = original.copyWith(
        name: 'Tên hiển thị',
        description: 'Mô tả hiển thị',
        eligibilityStatus: TrangThaiDieuKienSBT.duDieuKien,
        claimStatus: TrangThaiNhanSBT.choXacNhanChuoi,
      );
      expect(updated.achievementId, original.achievementId);
      expect(updated.tokenId, original.tokenId);
      expect(updated.ownershipStatus, original.ownershipStatus);
      expect(updated.name, 'Tên hiển thị');
      expect(updated.description, 'Mô tả hiển thị');
      expect(updated.eligible, isTrue);
      expect(updated.claimStatus, TrangThaiNhanSBT.choXacNhanChuoi);
      expect(original.name, 'Thợ Mỏ Tập Sự');
      expect(original.eligible, isFalse);
      expect(original.claimStatus, TrangThaiNhanSBT.chuaBatDau);
      expect(original.copyWith().toJson(), original.toJson());
    });

    test('cập nhật và xóa được các trường nullable', () {
      // Dùng asset thực sự tồn tại, chỉ để kiểm tra giá trị imagePath.
      const existingAsset = 'assets/images/dong_xu.png';
      expect(File(existingAsset).existsSync(), isTrue);
      final original = bangThanhTuuSBT.first.copyWith(
        imagePath: existingAsset,
        tokenId: BigInt.one,
      );
      expect(ThanhTuuSBT.fromJson(original.toJson()).imagePath, existingAsset);
      expect(original.copyWith().imagePath, existingAsset);
      final updated = original.copyWith(tokenId: BigInt.from(42));
      expect(updated.tokenId, BigInt.from(42));
      final cleared = updated.copyWith(
        clearImagePath: true,
        clearTokenId: true,
      );
      expect(cleared.imagePath, isNull);
      expect(cleared.tokenId, isNull);
      expect(original.imagePath, existingAsset);
      expect(original.tokenId, BigInt.one);
    });

    test('đổi ví/mạng có thể bỏ xác minh và dữ liệu token, không trưng bày cache cũ', () {
      final original = bangThanhTuuSBT.first.copyWith(
        tokenId: BigInt.one,
        ownershipStatus: TrangThaiSoHuuSBT.daSoHuu,
        selectedForDisplay: true,
      );
      expect(original.displayed, isTrue);
      final reset = original.copyWith(
        ownershipStatus: TrangThaiSoHuuSBT.chuaKiemTra,
        clearTokenId: true,
        selectedForDisplay: false,
      );
      expect(reset.owned, isFalse);
      expect(reset.tokenId, isNull);
      expect(reset.displayed, isFalse);
      expect(original.owned, isTrue);
    });

    test('constructor và copyWith đều kiểm tra giới hạn uint256', () {
      for (final tokenId in [BigInt.zero, -BigInt.one, BigInt.one << 256]) {
        expect(
          () => bangThanhTuuSBT.first.copyWith(tokenId: tokenId),
          throwsArgumentError,
        );
      }
      for (final id in [0, 6]) {
        expect(
          () =>
              ThanhTuuSBT(achievementId: id, name: 'Tên', description: 'Mô tả'),
          throwsRangeError,
        );
      }
    });
  });
}
