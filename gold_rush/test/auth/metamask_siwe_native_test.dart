import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/metamask_siwe_contract.dart';
import 'package:gold_rush/auth/metamask_siwe_native.dart';
import 'package:gold_rush/blockchain/vi_appkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reown_appkit/reown_appkit.dart';

const _mainnet = 'eip155:1';
const _sepolia = 'eip155:11155111';
const _address = '0x1111111111111111111111111111111111111111';
const _metadata = ConnectionMetadata(
  publicKey: 'test-key',
  metadata: PairingMetadata(name: 'Test', description: ''),
);

void main() {
  testWidgets('reads inventory and contract code without opening MetaMask', (
    tester,
  ) async {
    final modal = _Modal()..selectedChain = _network(_sepolia);
    final vi = ViAppKit(await _wallet(tester, modal));
    final methods = <String>[];

    await http.runWithClient(
      () async {
        expect(await vi.maHopDong(_address), '0x1234');
        expect(await vi.goi(toi: _address, duLieu: '0x4e1273f4'), '0x00');
      },
      () => MockClient((request) async {
        expect(request.url, Uri.parse(nativeSepoliaRpcUrl));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String;
        methods.add(method);
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': method == 'eth_getCode' ? '0x1234' : '0x00',
          }),
          200,
        );
      }),
    );

    expect(methods, ['eth_getCode', 'eth_call']);
    expect(modal.requestChain, isNull);
  });

  testWidgets('restores the selected approved chain for Android RPCs', (
    tester,
  ) async {
    final modal = _Modal()..selectedChain = _network(_sepolia);
    final wallet = await _wallet(tester, modal);

    expect((await wallet.connect()).chainId, BigInt.from(11155111));
    await wallet.requestRpc('eth_sendTransaction');
    expect(modal.requestChain, _sepolia);
  });

  testWidgets('honors a wallet chain change using its payload and topic', (
    tester,
  ) async {
    final modal = _Modal();
    final wallet = await _wallet(tester, modal);
    await wallet.connect();

    modal.emitChain('0xaa36a7', topic: 'old-session');
    expect(await wallet.getChainId(), BigInt.one);

    modal.emitChain('0xaa36a7');
    modal.onModalNetworkChange.broadcast(ModalNetworkChange(chainId: _mainnet));
    expect(await wallet.getChainId(), BigInt.from(11155111));
    await wallet.requestRpc('eth_call');
    expect(modal.requestChain, _sepolia);
  });

  testWidgets('keeps confirmed switch even when session lists mainnet first', (
    tester,
  ) async {
    final modal = _Modal();
    final wallet = await _wallet(tester, modal);
    await wallet.connect();
    modal.emitChain(1);

    await wallet.switchChain(11155111);
    expect(await wallet.getChainId(), BigInt.from(11155111));
    await wallet.signSiweMessage(
      address: _address,
      message: 'Gold Rush login',
      expectedChainId: BigInt.from(11155111),
    );
    expect(modal.requestChain, _sepolia);

    modal.duringRequest = () => modal.emitChain(1);
    await expectLater(
      wallet.signSiweMessage(address: _address, message: 'Gold Rush login'),
      throwsA(
        isA<MetamaskSiweException>().having(
          (error) => error.code,
          'code',
          MetamaskSiweErrorCode.chainChanged,
        ),
      ),
    );
  });

  testWidgets('a rejected switch does not ask to add the chain', (
    tester,
  ) async {
    final modal = _Modal()..rejectSwitch = true;
    final wallet = await _wallet(tester, modal);

    await expectLater(
      wallet.switchChain(11155111),
      throwsA(
        isA<MetamaskSiweException>().having(
          (error) => error.code,
          'code',
          MetamaskSiweErrorCode.userRejected,
        ),
      ),
    );
    expect(modal.addRequests, 0);
    expect(await wallet.getChainId(), BigInt.one);
  });
}

Future<MetamaskSiweWeb> _wallet(WidgetTester tester, _Modal modal) async {
  await tester.pumpWidget(const SizedBox());
  final wallet = MetamaskSiweWeb(
    context: tester.element(find.byType(SizedBox)),
    projectId: 'test-project',
    appKit: modal,
  );
  addTearDown(wallet.dispose);
  return wallet;
}

ReownAppKitModalNetworkInfo _network(String chainId) =>
    ReownAppKitModalNetworkInfo(
      name: chainId,
      chainId: chainId,
      currency: 'ETH',
      rpcUrl: '',
      explorerUrl: '',
    );

class _Modal implements ReownAppKitModal {
  @override
  final session = ReownAppKitModalSession(
    sessionData: SessionData(
      topic: 'current-session',
      pairingTopic: 'pairing',
      relay: Relay('irn'),
      expiry: 2000000000,
      acknowledged: true,
      controller: 'test-key',
      namespaces: const {
        'eip155': Namespace(
          accounts: ['$_mainnet:$_address', '$_sepolia:$_address'],
          methods: ['personal_sign', 'eth_sendTransaction', 'eth_call'],
          events: ['chainChanged'],
        ),
      },
      self: _metadata,
      peer: _metadata,
    ),
  );
  @override
  ReownAppKitModalNetworkInfo? selectedChain = _network(_mainnet);
  @override
  bool get isConnected => true;
  @override
  final onModalConnect = Event<ModalConnect>();
  @override
  final onModalUpdate = Event<ModalConnect>();
  @override
  final onModalNetworkChange = Event<ModalNetworkChange>();
  @override
  final onModalDisconnect = Event<ModalDisconnect>();
  @override
  final onModalError = Event<ModalError>();
  @override
  final onSessionEventEvent = Event<SessionEvent>();

  String? requestChain;
  void Function()? duringRequest;
  bool rejectSwitch = false;
  int addRequests = 0;

  void emitChain(Object chain, {String topic = 'current-session'}) {
    onSessionEventEvent.broadcast(
      SessionEvent(1, topic, 'chainChanged', _mainnet, chain),
    );
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> requestSwitchToChain(ReownAppKitModalNetworkInfo chain) async {
    if (rejectSwitch) throw const JsonRpcError(code: 4001);
    selectedChain = chain;
    onModalNetworkChange.broadcast(ModalNetworkChange(chainId: chain.chainId));
  }

  @override
  Future<void> requestAddChain(ReownAppKitModalNetworkInfo chain) async {
    addRequests++;
  }

  @override
  Future<dynamic> request({
    required String? topic,
    required String chainId,
    required SessionRequestParams request,
    String? switchToChainId,
  }) async {
    requestChain = chainId;
    duringRequest?.call();
    return '0x${'a' * 130}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
