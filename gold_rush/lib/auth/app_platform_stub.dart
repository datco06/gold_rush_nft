/// Native has no wallet login; protected content must remain inaccessible.
library;

import '../blockchain/vi.dart';
import 'metamask_siwe_stub.dart';

export 'metamask_siwe_stub.dart' show MetamaskSiweWeb;

({Vi vi, void Function() dispose}) createGameWallet(MetamaskSiweWeb wallet) =>
    throw UnsupportedError('Đăng nhập MetaMask yêu cầu trình duyệt Web.');
