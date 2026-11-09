/// Composition only: Auth and transactions share the selected MetaMask object.
library;

import '../blockchain/vi.dart';
import '../blockchain/vi_web.dart' as transactions;
import 'metamask_siwe_web.dart';

export 'metamask_siwe_web.dart' show MetamaskSiweWeb;

({Vi vi, void Function() dispose}) createGameWallet(MetamaskSiweWeb wallet) {
  final provider = wallet.selectedProvider;
  if (provider == null) throw StateError('Chưa xác minh ví MetaMask.');
  return transactions.taoViTuProvider(provider);
}
