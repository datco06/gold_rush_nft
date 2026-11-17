/// Vi implementation backed by the shared native Reown/WalletConnect adapter.
///
/// Gameplay and transaction orchestration keep using [Vi]; only this boundary
/// knows that Android transport is WalletConnect instead of browser EIP-1193.
library;

import 'dart:async';

import '../auth/metamask_siwe_contract.dart';
import '../auth/metamask_siwe_native.dart';
import 'loi_hop_dong.dart';
import 'vi.dart';

BigInt _hex(Object? value) {
  if (value is! String || !value.startsWith('0x') || value.length < 3) {
    throw const FormatException();
  }
  return BigInt.parse(value.substring(2), radix: 16);
}

String _hexOf(BigInt value) => '0x${value.toRadixString(16)}';

class ViAppKit implements Vi {
  ViAppKit(this.wallet);

  final MetamaskSiweWeb wallet;

  @override
  bool get coSan => wallet.isConfigured;

  @override
  String get ten => 'MetaMask';

  @override
  Stream<SuKienVi> get suKien => wallet.events.map((event) {
    return switch (event.type) {
      MetamaskSiweEventType.accountsChanged => DoiTaiKhoan(event.accounts),
      MetamaskSiweEventType.chainChanged => DoiMang(event.chainId!.toInt()),
      MetamaskSiweEventType.disconnected => const DoiTaiKhoan([]),
      MetamaskSiweEventType.invalidProviderData => const DoiTaiKhoan([]),
    };
  });

  @override
  Future<String> ketNoi() async {
    try {
      return (await wallet.connect()).address;
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<List<String>> taiKhoan() async {
    try {
      return await wallet.getAccounts();
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<int> chainId() async {
    try {
      return (await wallet.getChainId()).toInt();
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> chuyenMang(
    int chainId, {
    String? tenMang,
    String? rpcUrl,
  }) async {
    final localRpc = const String.fromEnvironment(
      'GOLD_RUSH_LOCAL_RPC_URL',
      defaultValue: 'http://10.0.2.2:8545',
    );
    final sepoliaRpc = const String.fromEnvironment(
      'GOLD_RUSH_SEPOLIA_RPC_URL',
      defaultValue: 'https://rpc.sepolia.org',
    );
    final requestedRpc = rpcUrl == null || rpcUrl.contains('127.0.0.1')
        ? (chainId == 11155111 ? sepoliaRpc : localRpc)
        : rpcUrl;
    try {
      await wallet.switchChain(
        chainId,
        name: tenMang ?? (chainId == 11155111 ? 'Sepolia' : 'Hardhat cục bộ'),
        rpcUrl: requestedRpc,
      );
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<Object?> _rpc(String method, [List<Object?> params = const []]) async {
    try {
      return await wallet.requestRpc(method, params);
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<String> goi({
    required String toi,
    required String duLieu,
    String? tu,
  }) async {
    final result = await _rpc('eth_call', [
      <String, Object?>{'to': toi, 'data': duLieu, if (tu != null) 'from': tu},
      'latest',
    ]);
    if (result is! String) {
      throw const LoiVi('Ví trả kết quả eth_call không hợp lệ.');
    }
    return result;
  }

  @override
  Future<String> maHopDong(String diaChi) async {
    final result = await _rpc('eth_getCode', [diaChi, 'latest']);
    return result is String ? result : '0x';
  }

  @override
  Future<BigInt> uocLuongGas({
    required String tu,
    required String toi,
    required String duLieu,
  }) async => _hex(
    await _rpc('eth_estimateGas', [
      {'from': tu, 'to': toi, 'data': duLieu},
    ]),
  );

  @override
  Future<BigInt> giaGas() async => _hex(await _rpc('eth_gasPrice'));

  @override
  Future<BigInt> soDu(String diaChi) async =>
      _hex(await _rpc('eth_getBalance', [diaChi, 'latest']));

  @override
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  }) async {
    final result = await _rpc('eth_sendTransaction', [
      {
        'from': tu,
        'to': toi,
        'data': duLieu,
        if (gas != null) 'gas': _hexOf(gas),
      },
    ]);
    if (result is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(result)) {
      throw const LoiVi('Ví không trả về mã giao dịch hợp lệ.');
    }
    return result;
  }

  @override
  Future<String> kyThongDiep({
    required String diaChi,
    required String thongDiep,
  }) async {
    try {
      return await wallet.signSiweMessage(address: diaChi, message: thongDiep);
    } catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    final result = await _rpc('eth_getTransactionReceipt', [maGiaoDich]);
    if (result == null) return null;
    if (result is! Map) throw const LoiVi('Ví trả biên lai không hợp lệ.');
    final status = result['status'];
    final block = result['blockNumber'];
    return BienLai(
      thanhCong: status == '0x1',
      soKhoi: block is String ? _hex(block).toInt() : null,
    );
  }

  LoiVi _mapError(Object error) {
    if (error is LoiVi) return error;
    if (error is MetamaskSiweException) {
      final kind = switch (error.code) {
        MetamaskSiweErrorCode.userRejected => LoaiLoiVi.tuChoi,
        MetamaskSiweErrorCode.requestPending => LoaiLoiVi.dangCho,
        MetamaskSiweErrorCode.chainChanged => LoaiLoiVi.doiTaiKhoan,
        MetamaskSiweErrorCode.accountChanged => LoaiLoiVi.doiTaiKhoan,
        _ => LoaiLoiVi.khac,
      };
      return LoiVi(error.message, ma: error.rpcCode, loai: kind);
    }
    return LoiVi(
      dichLoiHopDong(thongDiep: error.toString()) ?? 'Không giao tiếp được MetaMask Mobile. Hãy mở lại ứng dụng ví và thử lại.',
    );
  }
}

({Vi vi, void Function() dispose}) taoViTuAppKit(MetamaskSiweWeb wallet) {
  final vi = ViAppKit(wallet);
  var disposed = false;
  return (
    vi: vi,
    dispose: () {
      if (disposed) return;
      disposed = true;
      wallet.dispose();
    },
  );
}
