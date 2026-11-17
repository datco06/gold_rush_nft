/// Native has no wallet login; protected content must remain inaccessible.
library;

import '../blockchain/vi.dart';
import '../blockchain/vi_appkit.dart' as transactions;

import 'package:flutter/widgets.dart';

import 'metamask_siwe_native.dart';

export 'metamask_siwe_native.dart' show MetamaskSiweWeb;

MetamaskSiweWeb createWallet({
  required BuildContext context,
  required String projectId,
}) => MetamaskSiweWeb(context: context, projectId: projectId);

({Vi vi, void Function() dispose}) createGameWallet(MetamaskSiweWeb wallet) =>
    transactions.taoViTuAppKit(wallet);
