/// Character registration UI. The parent owns AuthController/navigation.
/// This file never connects/signs a wallet, calls HTTP, reads cookies or creates
/// a user. Unicode NFC and final name validation belong to the backend.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cau_hinh.dart';
import '../auth_controller.dart';
import 'welcome_screen.dart' show WelcomeCallback;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.controller,
    this.onAuthenticated,
    this.onBack,
    this.clock,
    this.timerFactory,
  });

  final AuthController controller;
  final WelcomeCallback? onAuthenticated;
  final WelcomeCallback? onBack;

  /// Tests may inject the same clock/scheduler as AuthController. These only
  /// lock an expired form locally; the server still enforces grant expiry.
  final DateTime Function()? clock;
  final AuthTimerFactory? timerFactory;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  Timer? _expiryTimer;
  String? _grantWallet;
  String _observedName = '';
  DateTime? _grantExpiry;
  String? _localError;
  String? _rejectedName;
  String? _navigationError;
  String? _successSession;
  String? _forwardedSession;
  int _generation = 0;
  bool _submitting = false;
  bool _navigating = false;
  bool _expired = false;
  bool _clearingName = false;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();
  bool get _composing =>
      _name.value.composing.isValid && !_name.value.composing.isCollapsed;
  bool get _hasGrant =>
      !_expired &&
      widget.controller.status == AuthStatus.registrationRequired &&
      !widget.controller.logoutPending &&
      _grantWallet != null &&
      _grantWallet == widget.controller.walletAddress &&
      _grantExpiry == widget.controller.expiresAt &&
      _grantExpiry!.isAfter(_now());
  bool get _busy => _submitting || _navigating || widget.controller.isLoading;

  @override
  void initState() {
    super.initState();
    _name.addListener(_nameChanged);
    widget.controller.addListener(_authChanged);
    _syncGrant();
  }

  @override
  void didUpdateWidget(covariant RegisterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_authChanged);
      widget.controller.addListener(_authChanged);
      _generation++;
      _submitting = false;
      _navigating = false;
      _successSession = null;
      _forwardedSession = null;
      _discardGrant();
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.clock != widget.clock ||
        oldWidget.timerFactory != widget.timerFactory) {
      _syncGrant();
    }
  }

  void _nameChanged() {
    if (!mounted || _clearingName) return;
    // Observe text/composition without rewriting TextEditingValue. Neither NFC
    // nor ASCII-space folding is performed here, including during active IME.
    final textChanged = _observedName != _name.text;
    _observedName = _name.text;
    setState(() {
      // Focus/selection changes also notify TextEditingController. They must
      // not erase a validation error before the player changes the name.
      if (textChanged) _localError = null;
    });
  }

  void _discardGrant() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_grantWallet != null) _generation++;
    _grantWallet = null;
    _grantExpiry = null;
    _localError = null;
    _rejectedName = null;
    _successSession = null;
    _clearingName = true;
    _name.clear();
    _observedName = '';
    _clearingName = false;
  }

  void _syncGrant() {
    final controller = widget.controller;
    final registration = controller.status == AuthStatus.registrationRequired;
    if (registration &&
        !controller.logoutPending &&
        controller.walletAddress != null &&
        controller.expiresAt != null) {
      if (_grantWallet != controller.walletAddress ||
          _grantExpiry != controller.expiresAt) {
        _discardGrant();
        _generation++;
        _grantWallet = controller.walletAddress;
        _grantExpiry = controller.expiresAt;
        _expired = false;
      }
      _scheduleExpiry();
    } else if (controller.status == AuthStatus.registering &&
        controller.walletAddress == _grantWallet &&
        !controller.logoutPending) {
      // Once register is in flight, its server outcome decides success. Do not
      // reject a valid rotated session just because the old grant expires
      // while the HTTP response is travelling back to the browser.
      _expiryTimer?.cancel();
    } else if (controller.canEnterGame) {
      _expiryTimer?.cancel();
    } else {
      _discardGrant();
    }
  }

  void _authChanged() {
    if (!mounted) return;
    _syncGrant();
    setState(() {});
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final remaining = _grantExpiry!.difference(_now());
    if (remaining <= Duration.zero) {
      _expired = true;
      return;
    }
    final generation = _generation;
    _expiryTimer = (widget.timerFactory ?? Timer.new)(remaining, () {
      if (!mounted || generation != _generation) return;
      if (_grantExpiry!.isAfter(_now())) {
        _scheduleExpiry();
      } else {
        setState(() => _expired = true);
      }
    });
  }

  String _sessionKey(AuthController controller) =>
      '${identityHashCode(controller)}:${controller.user?.id}:'
      '${controller.expiresAt?.microsecondsSinceEpoch}';

  Future<void> _submit() async {
    if (_busy || !_hasGrant) return;
    if (_composing) {
      setState(
        () => _localError = 'Hãy hoàn tất dấu tiếng Việt trước khi gửi tên.',
      );
      return;
    }
    final analysis = _inspectName(_name.text);
    if (analysis.error != null) {
      setState(() => _localError = analysis.error);
      _focus.requestFocus();
      return;
    }
    final controller = widget.controller;
    final wallet = _grantWallet!;
    final generation = _generation;
    final rawName = _name.text;
    setState(() {
      _submitting = true;
      _localError = null;
      _navigationError = null;
      _rejectedName = null;
    });
    _expiryTimer?.cancel();
    _focus.unfocus();
    try {
      // Send the ORIGINAL input; only the backend owns canonical username,
      // casefold key, uniqueness and persisted profile. Never send a wallet ID.
      await controller.register(rawName);
      if (!mounted ||
          generation != _generation ||
          controller != widget.controller) {
        return;
      }
      if (controller.canEnterGame && controller.user!.walletAddress == wallet) {
        final session = _sessionKey(controller);
        setState(() => _successSession = session);
        await _forwardSuccess(controller, session);
      } else if (_hasGrant) {
        setState(() => _rejectedName = rawName);
        _focus.requestFocus();
        _scheduleExpiry();
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _navigationError = 'Chưa thể hoàn tất thao tác. Hãy kiểm tra trạng thái phiên trước khi thử lại.',
        );
        if (_hasGrant) _scheduleExpiry();
      }
    } finally {
      // A wallet/controller replacement invalidates callbacks but should not
      // leave this widget's busy flag stuck if it is still displaying that op.
      if (mounted && controller == widget.controller) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _forwardSuccess(
    AuthController controller,
    String session,
  ) async {
    final callback = widget.onAuthenticated;
    if (callback == null ||
        !controller.canEnterGame ||
        session != _sessionKey(controller) ||
        _forwardedSession == session) {
      return;
    }
    // Navigation is triggered by a completed submit, never build/listener.
    _forwardedSession = session;
    try {
      await callback();
    } catch (_) {
      if (mounted &&
          controller == widget.controller &&
          controller.canEnterGame) {
        setState(() {
          _forwardedSession = null;
          _navigationError = 'Hồ sơ đã sẵn sàng nhưng chưa thể mở hành trình. Hãy thử tiếp tục lại.';
        });
      }
    }
  }

  Future<void> _continue() async {
    if (_busy || !widget.controller.canEnterGame) return;
    final controller = widget.controller;
    setState(() => _navigating = true);
    try {
      await _forwardSuccess(controller, _sessionKey(controller));
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _back() async {
    if (_busy || widget.onBack == null) return;
    setState(() => _navigating = true);
    try {
      await widget.onBack!();
    } catch (_) {
      if (mounted) {
        setState(() => _navigationError = 'Chưa thể quay lại. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final valid = controller.canEnterGame;
    final success = valid && _successSession == _sessionKey(controller);
    final showForm =
        _hasGrant ||
        controller.status == AuthStatus.registering &&
            _grantWallet != null &&
            controller.walletAddress == _grantWallet;
    final backendNameError =
        _rejectedName == _name.text &&
        {'USERNAME_TAKEN', 'USERNAME_INVALID'}.contains(controller.errorCode);
    final fieldError =
        _localError ?? (backendNameError ? controller.errorMessage : null);
    final generalError = backendNameError
        ? _navigationError
        : {'USERNAME_TAKEN', 'USERNAME_INVALID'}.contains(controller.errorCode)
        ? _navigationError
        : controller.errorMessage ?? _navigationError;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _RegisterColors.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _RegisterBackdrop()),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inset = constraints.maxWidth < 440 ? 16.0 : 28.0;
                return SingleChildScrollView(
                  key: const ValueKey('register-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(inset),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - inset * 2),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 510),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          builder: (context, value, child) =>
                              Opacity(opacity: value, child: child),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'GOLD RUSH',
                                style: TextStyle(
                                  color: _RegisterColors.gold,
                                  fontSize: 23,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'MỘT CÁI TÊN · MỘT HÀNH TRÌNH',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _RegisterColors.muted,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 22),
                              _RegistrationBoard(
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    constraints.maxWidth < 440 ? 20 : 28,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _RegistrationPortrait(success: success),
                                      const SizedBox(height: 18),
                                      Semantics(
                                        header: true,
                                        child: Text(
                                          success
                                              ? 'HỒ SƠ ĐÃ ĐƯỢC TẠO!'
                                              : valid
                                              ? 'BẠN ĐÃ ĐĂNG NHẬP'
                                              : 'TẠO HỒ SƠ NHÀ THÁM HIỂM',
                                          key: const ValueKey('register-title'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: _RegisterColors.paper,
                                            fontSize: 25,
                                            fontWeight: FontWeight.w900,
                                            height: 1.25,
                                            letterSpacing: .4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (showForm) ...[
                                        const Text(
                                          'Ví MetaMask của bạn đã được xác minh!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _RegisterColors.sage,
                                            fontSize: 13,
                                            height: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        const Text(
                                          'Hãy chọn tên nhân vật để bắt đầu hành trình săn vàng.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _RegisterColors.muted,
                                            fontSize: 14,
                                            height: 1.55,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        TextField(
                                          key: const ValueKey(
                                            'register-username',
                                          ),
                                          controller: _name,
                                          focusNode: _focus,
                                          enabled: _hasGrant && !_busy,
                                          textInputAction: TextInputAction.done,
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          smartDashesType:
                                              SmartDashesType.disabled,
                                          smartQuotesType:
                                              SmartQuotesType.disabled,
                                          scrollPadding: const EdgeInsets.all(
                                            32,
                                          ),
                                          onEditingComplete: () {},
                                          onSubmitted: (_) =>
                                              unawaited(_submit()),
                                          style: const TextStyle(
                                            color: _RegisterColors.paper,
                                            fontSize: 17,
                                          ),
                                          cursorColor: _RegisterColors.gold,
                                          decoration: InputDecoration(
                                            labelText: 'TÊN NHÀ THÁM HIỂM',
                                            hintText: 'Nhập tên nhà thám hiểm',
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.always,
                                            labelStyle: const TextStyle(
                                              color: _RegisterColors.gold,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            hintStyle: const TextStyle(
                                              color: _RegisterColors.muted,
                                              fontSize: 14,
                                            ),
                                            filled: true,
                                            fillColor: const Color(0xFF152722),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 18,
                                                ),
                                            enabledBorder:
                                                const OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.zero,
                                                  borderSide: BorderSide(
                                                    color: Color(0xFF88734C),
                                                  ),
                                                ),
                                            focusedBorder:
                                                const OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.zero,
                                                  borderSide: BorderSide(
                                                    color: _RegisterColors.gold,
                                                    width: 2,
                                                  ),
                                                ),
                                            disabledBorder:
                                                const OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.zero,
                                                  borderSide: BorderSide(
                                                    color: Color(0xFF615442),
                                                  ),
                                                ),
                                            errorBorder:
                                                const OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.zero,
                                                  borderSide: BorderSide(
                                                    color: Color(0xFFDC9D83),
                                                  ),
                                                ),
                                            focusedErrorBorder:
                                                const OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.zero,
                                                  borderSide: BorderSide(
                                                    color: Color(0xFFDC9D83),
                                                    width: 2,
                                                  ),
                                                ),
                                            errorText: fieldError,
                                            errorMaxLines: 4,
                                            errorStyle: const TextStyle(
                                              color: Color(0xFFFFC9B8),
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _composing
                                              ? 'Đang ghép dấu tiếng Việt…'
                                              : '3–20 ký tự sau chuẩn hóa; máy chủ xác nhận.',
                                          key: const ValueKey(
                                            'register-name-count',
                                          ),
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(
                                            color: _RegisterColors.muted,
                                            fontSize: 11,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          '3–20 ký tự; dùng chữ có dấu, chữ số, khoảng trắng, _ hoặc -. '
                                          'Tên được chuẩn hóa khi tạo hồ sơ; máy chủ kiểm tra tên trùng.',
                                          style: TextStyle(
                                            color: _RegisterColors.muted,
                                            fontSize: 12,
                                            height: 1.6,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        _VerifiedWallet(
                                          address: controller.walletAddress!,
                                        ),
                                      ] else if (valid) ...[
                                        Text(
                                          controller.user!.username,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: _RegisterColors.gold,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Hồ sơ đã được máy chủ xác nhận. Hành trình săn vàng đang chờ bạn.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _RegisterColors.sage,
                                            fontSize: 14,
                                            height: 1.6,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        _VerifiedWallet(
                                          address:
                                              controller.user!.walletAddress,
                                        ),
                                      ] else ...[
                                        _RegistrationNotice(
                                          message: _expired
                                              ? 'Quyền tạo nhân vật đã hết hạn. Hãy quay lại để xác minh MetaMask.'
                                              : controller.isLoading
                                              ? 'Đang kiểm tra trạng thái xác thực. Vui lòng chờ.'
                                              : 'Cần xác minh lại MetaMask trước khi tạo hồ sơ. Hãy quay lại màn hình chào mừng.',
                                        ),
                                      ],
                                      if (generalError != null) ...[
                                        const SizedBox(height: 16),
                                        _RegistrationNotice(
                                          message: generalError,
                                          isError: true,
                                        ),
                                      ],
                                      const SizedBox(height: 22),
                                      if (showForm)
                                        // Keep pointer-down from dismissing
                                        // an active IME before _submit checks
                                        // its composing range.
                                        TextFieldTapRegion(
                                          child: _RegisterButton(
                                            label: 'BẮT ĐẦU HÀNH TRÌNH',
                                            busy: _busy,
                                            reducedMotion: reduced,
                                            onPressed: !_hasGrant || _busy
                                                ? null
                                                : () => unawaited(_submit()),
                                          ),
                                        )
                                      else if (valid)
                                        _RegisterButton(
                                          label: 'TIẾP TỤC HÀNH TRÌNH',
                                          busy: _navigating,
                                          reducedMotion: reduced,
                                          onPressed:
                                              _busy ||
                                                  widget.onAuthenticated ==
                                                      null ||
                                                  _forwardedSession ==
                                                      _sessionKey(controller)
                                              ? null
                                              : () => unawaited(_continue()),
                                        ),
                                      if (controller.status ==
                                              AuthStatus.registering ||
                                          _submitting && !valid) ...[
                                        const SizedBox(height: 12),
                                        Semantics(
                                          liveRegion: true,
                                          child: const Text(
                                            'Đang tạo hồ sơ nhà thám hiểm...',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _RegisterColors.paper,
                                              fontSize: 13,
                                              height: 1.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (widget.onBack != null ||
                                          !showForm && !valid) ...[
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                          key: const ValueKey('register-back'),
                                          onPressed:
                                              _busy || widget.onBack == null
                                              ? null
                                              : () => unawaited(_back()),
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                            size: 18,
                                          ),
                                          label: Text(
                                            showForm || valid
                                                ? 'QUAY LẠI'
                                                : 'QUAY LẠI XÁC MINH',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                _RegisterColors.paper,
                                            minimumSize: const Size.fromHeight(
                                              48,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFF88734C),
                                            ),
                                            shape: const BeveledRectangleBorder(
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 19),
                                      const Text(
                                        'Chỉ chọn tên nhân vật. Không cần mật khẩu hoặc khóa bí mật.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _RegisterColors.muted,
                                          fontSize: 11,
                                          height: 1.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _expiryTimer?.cancel();
    widget.controller.removeListener(_authChanged);
    _name.removeListener(_nameChanged);
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }
}

class _NameAnalysis {
  const _NameAnalysis({this.error});
  final String? error;
}

_NameAnalysis _inspectName(String raw) {
  if (raw.runes.take(257).length > 256) {
    return const _NameAnalysis(
      error: 'Tên nhập vào quá dài. Hãy dùng tối đa 256 ký tự trước chuẩn hóa.',
    );
  }
  // Pre-NFC checks mirror the current schemas.py policy. Unicode versions can
  // differ between Dart runtimes and Python; backend remains final.
  final forbidden = RegExp(r'[^\p{L}\p{M}\p{Nd} _-]', unicode: true);
  bool invisible(int point) =>
      point == 0x034f ||
      point >= 0x115f && point <= 0x1160 ||
      point >= 0x17b4 && point <= 0x17b5 ||
      point >= 0x180b && point <= 0x180f ||
      point == 0x3164 ||
      point >= 0xfe00 && point <= 0xfe0f ||
      point == 0xffa0 ||
      point >= 0xe0100 && point <= 0xe01ef ||
      point == 0x20e3;
  if (forbidden.hasMatch(raw) || raw.runes.any(invisible)) {
    return const _NameAnalysis(
      error: 'Tên không được chứa emoji, ký tự ẩn hoặc ký tự đặc biệt ngoài _ và -.',
    );
  }
  // Dart core has no equivalent of String.normalize('NFC'). Do not approximate
  // normalized length with runes or graphemes: NFC can compose or expand input.
  // Submit the original text and let the backend enforce 3–20 after NFC and
  // ASCII-space folding, as well as casefold-based name uniqueness.
  if (!RegExp(r'[\p{L}\p{Nd}]', unicode: true).hasMatch(raw)) {
    return const _NameAnalysis(
      error: 'Tên cần có ít nhất một chữ cái hoặc chữ số.',
    );
  }
  return const _NameAnalysis();
}

abstract final class _RegisterColors {
  static const gold = Color(0xFFF1CF7A);
  static const paper = Color(0xFFF5E3B5);
  static const muted = Color(0xFFC8BBA0);
  static const sage = Color(0xFFB7DFAC);
  static const night = Color(0xFF101B27);
}

class _RegistrationBoard extends StatelessWidget {
  const _RegistrationBoard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4A3022), Color(0xFF30231E), Color(0xFF201B1B)],
      ),
      shape: BeveledRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _RegisterColors.gold, width: 2),
      ),
      shadows: const [
        BoxShadow(color: Color(0x99071017), offset: Offset(0, 7)),
        BoxShadow(color: Color(0x66000000), blurRadius: 35),
      ],
    ),
    child: child,
  );
}

class _RegistrationPortrait extends StatelessWidget {
  const _RegistrationPortrait({required this.success});
  final bool success;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: ShapeDecoration(
          color: const Color(0xFF183A2A),
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _RegisterColors.gold),
          ),
          shadows: success
              ? const [BoxShadow(color: Color(0x55E3A008), blurRadius: 24)]
              : null,
        ),
        child: success
            ? const SizedBox.square(
                dimension: 48,
                child: Icon(
                  Icons.verified_outlined,
                  color: _RegisterColors.gold,
                  size: 42,
                ),
              )
            : SizedBox.square(
                dimension: 48,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 192,
                    maxWidth: 192,
                    minHeight: 192,
                    maxHeight: 192,
                    child: Image.asset(
                      'assets/images/george.png',
                      width: 192,
                      height: 192,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

class _VerifiedWallet extends StatelessWidget {
  const _VerifiedWallet({required this.address});
  final String address;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('register-verified-wallet'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF192C26),
      border: Border.all(color: const Color(0xFF51634B)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.verified_user_outlined,
          color: _RegisterColors.sage,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VÍ ĐÃ XÁC MINH',
                style: TextStyle(
                  color: _RegisterColors.muted,
                  fontSize: 10,
                  height: 1.4,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                address.length > 14
                    ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
                    : address,
                style: const TextStyle(
                  color: _RegisterColors.paper,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RegistrationNotice extends StatelessWidget {
  const _RegistrationNotice({required this.message, this.isError = false});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0x663F1919) : const Color(0xFF1B2A28),
        border: Border.all(
          color: isError ? const Color(0xFFBB7963) : const Color(0xFF6B7359),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.lock_outline_rounded,
            color: isError ? const Color(0xFFFFC9B8) : _RegisterColors.gold,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isError ? const Color(0xFFFFC9B8) : _RegisterColors.paper,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RegisterButton extends StatelessWidget {
  const _RegisterButton({
    required this.label,
    required this.busy,
    required this.reducedMotion,
    this.onPressed,
  });
  final String label;
  final bool busy;
  final bool reducedMotion;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => ElevatedButton(
    key: const ValueKey('register-submit'),
    onPressed: onPressed,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(58)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      ),
      animationDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      foregroundColor: const WidgetStatePropertyAll(Color(0xFF201B1B)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Color(0xFF827252);
        }
        if (states.contains(WidgetState.pressed)) return CauHinh.mauChinh;
        return states.contains(WidgetState.hovered)
            ? const Color(0xFFFFDF8C)
            : const Color(0xFFF6C65B);
      }),
      elevation: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed) ? 1 : 4,
      ),
      shape: const WidgetStatePropertyAll(
        BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
          side: BorderSide(color: _RegisterColors.gold, width: 1.5),
        ),
      ),
    ),
    child: Row(
      children: [
        if (busy && !reducedMotion)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _RegisterColors.paper,
            ),
          )
        else
          Icon(
            busy ? Icons.hourglass_top_rounded : Icons.auto_awesome_outlined,
            size: 21,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.4,
              letterSpacing: .5,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A quiet pixel forest around a stone arch. Uniform scaling crops the scene;
/// no game instance, network image or duplicated Welcome background is needed.
class _RegisterBackdrop extends CustomPainter {
  const _RegisterBackdrop();
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / 480, size.height / 360);
    canvas.save();
    canvas.translate(
      (size.width - 480 * scale) / 2,
      (size.height - 360 * scale) / 2,
    );
    canvas.scale(scale);
    const bounds = Rect.fromLTWH(0, 0, 480, 360);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101B27), Color(0xFF1D3831), Color(0xFF101E23)],
        ).createShader(bounds),
    );
    void block(double x, double y, double w, double h, Color color) =>
        canvas.drawRect(
          Rect.fromLTWH(x, y, w, h),
          Paint()
            ..color = color
            ..isAntiAlias = false,
        );
    for (var i = 0; i < 32; i++) {
      block(
        (i * 71 % 480).toDouble(),
        (i * 37 % 170).toDouble(),
        i % 6 == 0 ? 2 : 1,
        1,
        const Color(0xFF6B7C6F),
      );
    }
    const stone = Color(0xFF34463F);
    block(88, 130, 22, 230, stone);
    block(370, 130, 22, 230, stone);
    for (var i = 0; i < 7; i++) {
      block(94 + i * 12, 120 - i * 12, 20, 20, stone);
      block(366 - i * 12, 120 - i * 12, 20, 20, stone);
    }
    block(172, 37, 136, 17, stone);
    for (var i = 0; i < 9; i++) {
      block(91, 149 + i * 25, 15, 1, const Color(0xFF5B6250));
      block(374, 149 + i * 25, 15, 1, const Color(0xFF5B6250));
    }
    for (final x in [73.0, 407.0]) {
      block(x - 1, 187, 3, 24, const Color(0xFF4D3C29));
      block(x - 5, 176, 11, 10, const Color(0xFF8B6331));
      block(x - 3, 170, 7, 10, const Color(0xFFDBAE55));
      block(x - 1, 173, 3, 8, _RegisterColors.gold);
    }
    for (final x in [4.0, 31.0, 55.0, 429.0, 452.0, 478.0]) {
      block(x, 181, 6, 179, const Color(0xFF101F1C));
      for (var level = 0; level < 6; level++) {
        final width = 10 + level * 8.0;
        block(
          x + 3 - width / 2,
          79 + level * 28.0,
          width,
          38,
          const Color(0xFF122E24),
        );
        block(
          x + 3 - width / 2,
          79 + level * 28.0,
          width * .4,
          3,
          const Color(0xFF294535),
        );
      }
    }
    for (var i = 0; i < 24; i++) {
      block(
        (i * 89 % 480).toDouble(),
        299 + (i * 19 % 59).toDouble(),
        4,
        1,
        const Color(0xFF365140),
      );
    }
    canvas.drawRect(bounds, Paint()..color = const Color(0x33101B27));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RegisterBackdrop oldDelegate) => false;
}
