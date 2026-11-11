/// Web UI boundary, not backend authorization. The parent owns AuthController,
/// its transports and app shutdown. No game, wallet, HTTP client or route is
/// created until the supplied controller has verified authenticated access.
///
/// The composition root supplies the controller and authenticated game builder.
/// This file deliberately
/// does not import main.dart or Flame. The gate must wrap the entire protected
/// game, including its menus/overlays. Do not push protected routes outside it.
///
/// By default every check unmounts gameplay. A host that synchronously pauses
/// its engine can opt into retaining hidden State during passive checks. The
/// same confirmed identity resumes it; failures and identity changes remove it.
/// This UI boundary does not authorize legacy backend endpoints.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../auth_controller.dart';
import 'register_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.authenticatedBuilder,
    this.restoreOnMount = true,
    this.recheckOnResume = true,
    this.retainGameDuringSessionCheck = false,
  });

  final AuthController controller;

  /// Build a fresh Widget subtree here; keep game engines in that subtree's
  /// State/lifecycle. Do not pre-create a FlameGame or reuse a GlobalKey from
  /// outside this boundary. Every loss of authority receives a new subtree key.
  final WidgetBuilder authenticatedBuilder;

  /// Only an initial controller is bootstrapped. Checking/restored controllers
  /// supplied by a parent are left alone. Set false if the parent owns startup.
  final bool restoreOnMount;

  /// Passive revalidation after an observed background/resume transition.
  /// AuthController implements this using /me and non-interactive wallet reads.
  final bool recheckOnResume;

  /// Opt-in for a game host that synchronously pauses its engine on lost access.
  /// Keep State only during passive checking, hidden and non-interactive. A
  /// failed check, expiry, logout or wallet event still destroys the subtree.
  final bool retainGameDuringSessionCheck;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  VoidCallback? _listener;
  int _lifecycle = 0;
  bool _initialRestoreScheduled = false;
  bool _restoreInProgress = false;
  bool _restoreFailed = false;
  bool _rebuildScheduled = false;
  bool _wasBackgrounded = false;
  bool _registrationBack = false;
  ({String wallet, DateTime expires})? _grant;
  ({String user, String wallet, BigInt chain, DateTime expires})? _session;
  Key? _gameKey;

  bool get _allowed =>
      !_restoreInProgress &&
      !_restoreFailed &&
      widget.controller.status == AuthStatus.authenticated &&
      widget.controller.canEnterGame;

  bool get _retainChecking =>
      widget.retainGameDuringSessionCheck &&
      !_restoreFailed &&
      _session != null &&
      !widget.controller.logoutPending &&
      _session!.expires.isAfter(DateTime.now().toUtc()) &&
      (widget.controller.status == AuthStatus.checkingSession ||
          _restoreInProgress &&
              widget.controller.status == AuthStatus.authenticated);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachController();
  }

  void _attachController() {
    final controller = widget.controller;
    final lifecycle = _lifecycle;
    _listener = () {
      if (!mounted ||
          lifecycle != _lifecycle ||
          controller != widget.controller) {
        return;
      }
      _synchronize();
      _refresh();
    };
    controller.addListener(_listener!);
    _synchronize();
    _scheduleInitialRestore();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_listener!);
      _lifecycle++;
      _initialRestoreScheduled = false;
      _restoreInProgress = false;
      _restoreFailed = false;
      _rebuildScheduled = false;
      _wasBackgrounded = false;
      _registrationBack = false;
      _grant = null;
      _session = null;
      _gameKey = null;
      _attachController();
    } else if (!oldWidget.restoreOnMount && widget.restoreOnMount) {
      _scheduleInitialRestore();
    }
  }

  void _scheduleInitialRestore() {
    if (!widget.restoreOnMount ||
        _initialRestoreScheduled ||
        widget.controller.status != AuthStatus.initial) {
      return;
    }
    _initialRestoreScheduled = true;
    final controller = widget.controller;
    final lifecycle = _lifecycle;
    // Initial child construction can occur inside a parent's build. Start
    // after that frame so controller notifications cannot mutate that build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          lifecycle != _lifecycle ||
          controller != widget.controller) {
        return;
      }
      if (!widget.restoreOnMount) {
        _initialRestoreScheduled = false;
        return;
      }
      // A parent may have started restore or a user flow since scheduling.
      if (controller.status == AuthStatus.initial) {
        unawaited(_restore(controller, lifecycle));
      }
    });
  }

  Future<void> _restore(AuthController controller, int lifecycle) async {
    if (!mounted ||
        lifecycle != _lifecycle ||
        controller != widget.controller ||
        _restoreInProgress) {
      return;
    }
    _restoreInProgress = true;
    _restoreFailed = false;
    _synchronize();
    _refresh();
    try {
      await controller.restoreSession();
    } catch (_) {
      // The current controller normally reports errors as state. If it ever
      // throws, do not expose its exception or fall back to cached authority.
      if (mounted &&
          lifecycle == _lifecycle &&
          controller == widget.controller) {
        _restoreFailed = true;
      }
    } finally {
      if (mounted &&
          lifecycle == _lifecycle &&
          controller == widget.controller) {
        _restoreInProgress = false;
        _synchronize();
        _refresh();
      }
    }
  }

  /// Forget the old identity even if loss and recovery happen between frames;
  /// the former user's State must not be reused by a later authenticated tree.
  void _synchronize() {
    final controller = widget.controller;
    if (!_allowed && !_retainChecking) {
      _session = null;
      _gameKey = null;
    } else if (_allowed) {
      final session = (
        user: controller.user!.id,
        wallet: controller.walletAddress!,
        chain: controller.chainId!,
        expires: controller.expiresAt!,
      );
      if (session != _session) {
        _session = session;
        _gameKey = UniqueKey();
      }
    }
    if (controller.status == AuthStatus.registrationRequired ||
        controller.status == AuthStatus.registering) {
      final wallet = controller.walletAddress;
      final expires = controller.expiresAt;
      final grant = wallet == null || expires == null
          ? null
          : (wallet: wallet, expires: expires);
      if (grant != _grant) _registrationBack = false;
      _grant = grant;
    } else {
      _registrationBack = false;
      _grant = null;
    }
  }

  void _refresh() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    // Defensive against a builder/inherited dependency triggering an auth
    // notification during a frame. The protected child also rechecks access.
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    final lifecycle = _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || lifecycle != _lifecycle) return;
      _rebuildScheduled = false;
      setState(() {});
    });
  }

  Future<void> _showRegistration(AuthController expected) async {
    if (!mounted ||
        expected != widget.controller ||
        expected.isLoading ||
        expected.logoutPending ||
        expected.status != AuthStatus.registrationRequired) {
      return;
    }
    setState(() => _registrationBack = false);
  }

  Future<void> _showWelcome(AuthController expected) async {
    if (!mounted || expected != widget.controller || expected.isLoading) return;
    // This is local screen selection only. It does NOT cancel/revoke a grant,
    // change controller status or claim a successful server logout. Welcome's
    // create-character action can reopen the same still-valid registration.
    setState(() => _registrationBack = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _wasBackgrounded = true;
      return;
    }
    final resumed = _wasBackgrounded;
    _wasBackgrounded = false;
    if (resumed &&
        widget.recheckOnResume &&
        widget.controller.status == AuthStatus.authenticated) {
      unawaited(_restore(widget.controller, _lifecycle));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if ((_allowed || _retainChecking) && _gameKey != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _AuthenticatedContent(
            key: _gameKey,
            controller: controller,
            authenticatedBuilder: widget.authenticatedBuilder,
            retainWhileChecking: widget.retainGameDuringSessionCheck,
          ),
          if (!_allowed)
            const _GateWaiting(
              message: 'ĐANG KIỂM TRA HỒ SƠ NHÀ THÁM HIỂM...',
              detail: 'Hành trình đang tạm dừng để đối chiếu phiên và ví.',
            ),
        ],
      );
    }
    if (_restoreFailed) {
      return _GateWaiting(
        message: 'CHƯA THỂ KIỂM TRA HỒ SƠ',
        detail: 'Hành trình đang khóa. Hãy kiểm tra kết nối và thử lại.',
        onRetry: () => unawaited(_restore(controller, _lifecycle)),
      );
    }
    if (_restoreInProgress ||
        controller.status == AuthStatus.initial ||
        controller.status == AuthStatus.checkingSession) {
      return const _GateWaiting(
        message: 'ĐANG KIỂM TRA HỒ SƠ NHÀ THÁM HIỂM...',
        detail: 'Đang đối chiếu phiên đăng nhập và ví MetaMask.',
      );
    }
    if (controller.status == AuthStatus.loggingOut) {
      return const _GateWaiting(
        message: 'ĐANG ĐĂNG XUẤT...',
        detail: 'Hành trình đã khóa. Đang chờ máy chủ xác nhận.',
      );
    }
    if (controller.status == AuthStatus.registering ||
        controller.status == AuthStatus.registrationRequired &&
            !_registrationBack) {
      return RegisterScreen(
        key: ObjectKey(controller),
        controller: controller,
        onBack: () => _showWelcome(controller),
        // No success callback is treated as evidence. Controller notifications
        // alone replace this screen after verify/register AND /me succeed.
      );
    }
    return WelcomeScreen(
      key: ObjectKey(controller),
      controller: controller,
      onRegistrationRequired: () => _showRegistration(controller),
    );
  }

  @override
  void dispose() {
    _lifecycle++;
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_listener!);
    // The parent still owns controller and its ongoing network operation.
    super.dispose();
  }
}

/// A fresh keyed instance owns its Widget cache. Passive checks can retain a
/// hidden, paused game only when explicitly enabled by a suitable game host.
class _AuthenticatedContent extends StatefulWidget {
  const _AuthenticatedContent({
    super.key,
    required this.controller,
    required this.authenticatedBuilder,
    this.retainWhileChecking = false,
  });
  final AuthController controller;
  final WidgetBuilder authenticatedBuilder;
  final bool retainWhileChecking;

  @override
  State<_AuthenticatedContent> createState() => _AuthenticatedContentState();
}

class _AuthenticatedContentState extends State<_AuthenticatedContent> {
  Widget? _content;
  bool get _allowed =>
      widget.controller.status == AuthStatus.authenticated &&
      widget.controller.canEnterGame;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content = null;
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authenticatedBuilder != widget.authenticatedBuilder ||
        oldWidget.controller != widget.controller) {
      _content = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed &&
        !(widget.retainWhileChecking &&
            widget.controller.status == AuthStatus.checkingSession &&
            _content != null)) {
      return const SizedBox.shrink();
    }
    if (_allowed) _content ??= widget.authenticatedBuilder(context);
    // A synchronous builder must not be able to publish content if it caused
    // access to be invalidated while constructing that content.
    if (!_allowed &&
        !(widget.retainWhileChecking &&
            widget.controller.status == AuthStatus.checkingSession)) {
      return const SizedBox.shrink();
    }
    return TickerMode(
      enabled: _allowed,
      child: Offstage(offstage: !_allowed, child: _content),
    );
  }
}

class _GateWaiting extends StatelessWidget {
  const _GateWaiting({
    required this.message,
    required this.detail,
    this.onRetry,
  });
  final String message;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    const gold = Color(0xFFF1CF7A);
    const paper = Color(0xFFF5E3B5);
    return Scaffold(
      backgroundColor: const Color(0xFF101B27),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1,
            colors: [Color(0xFF244A3A), Color(0xFF101B27)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 40).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4A3022), Color(0xFF201B1B)],
                          ),
                          shape: BeveledRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: gold, width: 2),
                          ),
                          shadows: const [
                            BoxShadow(
                              color: Color(0x88071017),
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'GOLD RUSH',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: gold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                  letterSpacing: 3,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 23),
                              Icon(
                                onRetry != null
                                    ? Icons.shield_outlined
                                    : Icons.diamond_outlined,
                                color: gold,
                                size: 36,
                              ),
                              const SizedBox(height: 18),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  message,
                                  key: const ValueKey('auth-gate-status'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: paper,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                detail,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFC8BBA0),
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 23),
                              if (onRetry != null)
                                OutlinedButton.icon(
                                  onPressed: onRetry,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('THỬ LẠI'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: gold,
                                    minimumSize: const Size.fromHeight(48),
                                    side: const BorderSide(color: gold),
                                  ),
                                )
                              else if (reduced)
                                const Text(
                                  'Vui lòng chờ…',
                                  style: TextStyle(color: gold, fontSize: 12),
                                )
                              else
                                const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    color: gold,
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
