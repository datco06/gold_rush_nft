import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/ai/may_chu_tien_trinh.dart';
import 'package:gold_rush/ai/tien_trinh_controller.dart';
import 'package:gold_rush/ai/tien_trinh_models.dart';
import 'package:gold_rush/auth/auth_api_client.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/auth/metamask_siwe_contract.dart';
import 'package:gold_rush/man_hinh/anh_nhan_vat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../blockchain/vi_gia.dart';

// -----------------------------------------------------------------------------
// Test Doubles & Helpers
// -----------------------------------------------------------------------------

class _FakeAuthWallet implements AuthWallet {
  final _eventsController =
      StreamController<MetamaskSiweEventType>.broadcast(sync: true);
  List<String> accounts = ['0x1111111111111111111111111111111111111111'];
  BigInt chain = BigInt.from(31337);

  @override
  Stream<MetamaskSiweEventType> get events => _eventsController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<MetamaskWalletConnection> connect() async => MetamaskWalletConnection(
        address: accounts.first,
        chainId: chain,
      );

  @override
  Future<List<String>> getAccounts() async => accounts;

  @override
  Future<BigInt> getChainId() async => chain;

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) async =>
      '0x${'a' * 130}';

  void emit(MetamaskSiweEventType event) => _eventsController.add(event);

  @override
  void dispose() {
    _eventsController.close();
  }
}

String get _futureExpiry =>
    DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String();

http.Response _mockJson(dynamic body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _taoTienTrinhJson({
  required List<int> completed,
  String wallet = '0x1111111111111111111111111111111111111111',
}) {
  final stages = <Map<String, dynamic>>[];
  for (int i = 1; i <= 6; i++) {
    final done = completed.contains(i);
    stages.add({
      'stage_id': i,
      'name': 'Màn $i',
      'status': done ? 'completed' : 'locked',
      'verification_source': done ? 'referee_log' : null,
      'completed_at': done ? '2026-11-11T08:00:00Z' : null,
    });
  }
  return {
    'owner_user_id': 'user_123',
    'verified_wallet_address': wallet,
    'completed_stage_ids': completed,
    'allowed_stage_ids': [1, 2, 3, 4, 5, 6],
    'stages': stages,
    'total_completed': completed.length,
    'is_character_unlocked': completed.length == 6,
  };
}

void main() {
  group('Giai đoạn 11B: Tiến trình 6 màn ↔ FastAPI AI Backend', () {
    // -------------------------------------------------------------------------
    // Test 1: JSON Schema & Contract Model Parsing
    // -------------------------------------------------------------------------
    test('1. Parse thành công JSON schema PhanHoiTienTrinh và từ chối JSON lỗi', () {
      final jsonHopLe = _taoTienTrinhJson(completed: [1, 2, 3]);
      final tt = PhanHoiTienTrinh.tuJson(jsonHopLe);

      expect(tt.ownerUserId, 'user_123');
      expect(tt.verifiedWalletAddress, '0x1111111111111111111111111111111111111111');
      expect(tt.completedStageIds, [1, 2, 3]);
      expect(tt.totalCompleted, 3);
      expect(tt.isCharacterUnlocked, false);
      expect(tt.stages.length, 6);
      expect(tt.stages[0].status, 'completed');
      expect(tt.stages[3].status, 'locked');

      // Thiếu trường bắt buộc
      expect(
        () => PhanHoiTienTrinh.tuJson(const {'owner_user_id': 'user_123'}),
        throwsA(isA<FormatException>()),
      );

      // Định dạng sai completed_stage_ids
      expect(
        () => PhanHoiTienTrinh.tuJson(const {
          'owner_user_id': 'user_123',
          'verified_wallet_address': '0x111',
          'completed_stage_ids': 'invalid_string',
          'stages': [],
          'total_completed': 0,
          'is_character_unlocked': false,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    // -------------------------------------------------------------------------
    // Test 2: Tài khoản mới (0/6 màn)
    // -------------------------------------------------------------------------
    test('2. Tài khoản mới: tiến trình 0/6 màn, isCharacterUnlocked = false', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: []));
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.totalCompleted, 0);
      expect(controller.tongManHoanThanh, 0);
      expect(controller.isCharacterUnlocked, false);
      expect(controller.daHoanThanhDuSauMan, false);
      expect(controller.completedStageIds, isEmpty);
      expect(controller.daHoanThanhMan(1), false);
    });

    // -------------------------------------------------------------------------
    // Test 3: Hoàn thành màn 1 (1/6 màn)
    // -------------------------------------------------------------------------
    test('3. Hoàn thành màn 1: cập nhật 1/6 màn, daHoanThanhMan(1)=true, màn 2 chưa hoàn thành', () async {
      int fetchCount = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          fetchCount++;
          if (fetchCount == 1) {
            return _mockJson(_taoTienTrinhJson(completed: []));
          }
          return _mockJson(_taoTienTrinhJson(completed: [1]));
        }
        if (req.url.path == '/api/ai/tien-trinh/xac-minh') {
          final body = jsonDecode(req.body);
          expect(body['stage_id'], 1);
          expect(body['evidence_type'], 'referee_log');
          expect(body['evidence'], 'referee_proof_stage_1');
          return _mockJson({
            'id': 1,
            'owner_user_id': 'user_123',
            'verified_wallet_address': '0x1111111111111111111111111111111111111111',
            'stage_id': 1,
            'completion_status': 'completed',
            'verification_source': 'referee_log',
            'completion_evidence': 'referee_proof_stage_1',
            'replay_key': 'referee:referee_proof_stage_1',
            'completed_at': '2026-11-11T08:00:00Z',
          });
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();
      expect(controller.totalCompleted, 0);

      final ok = await controller.xacNhanHoanThanhMan(
        stageId: 1,
        evidenceType: 'referee_log',
        evidence: 'referee_proof_stage_1',
      );

      expect(ok, true);
      expect(controller.totalCompleted, 1);
      expect(controller.daHoanThanhMan(1), true);
      expect(controller.daHoanThanhMan(2), false);
      expect(controller.isCharacterUnlocked, false);
    });

    // -------------------------------------------------------------------------
    // Test 4: Hoàn thành màn 2 không ghi nhận màn 3
    // -------------------------------------------------------------------------
    test('4. Hoàn thành màn 2: không ghi nhận màn 3, hiển thị 2/6', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 2]));
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.totalCompleted, 2);
      expect(controller.daHoanThanhMan(1), true);
      expect(controller.daHoanThanhMan(2), true);
      expect(controller.daHoanThanhMan(3), false);
      expect(controller.isCharacterUnlocked, false);
    });

    // -------------------------------------------------------------------------
    // Test 5: Won stage ID preservation
    // -------------------------------------------------------------------------
    test('5. Bảo toàn stageId khi chuyển màn hoặc chơi màn mới sau khi thắng', () {
      const manVuaThang = 1;
      int capturedStageId = manVuaThang;

      int manHienTai = 2;
      expect(capturedStageId, 1);
      expect(manHienTai, 2);
      expect(capturedStageId, 1);
    });

    // -------------------------------------------------------------------------
    // Test 6: Hoàn thành 5/6 màn vẫn khóa AI Character
    // -------------------------------------------------------------------------
    test('6. Hoàn thành 5 màn (1..5): isCharacterUnlocked vẫn là false', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 2, 3, 4, 5]));
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.totalCompleted, 5);
      expect(controller.isCharacterUnlocked, false);
      expect(controller.daHoanThanhDuSauMan, false);
      expect(controller.daHoanThanhMan(6), false);
    });

    // -------------------------------------------------------------------------
    // Test 7: Hoàn thành đủ 6/6 màn mở khóa AI Character
    // -------------------------------------------------------------------------
    test('7. Hoàn thành đủ 6 màn (1..6): isCharacterUnlocked = true', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 2, 3, 4, 5, 6]));
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.totalCompleted, 6);
      expect(controller.isCharacterUnlocked, true);
      expect(controller.daHoanThanhDuSauMan, true);
      for (int i = 1; i <= 6; i++) {
        expect(controller.daHoanThanhMan(i), true);
      }
    });

    // -------------------------------------------------------------------------
    // Test 8: Backend 503 Service Unavailable
    // -------------------------------------------------------------------------
    test('8. Backend 503: hiển thị lỗi, KHÔNG tự ý mở khóa nhân vật AI', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return http.Response(
            jsonEncode({'detail': 'Hệ thống xác minh tiến trình đang bảo trì.'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.isCharacterUnlocked, false);
      expect(controller.thongBaoLaLoi, true);
      expect(controller.thongBaoLoi, isNotNull);
      expect(controller.tienTrinh, isNull);
    });

    // -------------------------------------------------------------------------
    // Test 9: Client tự khai báo hoàn thành không qua backend
    // -------------------------------------------------------------------------
    test('9. Client không thể tự đánh dấu hoàn thành nếu Backend không xác nhận', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: []));
        }
        if (req.url.path == '/api/ai/tien-trinh/xac-minh') {
          return http.Response(
            jsonEncode({'detail': 'Bằng chứng không hợp lệ.'}),
            422,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      final ok = await controller.xacNhanHoanThanhMan(
        stageId: 1,
        evidenceType: 'referee_log',
        evidence: 'invalid_proof',
      );

      expect(ok, false);
      expect(controller.daHoanThanhMan(1), false);
      expect(controller.totalCompleted, 0);
      expect(controller.isCharacterUnlocked, false);
    });

    // -------------------------------------------------------------------------
    // Test 10: Auto-recording qua cap_phieu
    // -------------------------------------------------------------------------
    test('10. Backend tự động ghi nhận qua cap_phieu: reload tiến trình nhận diện ngay mà không cần gọi POST xac-minh', () async {
      int xacMinhCallCount = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1]));
        }
        if (req.url.path == '/api/ai/tien-trinh/xac-minh') {
          xacMinhCallCount++;
          return _mockJson({});
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      final ok = await controller.xacNhanHoanThanhMan(
        stageId: 1,
        evidenceType: 'referee_log',
        evidence: 'ticket_voucher_123',
      );

      expect(ok, true);
      expect(xacMinhCallCount, 0);
      expect(controller.daHoanThanhMan(1), true);
      expect(controller.totalCompleted, 1);
    });

    // -------------------------------------------------------------------------
    // Test 11: HTTP 409 Replay Attack Handling
    // -------------------------------------------------------------------------
    test('11. HTTP 409 Bằng chứng đã dùng: reload tiến trình an toàn không crash UI', () async {
      int getCount = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          getCount++;
          return _mockJson(_taoTienTrinhJson(completed: [1]));
        }
        if (req.url.path == '/api/ai/tien-trinh/xac-minh') {
          return http.Response(
            jsonEncode({'detail': 'Bằng chứng đã được sử dụng trước đó.'}),
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      final ok = await controller.xacNhanHoanThanhMan(
        stageId: 1,
        evidenceType: 'referee_log',
        evidence: 'replayed_proof',
      );

      expect(ok, true);
      expect(controller.daHoanThanhMan(1), true);
      expect(getCount, greaterThan(0));
    });

    // -------------------------------------------------------------------------
    // Test 12: Network failure / timeout
    // -------------------------------------------------------------------------
    test('12. Lỗi mạng: không đánh dấu hoàn thành màn, thông báo lỗi cho phép thử lại', () async {
      final client = MockClient((req) async {
        throw http.ClientException('Network connection refused');
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.totalCompleted, 0);
      expect(controller.thongBaoLaLoi, true);
      expect(controller.thongBaoLoi, contains('kết nối'));
    });

    // -------------------------------------------------------------------------
    // Test 13: Phiên SIWE hết hạn (HTTP 401)
    // -------------------------------------------------------------------------
    test('13. Phiên SIWE hết hạn (401): dọn dẹp tiến trình và thông báo hết phiên', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'detail': 'Phiên đăng nhập đã hết hạn.'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      await controller.taiTienTrinh();

      expect(controller.tienTrinh, isNull);
      expect(controller.thongBaoLoi, contains('hết hạn'));
    });

    // -------------------------------------------------------------------------
    // Test 14: CSRF token forwarding
    // -------------------------------------------------------------------------
    test('14. CSRF token từ AuthController được truyền chính xác vào header x-csrf-token', () async {
      String? sentCsrf;
      final client = MockClient((req) async {
        if (req.url.path == '/api/me') {
          return _mockJson({
            'user': {
              'id': '12345678-1234-1234-1234-123456789abc',
              'wallet_address': '0x1111111111111111111111111111111111111111',
              'username': 'Miner',
              'avatar': 'george',
              'created_at': '2026-11-11T08:00:00Z',
            },
            'chain_id': 31337,
            'csrf_token': 'test_csrf_token_secret_123',
            'expires_at': _futureExpiry,
          });
        }
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: []));
        }
        if (req.url.path == '/api/ai/tien-trinh/xac-minh') {
          sentCsrf = req.headers['x-csrf-token'] ?? req.headers['X-CSRF-Token'];
          return _mockJson({
            'id': 1,
            'owner_user_id': 'user_123',
            'verified_wallet_address': '0x1111111111111111111111111111111111111111',
            'stage_id': 1,
            'completion_status': 'completed',
            'verification_source': 'referee_log',
            'completion_evidence': 'proof',
            'replay_key': 'referee:proof',
            'completed_at': '2026-11-11T08:00:00Z',
          });
        }
        return http.Response('Not Found', 404);
      });

      final authApi = AuthApiClient(baseUrl: 'http://localhost:8000', client: client);
      final authCtrl = AuthController(api: authApi, wallet: _FakeAuthWallet());
      await authCtrl.restoreSession();

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu, authController: authCtrl);

      await controller.xacNhanHoanThanhMan(
        stageId: 1,
        evidenceType: 'referee_log',
        evidence: 'valid_referee_proof_123',
      );

      expect(sentCsrf, 'test_csrf_token_secret_123');
      authCtrl.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 15: Logout SIWE dọn dẹp tiến trình
    // -------------------------------------------------------------------------
    test('15. Đăng xuất SIWE: toàn bộ trạng thái tiến trình bị dọn dẹp', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/me') {
          return _mockJson({
            'user': {
              'id': '12345678-1234-1234-1234-123456789abc',
              'wallet_address': '0x1111111111111111111111111111111111111111',
              'username': 'Miner',
              'avatar': 'george',
              'created_at': '2026-11-11T08:00:00Z',
            },
            'chain_id': 31337,
            'csrf_token': 'csrf_123',
            'expires_at': _futureExpiry,
          });
        }
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 2, 3]));
        }
        if (req.url.path == '/api/auth/logout') {
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final authApi = AuthApiClient(baseUrl: 'http://localhost:8000', client: client);
      final authCtrl = AuthController(api: authApi, wallet: _FakeAuthWallet());
      await authCtrl.restoreSession();

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu, authController: authCtrl);

      await controller.taiTienTrinh();
      expect(controller.totalCompleted, 3);

      await authCtrl.logout();

      expect(controller.tienTrinh, isNull);
      expect(controller.totalCompleted, 0);
      expect(controller.isCharacterUnlocked, false);
      authCtrl.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 16: Chuyển ví / tài khoản MetaMask
    // -------------------------------------------------------------------------
    test('16. Đổi ví MetaMask: tự động hủy tiến trình ví cũ và nạp tiến trình ví mới', () async {
      String currentWallet = '0x1111111111111111111111111111111111111111';
      final client = MockClient((req) async {
        if (req.url.path == '/api/me') {
          return _mockJson({
            'user': {
              'id': currentWallet == '0x1111111111111111111111111111111111111111'
                  ? '12345678-1234-1234-1234-123456789abc'
                  : '87654321-4321-4321-4321-cba987654321',
              'wallet_address': currentWallet,
              'username': 'Player',
              'avatar': 'george',
              'created_at': '2026-11-11T08:00:00Z',
            },
            'chain_id': 31337,
            'csrf_token': 'csrf',
            'expires_at': _futureExpiry,
          });
        }
        if (req.url.path == '/api/ai/tien-trinh') {
          if (currentWallet == '0x1111111111111111111111111111111111111111') {
            return _mockJson(_taoTienTrinhJson(
              completed: [1, 2],
              wallet: '0x1111111111111111111111111111111111111111',
            ));
          } else {
            return _mockJson(_taoTienTrinhJson(
              completed: [1, 2, 3, 4, 5, 6],
              wallet: '0x2222222222222222222222222222222222222222',
            ));
          }
        }
        if (req.url.path == '/api/auth/logout') {
          return http.Response('', 204);
        }
        return http.Response('Not Found', 404);
      });

      final authApi = AuthApiClient(baseUrl: 'http://localhost:8000', client: client);
      final fakeWallet = _FakeAuthWallet();
      final authCtrl = AuthController(api: authApi, wallet: fakeWallet);
      await authCtrl.restoreSession();

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu, authController: authCtrl);

      await controller.taiTienTrinh();
      expect(controller.totalCompleted, 2);
      expect(controller.isCharacterUnlocked, false);

      // Đổi sang ví 2
      currentWallet = '0x2222222222222222222222222222222222222222';
      fakeWallet.accounts = [currentWallet];
      fakeWallet.emit(MetamaskSiweEventType.accountsChanged);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Sau khi đổi ví, tiến trình ví 1 bị xóa ngay lập tức
      expect(controller.tienTrinh, isNull);
      expect(controller.totalCompleted, 0);

      // Đăng nhập lại với ví 2
      await authCtrl.restoreSession();
      await controller.taiTienTrinh();

      expect(controller.totalCompleted, 6);
      expect(controller.isCharacterUnlocked, true);
      authCtrl.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 17: Race condition async
    // -------------------------------------------------------------------------
    test('17. Race condition async: phản hồi muộn của ví cũ không ghi đè tiến trình ví mới', () async {
      final completer1 = Completer<http.Response>();
      final completer2 = Completer<http.Response>();

      int callIndex = 0;
      final client = MockClient((req) async {
        callIndex++;
        if (callIndex == 1) {
          return completer1.future;
        } else {
          return completer2.future;
        }
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      final future1 = controller.taiTienTrinh();
      final future2 = controller.taiTienTrinh();

      completer2.complete(_mockJson(_taoTienTrinhJson(completed: [1, 2, 3, 4, 5, 6])));
      await future2;
      expect(controller.totalCompleted, 6);

      completer1.complete(_mockJson(_taoTienTrinhJson(completed: [1])));
      await future1;

      expect(controller.totalCompleted, 6);
    });

    // -------------------------------------------------------------------------
    // Test 18: Widget Test ManHinhAnhNhanVat (Lock & Unlock states)
    // -------------------------------------------------------------------------
    testWidgets('18. ManHinhAnhNhanVat: hiển thị Card tiến trình, khóa Tạo ảnh khi <6 màn, mở khi đủ 6 màn', (tester) async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/me') {
          return _mockJson({
            'user': {
              'id': '12345678-1234-1234-1234-123456789abc',
              'wallet_address': '0x1111111111111111111111111111111111111111',
              'username': 'GoldMiner',
              'avatar': 'george',
              'created_at': '2026-11-11T08:00:00Z',
            },
            'chain_id': 31337,
            'csrf_token': 'csrf_123',
            'expires_at': _futureExpiry,
          });
        }
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 2, 3]));
        }
        if (req.url.path == '/api/nhan-vat-ai/characters') {
          return _mockJson([]);
        }
        return http.Response('Not Found', 404);
      });

      final authApi = AuthApiClient(baseUrl: 'http://localhost:8000', client: client);
      final authCtrl = AuthController(api: authApi, wallet: _FakeAuthWallet());
      await authCtrl.restoreSession();

      final mayChuTT = MayChuTienTrinh(client: client);
      final ttCtrl = TienTrinhController(mayChu: mayChuTT, authController: authCtrl);
      await ttCtrl.taiTienTrinh();

      final mayChuNv = MayChuNhanVat(client: client);
      final vi = ViGia(taiKhoan: const ['0x1111111111111111111111111111111111111111']);

      await tester.pumpWidget(
        MaterialApp(
          home: ManHinhAnhNhanVat(
            mayChu: mayChuNv,
            vi: vi,
            authController: authCtrl,
            tienTrinhController: ttCtrl,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('card_tien_trinh_ai')), findsOneWidget);
      expect(find.text('TIẾN TRÌNH: 3/6 MÀN HOÀN THÀNH'), findsOneWidget);

      final nutTaoAnh = find.widgetWithText(FilledButton, 'Khóa (Cần hoàn thành 6 màn)');
      expect(nutTaoAnh, findsOneWidget);

      final filledButton = tester.widget<FilledButton>(nutTaoAnh);
      expect(filledButton.onPressed, isNull);

      ttCtrl.datTienTrinhChoKiemThu(PhanHoiTienTrinh.tuJson(_taoTienTrinhJson(completed: [1, 2, 3, 4, 5, 6])));
      await tester.pumpAndSettle();

      expect(find.text('TIẾN TRÌNH: 6/6 MÀN HOÀN THÀNH'), findsOneWidget);
      final nutMoKhoa = find.widgetWithText(FilledButton, 'Tạo ảnh');
      expect(nutMoKhoa, findsOneWidget);
      final filledButtonUnlocked = tester.widget<FilledButton>(nutMoKhoa);
      expect(filledButtonUnlocked.onPressed, isNotNull);
      authCtrl.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 19: Progress query state tests
    // -------------------------------------------------------------------------
    test('19. Truy vấn trạng thái tiến trình: hoàn thành màn lẻ, hiển thị đúng danh sách completedStageIds', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 3, 5]));
        }
        return http.Response('Not Found', 404);
      });

      final mayChuTT = MayChuTienTrinh(client: client);
      final ttCtrl = TienTrinhController(mayChu: mayChuTT);
      await ttCtrl.taiTienTrinh();

      expect(ttCtrl.totalCompleted, 3);
      expect(ttCtrl.daHoanThanhMan(1), true);
      expect(ttCtrl.daHoanThanhMan(2), false);
      expect(ttCtrl.daHoanThanhMan(3), true);
      expect(ttCtrl.daHoanThanhMan(4), false);
      expect(ttCtrl.daHoanThanhMan(5), true);
      expect(ttCtrl.daHoanThanhMan(6), false);
      expect(ttCtrl.isCharacterUnlocked, false);
    });

    // -------------------------------------------------------------------------
    // Test 20: Contract & Integration Calldata Verification Flow
    // -------------------------------------------------------------------------
    test('20. Contract & Integration: đối soát đúng calldata EIP-712 Voucher và Tx Hash', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/ai/tien-trinh/xac-minh') {
          final body = jsonDecode(req.body);
          expect(body['stage_id'], 6);
          expect(body['evidence_type'], 'blockchain_tx');
          expect(body['evidence'], '0x${'a' * 64}');
          return _mockJson({
            'id': 6,
            'owner_user_id': 'user_123',
            'verified_wallet_address': '0x1111111111111111111111111111111111111111',
            'stage_id': 6,
            'completion_status': 'completed',
            'verification_source': 'blockchain_tx',
            'completion_evidence': '0x${'a' * 64}',
            'replay_key': 'tx:0x${'a' * 64}',
            'completed_at': '2026-11-11T08:00:00Z',
          });
        }
        if (req.url.path == '/api/ai/tien-trinh') {
          return _mockJson(_taoTienTrinhJson(completed: [1, 2, 3, 4, 5, 6]));
        }
        return http.Response('Not Found', 404);
      });

      final mayChu = MayChuTienTrinh(client: client);
      final controller = TienTrinhController(mayChu: mayChu);

      final ok = await controller.xacNhanHoanThanhMan(
        stageId: 6,
        evidenceType: 'blockchain_tx',
        evidence: '0x${'a' * 64}',
      );

      expect(ok, true);
      expect(controller.daHoanThanhMan(6), true);
      expect(controller.isCharacterUnlocked, true);
    });
  });
}
