@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gold_rush/blockchain/loi_hop_dong.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/blockchain/sbt/sbt_model.dart';
import 'package:gold_rush/blockchain/sbt/sbt_service.dart';
import 'package:gold_rush/blockchain/vi.dart';

// Kiểm thử lớp JS interop hiện có bằng provider EIP-1193 THỬ NGHIỆM.
// Không phải tiện ích MetaMask thật, không ký phiếu ở Flutter.
class ProviderThu {
  final Future<Object?> Function(String, List<dynamic>) hoi;
  final methods = <String>[];
  final listeners = <String, JSFunction>{};
  final object = JSObject();

  ProviderThu(this.hoi) {
    object.setProperty(
      'request'.toJS,
      ((JSObject request) {
        final data = Map<String, dynamic>.from(request.dartify()! as Map);
        final method = data['method'] as String;
        final params = List<dynamic>.from(data['params'] as List);
        methods.add(method);
        return JSPromise<JSAny?>(
          ((JSFunction resolve, JSFunction reject) {
            unawaited(() async {
              try {
                final answer = await hoi(method, params);
                resolve.callAsFunction(null, answer.jsify());
              } catch (error) {
                reject.callAsFunction(
                  null,
                  (error is Map ? error : {'code': -32603, 'message': '$error'})
                      .jsify(),
                );
              }
            }());
          }).toJS,
        );
      }).toJS,
    );
    object.setProperty(
      'on'.toJS,
      ((String name, JSFunction callback) {
        listeners[name] = callback;
      }).toJS,
    );
    globalContext.setProperty('ethereum'.toJS, object);
  }

  void emit(String event, Object value) =>
      listeners[event]?.callAsFunction(null, value.jsify());
}

const _fixtureJson = String.fromEnvironment('SBT_WEB_FIXTURE');

void main() {
  tearDown(() => globalContext.delete('ethereum'.toJS));

  test(
    'vi_web: tài khoản, chain, sự kiện và lỗi 4001 đi qua Promise JS thật',
    () async {
      final player = '0x${'a' * 40}';
      final provider = ProviderThu(
        (method, params) async => switch (method) {
          'eth_requestAccounts' || 'eth_accounts' => [player],
          'eth_chainId' => '0x7a69',
          'eth_sendTransaction' => throw {
            'code': 4001,
            'message': 'User rejected the request',
          },
          _ => throw StateError('Không hỗ trợ $method'),
        },
      );
      final vi = taoViMacDinh();
      expect(vi.coSan, isTrue);
      expect(await vi.ketNoi(), player);
      expect(await vi.taiKhoan(), [player]);
      expect(await vi.chainId(), 31337);
      final event = vi.suKien.first;
      provider.emit('accountsChanged', <String>[]);
      expect((await event as DoiTaiKhoan).taiKhoan, isEmpty);
      await expectLater(
        vi.guiGiaoDich(tu: player, toi: player, duLieu: '0x'),
        throwsA(
          isA<LoiVi>().having((e) => e.nguoiDungTuChoi, 'tuChoi', isTrue),
        ),
      );
      expect(provider.methods, isNot(contains('eth_signTypedData_v4')));
    },
  );

  test('model JSON uint256 giữ chính xác trên Chrome và không tin quyền sở hữu cache', () {
    final tokenId = (BigInt.one << 256) - BigInt.one;
    final before = bangThanhTuuSBT.first.copyWith(
      tokenId: tokenId,
      ownershipStatus: TrangThaiSoHuuSBT.daSoHuu,
      selectedForDisplay: true,
    );
    final after = ThanhTuuSBT.fromJson(
      jsonDecode(jsonEncode(before.toJson())) as Map<String, dynamic>,
    );
    expect(after.tokenId, tokenId);
    expect(after.owned, isFalse);
    expect(after.displayed, isFalse);
  });

  test(
    'Flutter Web → vi_web → Hardhat thật: claim, chữ ký sai, hết hạn và vàng không đổi',
    () async {
      final fixture = jsonDecode(_fixtureJson) as Map<String, dynamic>;
      final rpcUrl = Uri.parse(fixture['rpcUrl'] as String);
      expect(['127.0.0.1', 'localhost', '::1'], contains(rpcUrl.host));
      final rpc = http.Client();
      final noBackend = MockClient(
        (_) async =>
            throw StateError('Không gọi API Backend trong kiểm thử Web'),
      );
      addTearDown(() {
        rpc.close();
        noBackend.close();
      });
      var requestId = 0;
      var decline = false;
      var sends = 0;
      final player = fixture['player'] as String;
      final provider = ProviderThu((method, params) async {
        if (method == 'eth_accounts' || method == 'eth_requestAccounts') {
          return [player];
        }
        if (method == 'eth_sendTransaction') {
          if (decline) throw {'code': 4001, 'message': 'User rejected'};
          sends++;
        }
        final response = await rpc.post(
          rpcUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': requestId++,
            'method': method,
            'params': params,
          }),
        );
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        if (result['error'] != null) {
          throw Map<String, dynamic>.from(result['error'] as Map);
        }
        return result['result'];
      });
      final vi = taoViMacDinh();
      final phien = PhienVi(
        vi: vi,
        mayChu: MayChuPhieu(mayChu: '', client: noBackend),
      );
      addTearDown(phien.dispose);
      phien.diaChi = await vi.ketNoi();
      final config = CauHinhSBT(
        chainId: fixture['chainId'] as int,
        hopDong: fixture['address'] as String,
      );
      final service = DichVuSBT(
        phienVi: phien,
        cauHinh: config,
        nhipKiemTra: const Duration(milliseconds: 50),
        choToiDa: const Duration(seconds: 15),
      );
      PhieuSBTDaKy voucher(String key) {
        final json = Map<String, dynamic>.from(fixture[key] as Map);
        return PhieuSBTDaKy(
          phieu: PhieuSBT.fromJson(
            Map<String, dynamic>.from(json['phieu'] as Map),
          ),
          chuKy: json['chuKy'] as String,
          cauHinh: config,
        );
      }

      final badge = bangThanhTuuSBT.first;
      expect((await service.taiThanhTuu(badge)).owned, isFalse);
      expect(
        (await service.docSigner()).toLowerCase(),
        (fixture['backendSigner'] as String).toLowerCase(),
      );
      // Chưa có phiếu không được gửi, kể cả UI ghi đủ điều kiện.
      await expectLater(
        service.nhanThanhTuu(
          badge.copyWith(eligibilityStatus: TrangThaiDieuKienSBT.duDieuKien),
        ),
        throwsA(isA<LoiVi>()),
      );
      expect(sends, 0);
      for (final key in ['invalid', 'expired']) {
        final v = voucher(key);
        await expectLater(
          service.nhanThanhTuu(
            bangThanhTuuSBT[v.phieu.achievementId - 1],
            phieu: v,
          ),
          throwsA(
            isA<LoiVi>().having(
              (e) => e.thongBao,
              'revert',
              contains(
                key == 'invalid' ? 'InvalidSignature' : 'VoucherExpired',
              ),
            ),
          ),
        );
        expect(sends, 0);
      }
      decline = true;
      final canceled = <ThanhTuuSBT>[];
      await expectLater(
        service.nhanThanhTuu(
          badge,
          phieu: voucher('valid'),
          khiCapNhat: canceled.add,
        ),
        throwsA(
          isA<LoiVi>().having((e) => e.nguoiDungTuChoi, 'tuChoi', isTrue),
        ),
      );
      expect(canceled.last.claimStatus, TrangThaiNhanSBT.daHuy);
      expect(canceled.last.owned, isFalse);
      expect(sends, 0);
      decline = false;
      final states = <ThanhTuuSBT>[];
      final hashes = <String>[];
      final owned = await service.nhanThanhTuu(
        badge,
        phieu: voucher('valid'),
        khiCapNhat: states.add,
        khiDaGui: hashes.add,
      );
      expect(owned.owned, isTrue);
      expect(
        states.take(states.length - 1).every((state) => !state.owned),
        isTrue,
      );
      expect(hashes.single, matches(r'^0x[0-9a-fA-F]{64}$'));
      expect(sends, 1);
      expect((await service.taiThanhTuu(badge)).owned, isTrue);
      final token = await service.docToken(BigInt.one);
      expect(token.owner.toLowerCase(), player.toLowerCase());
      expect(token.achievementId, 1);
      // Service nhận ra đã sở hữu, không gửi lại và không tốn thêm phí.
      expect(
        (await service.nhanThanhTuu(badge, phieu: voucher('duplicate'))).owned,
        isTrue,
      );
      expect(sends, 1);
      // Kiểm tra trực tiếp hợp đồng từ chối nonce cũ và thành tích trùng.
      for (final key in ['valid', 'duplicate']) {
        final data =
            (fixture[key] as Map<String, dynamic>)['calldata'] as String;
        await expectLater(
          vi.goi(toi: config.hopDong, duLieu: data, tu: player),
          throwsA(
            isA<LoiVi>().having(
              (e) => timDuLieuRevert(e.duLieu),
              'revert data',
              startsWith(key == 'valid' ? '0x8c242285' : '0x509e2d52'),
            ),
          ),
        );
      }
      final goldCalls = List<String>.from(fixture['goldCalls'] as List);
      for (var i = 0; i < goldCalls.length; i++) {
        expect(
          await vi.goi(toi: fixture['shop'] as String, duLieu: goldCalls[i]),
          (fixture['goldBefore'] as List)[i],
        );
      }
      expect(
        provider.methods.any(
          (method) =>
              method.startsWith('eth_sign') || method == 'personal_sign',
        ),
        isFalse,
      );
      // In bằng chứng kiểm thử; đây là giao dịch thử từ node mở khóa, không phải MetaMask thật.
      printOnFailure('SBT transaction: ${hashes.single}');
    },
    skip: _fixtureJson.isEmpty
        ? 'Cần fixture từ chuan_bi_web.mjs và Hardhat local riêng.'
        : false,
  );
}
