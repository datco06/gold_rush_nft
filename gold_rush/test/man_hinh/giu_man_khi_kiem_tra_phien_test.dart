import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_api_client.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/auth/metamask_siwe_contract.dart';
import 'package:gold_rush/auth/ui/auth_gate.dart';
import 'package:gold_rush/auth/ui/welcome_screen.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_hinh/ho_so_nhan_vat.dart';
import 'package:gold_rush/man_hinh/kho_do.dart';
import 'package:gold_rush/man_hinh/lich_su_man_choi.dart';

import '../lich_su/ho_tro_lich_su.dart';
import '../ngon_ngu/ho_tro_json.dart';

const _wallet = '0x1111111111111111111111111111111111111111';

class _PassiveWallet implements AuthWallet {
  final _events = StreamController<MetamaskSiweEventType>.broadcast(sync: true);
  @override
  Stream<MetamaskSiweEventType> get events => _events.stream;
  @override
  Future<bool> checkAvailability() async => true;
  @override
  Future<List<String>> getAccounts() async => [_wallet];
  @override
  Future<BigInt> getChainId() async => BigInt.from(31337);
  @override
  void dispose() => unawaited(_events.close());
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected wallet action: ${invocation.memberName}',
  );
}

AuthMeResponse _me({String userId = '80574202-05bd-4577-8edf-d480b37cf9a2'}) =>
    AuthMeResponse.fromJson({
      'user': {
        'id': userId,
        'wallet_address': _wallet,
        'username': 'Test player',
        'avatar': 'george',
        'created_at': '2099-01-01T00:00:00Z',
      },
      'chain_id': 31337,
      'expires_at': '2099-01-01T08:00:00Z',
      'csrf_token': 'test-credential-only',
    });

class _PassiveApi implements AuthApiClient {
  Future<AuthMeResponse> Function()? reading;
  @override
  bool get mutationPending => false;
  @override
  Future<AuthMeResponse> getMe() async =>
      reading == null ? _me() : await reading!();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected API action: ${invocation.memberName}');
}

void main() {
  setUpAll(chuanBiNgonNguChoKiemThu);

  for (final outcome in ['same identity', 'another user', 'rejected session']) {
    testWidgets(
      'Real 60-second session check handles $outcome with Profile history open',
      (tester) async {
        final wallet = _PassiveWallet();
        final api = _PassiveApi();
        final auth = AuthController(
          wallet: wallet,
          api: api,
          clock: () => DateTime.utc(2099),
        );
        final game = GoldRushGame(auth: auth);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          game.danhSachVatPham.dispose();
          game.capHoSoDaDongBo.dispose();
          game.phienVi?.dispose();
          auth.dispose();
          wallet.dispose();
        });
        await auth.restoreSession();
        await tester.binding.setSurfaceSize(const Size(1280, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: AuthGate(
              controller: auth,
              retainGameDuringSessionCheck: true,
              authenticatedBuilder: (context) => TextButton(
                child: const Text('Mở hồ sơ'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CharacterProfileScreen(game: game),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Mở hồ sơ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lịch sử màn chơi'));
        await tester.pumpAndSettle();
        final current = find.byType(ManHinhLichSuManChoi);
        final before = tester.state(current);
        final reading = Completer<AuthMeResponse>();
        api.reading = () => reading.future;
        await tester.pump(const Duration(seconds: 60));
        expect(auth.status, AuthStatus.checkingSession);
        expect(auth.user, isNull);
        expect(auth.canEnterGame, isFalse);
        expect(tester.state(current), same(before));
        final task = auth.restoreSession();
        if (outcome == 'rejected session') {
          reading.completeError(
            const AuthApiException(
              AuthApiErrorKind.unauthenticated,
              statusCode: 401,
            ),
          );
        } else {
          reading.complete(
            outcome == 'same identity'
                ? _me()
                : _me(userId: 'c21ad4be-b54e-4ecb-9c99-62dbdcedc677'),
          );
        }
        await task;
        if (outcome == 'rejected session') {
          // Welcome loops its animation; wait only until the old routes close.
          for (
            var frame = 0;
            frame < 20 && current.evaluate().isNotEmpty;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        } else {
          await tester.pumpAndSettle();
        }
        if (outcome == 'same identity') {
          expect(tester.state(current), same(before));
        } else {
          expect(current, findsNothing);
          expect(find.byType(CharacterProfileScreen), findsNothing);
          expect(
            outcome == 'rejected session'
                ? find.byType(WelcomeScreen)
                : find.text('Mở hồ sơ'),
            findsOneWidget,
          );
        }
      },
    );
  }

  Future<AuthLichSu> moHoSo(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthLichSu();
    final game = GoldRushGame(auth: auth);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      game.danhSachVatPham.dispose();
      game.capHoSoDaDongBo.dispose();
      game.phienVi?.dispose();
      auth.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CharacterProfileScreen(game: game),
                  ),
                );
              },
              child: const Text('Mở hồ sơ'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Mở hồ sơ'));
    await tester.pumpAndSettle();
    return auth;
  }

  for (final screen in ['Hồ sơ', 'Lịch sử màn chơi', 'VŨ KHÍ', 'NHÂN VẬT']) {
    testWidgets('Passive session check preserves $screen and its State', (
      tester,
    ) async {
      final auth = await moHoSo(tester);
      if (screen != 'Hồ sơ') {
        await tester.tap(find.text(screen));
        await tester.pumpAndSettle();
      }
      final current = screen == 'Hồ sơ'
          ? find.byType(CharacterProfileScreen)
          : screen == 'Lịch sử màn chơi'
          ? find.byType(ManHinhLichSuManChoi)
          : find.byType(ManHinhKhoDo);
      final before = tester.state(current);
      // AuthController clears identity and temporarily denies access during /me.
      auth.allowed = false;
      auth.phase = AuthStatus.checkingSession;
      auth.thayDoi();
      await tester.pumpAndSettle();
      expect(current, findsOneWidget);
      expect(tester.state(current), same(before));
      auth.allowed = true;
      auth.phase = AuthStatus.authenticated;
      auth.thayDoi();
      await tester.pumpAndSettle();
      expect(tester.state(current), same(before));
    });
  }

  for (final failure in [
    AuthStatus.unauthenticated,
    AuthStatus.error,
    AuthStatus.loggingOut,
  ]) {
    testWidgets(
      'Actual session loss $failure still closes Profile and child routes',
      (tester) async {
        final auth = await moHoSo(tester);
        await tester.tap(find.text('VŨ KHÍ'));
        await tester.pumpAndSettle();
        auth.allowed = false;
        auth.phase = failure;
        auth.thayDoi();
        await tester.pumpAndSettle();
        expect(find.byType(CharacterProfileScreen), findsNothing);
        expect(find.byType(ManHinhKhoDo), findsNothing);
        expect(find.text('Mở hồ sơ'), findsOneWidget);
      },
    );
  }

  for (final changed in ['wallet', 'chain']) {
    testWidgets(
      'Successful recheck for another $changed closes the old route stack',
      (tester) async {
        final auth = await moHoSo(tester);
        await tester.tap(find.text('VŨ KHÍ'));
        await tester.pumpAndSettle();
        auth.allowed = false;
        auth.phase = AuthStatus.checkingSession;
        auth.thayDoi();
        await tester.pumpAndSettle();
        expect(find.byType(ManHinhKhoDo), findsOneWidget);
        if (changed == 'wallet') {
          auth.wallet = '0x${'b' * 40}';
        } else {
          auth.chain = 11155111;
        }
        auth.allowed = true;
        auth.phase = AuthStatus.authenticated;
        auth.thayDoi();
        await tester.pumpAndSettle();
        expect(find.byType(CharacterProfileScreen), findsNothing);
        expect(find.byType(ManHinhKhoDo), findsNothing);
        expect(find.text('Mở hồ sơ'), findsOneWidget);
      },
    );
  }
}
