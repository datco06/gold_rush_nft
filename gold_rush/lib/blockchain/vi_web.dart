import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'loi_hop_dong.dart';
import 'vi.dart';

// ---------------------------------------------------------------------------
// Khai báo phía JavaScript
// ---------------------------------------------------------------------------

/// `window.ethereum` — cách cũ: ví nào cài sau cùng sẽ "chiếm" biến này. Chỉ dùng khi không có EIP-6963.
@JS('ethereum')
external _NhaCungCap? get _windowEthereum;

/// Nhà cung cấp EIP-1193 (MetaMask và các ví khác).
extension type _NhaCungCap._(JSObject _) implements JSObject {
  external _Hua request(_YeuCau yeuCau);

  @JS('on')
  external void dangKy(String suKien, JSFunction xuLy);
}

/// Promise của JS, khai báo kèm `then` để tự xử lý cả hai nhánh — không phải bắt ngoại lệ rồi ép
/// kiểu Dart ↔ JS (cách đó cho kết quả khác nhau giữa dart2js và dart2wasm).
extension type _Hua._(JSObject _) implements JSObject {
  external void then(JSFunction khiXong, JSFunction khiLoi);
}

extension type _YeuCau._(JSObject _) implements JSObject {
  external factory _YeuCau({String method, JSArray<JSAny?> params});
}

/// Lỗi EIP-1193: `code`, `message`, `data` (dữ liệu revert nằm đâu đó trong `data`).
extension type _LoiJs._(JSObject _) implements JSObject {
  external JSAny? get code;
  external JSAny? get message;
  external JSAny? get data;
}

// ---- EIP-6963: liệt kê MỌI ví trong trình duyệt, chọn đúng MetaMask ----
@JS('Event')
extension type _SuKienDom._(JSObject _) implements JSObject {
  external factory _SuKienDom(String type);
}

extension type _ThongBaoVi._(JSObject _) implements JSObject {
  external _ChiTietVi? get detail;
}

extension type _ChiTietVi._(JSObject _) implements JSObject {
  external _ThongTinVi get info;
  external _NhaCungCap get provider;
}

extension type _ThongTinVi._(JSObject _) implements JSObject {
  external JSAny? get name;
  external JSAny? get rdns;
}

// ---------------------------------------------------------------------------

String _chuoi(JSAny? x) {
  final d = x.dartify();
  return d is String ? d : '';
}

BigInt _hex(Object? v) {
  if (v is! String || v.length < 3) return BigInt.zero;
  return BigInt.parse(v.substring(2), radix: 16);
}

String _hexCua(BigInt n) => '0x${n.toRadixString(16)}';

class _ViWeb implements Vi {
  _ViWeb() {
    _timCacVi();
  }

  final List<(String ten, String rdns, _NhaCungCap nhaCungCap)> _cacVi = [];
  final StreamController<SuKienVi> _suKien = StreamController.broadcast();
  _NhaCungCap? _daChon;
  String _ten = 'MetaMask';
  bool _daNghe = false;

  /// EIP-6963: đăng ký nghe "announceProvider" rồi phát "requestProvider" — mỗi ví tự giới thiệu.
  void _timCacVi() {
    try {
      globalContext.callMethod(
        'addEventListener'.toJS,
        'eip6963:announceProvider'.toJS,
        ((JSObject e) {
          final ct = _ThongBaoVi._(e).detail;
          if (ct == null) return;
          _cacVi.add((_chuoi(ct.info.name), _chuoi(ct.info.rdns), ct.provider));
        }).toJS,
      );
      globalContext.callMethod('dispatchEvent'.toJS, _SuKienDom('eip6963:requestProvider'));
    } catch (_) {
      // Trình duyệt quá cũ: còn window.ethereum.
    }
  }

  /// Ưu tiên MetaMask (rdns "io.metamask…"), rồi ví EIP-6963 đầu tiên, rồi `window.ethereum`.
  _NhaCungCap? get _nhaCungCap {
    var p = _daChon;
    if (p != null) return p;
    for (final (ten, rdns, ncc) in _cacVi) {
      if (rdns.startsWith('io.metamask')) {
        _ten = ten.isEmpty ? 'MetaMask' : ten;
        p = ncc;
        break;
      }
    }
    if (p == null && _cacVi.isNotEmpty) {
      _ten = _cacVi.first.$1;
      p = _cacVi.first.$3;
    }
    p ??= _windowEthereum;
    if (p != null) {
      _daChon = p;
      _ngheSuKien(p);
    }
    return p;
  }

  void _ngheSuKien(_NhaCungCap p) {
    if (_daNghe) return;
    _daNghe = true;
    try {
      p.dangKy(
        'accountsChanged',
        ((JSAny? ds) {
          final l = ds.dartify();
          _suKien.add(DoiTaiKhoan(l is List ? [for (final x in l) '$x'] : const []));
        }).toJS,
      );
      p.dangKy(
        'chainChanged',
        ((JSAny? id) {
          final h = id.dartify();
          if (h is String) _suKien.add(DoiMang(_hex(h).toInt()));
        }).toJS,
      );
    } catch (_) {
      // Ví không hỗ trợ sự kiện: app vẫn kiểm tra lại tài khoản/mạng trước mỗi giao dịch.
    }
  }

  @override
  bool get coSan => _nhaCungCap != null;

  @override
  String get ten {
    _nhaCungCap;
    return _ten;
  }

  @override
  Stream<SuKienVi> get suKien {
    _nhaCungCap;
    return _suKien.stream;
  }

  /// Gửi một yêu cầu EIP-1193; kết quả đã chuyển sang kiểu Dart (String, List, Map…).
  Future<Object?> _hoi(String phuongThuc, [List<Object?> thamSo = const []]) {
    final eth = _nhaCungCap;
    if (eth == null) {
      return Future.error(const LoiVi(
          'Chưa cài MetaMask. Cài tiện ích MetaMask cho trình duyệt rồi tải lại trang.'));
    }
    final xong = Completer<Object?>();
    try {
      eth
          .request(_YeuCau(
            method: phuongThuc,
            params: thamSo.jsify()! as JSArray<JSAny?>,
          ))
          .then(
            ((JSAny? kq) => xong.complete(kq.dartify())).toJS,
            ((JSAny? loi) => xong.completeError(_dichLoi(loi))).toJS,
          );
    } catch (e) {
      xong.completeError(LoiVi('Không gọi được ví: $e'));
    }
    return xong.future;
  }

  LoiVi _dichLoi(JSAny? goc) {
    if (goc != null && goc.isA<JSObject>()) {
      final l = _LoiJs._(goc as JSObject);
      final ma = l.code.dartify();
      return taoLoiVi(
        ma: ma is num ? ma.toInt() : null,
        thongDiep: _chuoi(l.message),
        duLieu: l.data.dartify(),
      );
    }
    return taoLoiVi(thongDiep: '${goc.dartify()}');
  }

  @override
  Future<String> ketNoi() async {
    final ds = await _hoi('eth_requestAccounts');
    if (ds is! List || ds.isEmpty) throw const LoiVi('Ví không trả về tài khoản nào.');
    return '${ds.first}';
  }

  @override
  Future<List<String>> taiKhoan() async {
    final ds = await _hoi('eth_accounts');
    return ds is List ? [for (final x in ds) '$x'] : const [];
  }

  @override
  Future<int> chainId() async => _hex(await _hoi('eth_chainId')).toInt();

  @override
  Future<void> chuyenMang(int chainId, {String? tenMang, String? rpcUrl}) async {
    final hex = '0x${chainId.toRadixString(16)}';
    try {
      await _hoi('wallet_switchEthereumChain', [
        {'chainId': hex},
      ]);
    } on LoiVi catch (e) {
      // 4902 chuẩn; một số bản MetaMask di động trả -32603 kèm "Unrecognized chain".
      final chuaCo = e.loai == LoaiLoiVi.chuaCoMang ||
          (e.thongDiepGoc ?? '').toLowerCase().contains('unrecognized chain');
      if (!chuaCo || rpcUrl == null) rethrow;
      await _hoi('wallet_addEthereumChain', [
        {
          'chainId': hex,
          'chainName': tenMang ?? 'Mạng $chainId',
          'rpcUrls': [rpcUrl],
          'nativeCurrency': {'name': 'ETH', 'symbol': 'ETH', 'decimals': 18},
        },
      ]);
    }
  }

  @override
  Future<String> goi({required String toi, required String duLieu, String? tu}) async {
    final kq = await _hoi('eth_call', [
      {if (tu != null) 'from': tu, 'to': toi, 'data': duLieu},
      'latest',
    ]);
    return kq is String ? kq : '0x';
  }

  @override
  Future<String> maHopDong(String diaChi) async {
    final kq = await _hoi('eth_getCode', [diaChi, 'latest']);
    return kq is String ? kq : '0x';
  }

  @override
  Future<BigInt> uocLuongGas({required String tu, required String toi, required String duLieu}) async =>
      _hex(await _hoi('eth_estimateGas', [
        {'from': tu, 'to': toi, 'data': duLieu},
      ]));

  @override
  Future<BigInt> giaGas() async => _hex(await _hoi('eth_gasPrice'));

  @override
  Future<BigInt> soDu(String diaChi) async => _hex(await _hoi('eth_getBalance', [diaChi, 'latest']));

  @override
  Future<String> guiGiaoDich({
    required String tu,
    required String toi,
    required String duLieu,
    BigInt? gas,
  }) async {
    // Đặt giới hạn gas (đã cộng biên an toàn); giá gas để MetaMask tự đề xuất (EIP-1559).
    final kq = await _hoi('eth_sendTransaction', [
      {'from': tu, 'to': toi, 'data': duLieu, if (gas != null) 'gas': _hexCua(gas)},
    ]);
    if (kq is! String) throw const LoiVi('Ví không trả về mã giao dịch.');
    return kq;
  }

  @override
  Future<BienLai?> bienLai(String maGiaoDich) async {
    final kq = await _hoi('eth_getTransactionReceipt', [maGiaoDich]);
    if (kq is! Map) return null;
    return BienLai(
      thanhCong: kq['status'] == '0x1',
      soKhoi: kq['blockNumber'] is String ? _hex(kq['blockNumber']).toInt() : null,
    );
  }
}

Vi taoVi() => _ViWeb();
