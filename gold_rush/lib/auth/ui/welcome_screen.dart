/// Web Welcome UI only. The parent owns AuthController and future navigation.
/// No restore/login runs on mount; no Flame world, provider, HTTP client,
/// registration route or credentials are created here. Import conditionally
/// for native builds because the injected controller is currently Web-only.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cau_hinh.dart';
import '../auth_controller.dart';

/// A parent can return its navigation Future to keep repeated taps disabled.
typedef WelcomeCallback = FutureOr<void> Function();

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.controller,
    this.onRegistrationRequired,
    this.onAuthenticated,
  });

  final AuthController controller;

  /// Called only by the create-character button while a grant is present.
  final WelcomeCallback? onRegistrationRequired;

  /// Called only by an explicit continue action while canEnterGame is true,
  /// at most once for the same controller/user/session expiry. Rebuilds never
  /// trigger navigation. A future Auth Gate must still enforce canEnterGame.
  final WelcomeCallback? onAuthenticated;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambience;
  bool _reducedMotion = false;
  bool _actionPending = false;
  int _actionGeneration = 0;
  String? _forwardedSession;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _ambience = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (!_reducedMotion && TickerMode.valuesOf(context).enabled) {
      if (!_ambience.isAnimating) _ambience.repeat();
    } else {
      _ambience.stop();
    }
  }

  @override
  void didUpdateWidget(covariant WelcomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _actionGeneration++;
      _actionPending = false;
      _forwardedSession = null;
      _actionError = null;
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_actionPending || widget.controller.isLoading) return;
    final generation = ++_actionGeneration;
    setState(() {
      _actionPending = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      // Never render an untrusted exception from a parent's navigation callback.
      if (mounted && generation == _actionGeneration) {
        setState(() {
          _actionError = 'Chưa thể hoàn tất thao tác. Hãy thử lại.';
          _forwardedSession = null;
        });
      }
    } finally {
      if (mounted && generation == _actionGeneration) {
        setState(() => _actionPending = false);
      }
    }
  }

  String _sessionKey(AuthController controller) =>
      '${identityHashCode(controller)}:${controller.user?.id}:'
      '${controller.expiresAt?.microsecondsSinceEpoch}';

  Future<void> _createCharacter() => _perform(() async {
    final controller = widget.controller;
    if (controller.status != AuthStatus.registrationRequired ||
        controller.logoutPending) {
      return;
    }
    await widget.onRegistrationRequired?.call();
  });

  Future<void> _continueAdventure() => _perform(() async {
    final controller = widget.controller;
    final key = _sessionKey(controller);
    if (!controller.canEnterGame ||
        _forwardedSession == key ||
        widget.onAuthenticated == null) {
      return;
    }
    setState(() => _forwardedSession = key);
    await widget.onAuthenticated!();
  });

  _Action _action(AuthController controller) {
    if (controller.isLoading) {
      return _Action(
        _busyLabel(controller.status),
        Icons.hourglass_top_rounded,
      );
    }
    if (controller.logoutPending) {
      return _Action(
        'THỬ ĐĂNG XUẤT LẠI',
        Icons.refresh_rounded,
        run: () => _perform(controller.logout),
      );
    }
    if (controller.status == AuthStatus.registrationRequired) {
      return _Action(
        'TẠO NHÂN VẬT',
        Icons.person_add_alt_1_rounded,
        run: widget.onRegistrationRequired == null ? null : _createCharacter,
      );
    }
    if (controller.canEnterGame) {
      return _Action(
        'BẮT ĐẦU PHIÊU LƯU',
        Icons.arrow_forward_rounded,
        run:
            widget.onAuthenticated == null ||
                _forwardedSession == _sessionKey(controller)
            ? null
            : _continueAdventure,
      );
    }
    if (controller.status == AuthStatus.authenticated) {
      return _Action(
        'KIỂM TRA LẠI PHIÊN',
        Icons.refresh_rounded,
        run: () => _perform(controller.restoreSession),
      );
    }
    return _Action(
      controller.status == AuthStatus.error
          ? 'THỬ KẾT NỐI LẠI'
          : 'KẾT NỐI METAMASK',
      Icons.account_balance_wallet_outlined,
      run: () => _perform(controller.connectAndSignIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _LandscapePainter()),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.2),
                radius: 1.2,
                colors: [Color(0x15101B27), Color(0xAA101B27)],
              ),
            ),
          ),
          IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(painter: _FirefliesPainter(_ambience)),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 440;
                final padding = narrow ? 16.0 : 28.0;
                return SingleChildScrollView(
                  key: const ValueKey('welcome-scroll'),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: padding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        constraints.maxHeight - padding * 2,
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: _reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 10),
                              child: child,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _GameTitle(narrow: narrow),
                              const SizedBox(height: 26),
                              ListenableBuilder(
                                listenable: widget.controller,
                                builder: (context, _) => _panel(narrow),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                'MỖI HÀNH TRÌNH BẮT ĐẦU TỪ MỘT BƯỚC CHÂN',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _Palette.mist,
                                  fontSize: 10,
                                  letterSpacing: 1.8,
                                  height: 1.6,
                                  fontWeight: FontWeight.w600,
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

  Widget _panel(bool narrow) {
    final controller = widget.controller;
    final action = _action(controller);
    final busy = controller.isLoading || _actionPending;
    final authenticated = controller.canEnterGame;
    final error = controller.errorMessage ?? _actionError;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Palette.woodLight, _Palette.wood, _Palette.woodDark],
          ),
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: _Palette.gold, width: 2),
          ),
          shadows: const [
            BoxShadow(color: Color(0xAA070F15), offset: Offset(0, 7)),
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 36,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(narrow ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AdventurerCrest(),
              const SizedBox(height: 18),
              Text(
                'CHÀO MỪNG\nNHÀ THÁM HIỂM!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _Palette.parchment,
                  fontSize: narrow ? 22 : 25,
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Khám phá thế giới Gold Rush, thu thập kho báu '
                'và bắt đầu hành trình của bạn.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _Palette.parchment,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Đăng nhập an toàn bằng ví MetaMask để lưu tài khoản phiêu lưu.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _Palette.muted,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 21),
              const _GoldRule(),
              const SizedBox(height: 17),
              Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      authenticated
                          ? Icons.verified_user_outlined
                          : controller.status == AuthStatus.registrationRequired
                          ? Icons.person_outline_rounded
                          : Icons.auto_awesome_outlined,
                      color: authenticated ? _Palette.sage : _Palette.gold,
                      size: 20,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _statusMessage(controller),
                      key: const ValueKey('welcome-auth-status'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: authenticated
                            ? _Palette.sage
                            : _Palette.parchment,
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (controller.walletAddress case final String address) ...[
                      const SizedBox(height: 7),
                      Text(
                        _shortWallet(address),
                        style: const TextStyle(
                          color: _Palette.muted,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    key: const ValueKey('welcome-auth-error'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x663F1919),
                      border: Border.all(color: const Color(0xFFBB7963)),
                    ),
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFC9B8),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 17),
              _QuestButton(
                label: action.label,
                icon: action.icon,
                busy: busy,
                reducedMotion: _reducedMotion,
                onPressed: busy || action.run == null
                    ? null
                    : () => unawaited(action.run!()),
              ),
              const SizedBox(height: 18),
              const _SecurityNote(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _actionGeneration++;
    _ambience.dispose();
    // Controller is caller-owned; ListenableBuilder removes its own listener.
    super.dispose();
  }
}

class _Action {
  const _Action(this.label, this.icon, {this.run});
  final String label;
  final IconData icon;
  final Future<void> Function()? run;
}

String _busyLabel(AuthStatus status) => switch (status) {
  AuthStatus.checkingSession => 'ĐANG KIỂM TRA PHIÊN',
  AuthStatus.connectingWallet => 'ĐANG KẾT NỐI VÍ',
  AuthStatus.requestingChallenge => 'ĐANG CHUẨN BỊ XÁC THỰC',
  AuthStatus.awaitingSignature => 'ĐANG CHỜ CHỮ KÝ',
  AuthStatus.verifying => 'ĐANG XÁC MINH',
  AuthStatus.registering => 'ĐANG TẠO NHÂN VẬT',
  AuthStatus.loggingOut => 'ĐANG ĐĂNG XUẤT',
  _ => 'ĐANG XỬ LÝ',
};

String _statusMessage(AuthController controller) {
  if (controller.canEnterGame) return 'Chào mừng quay trở lại Gold Rush!';
  return switch (controller.status) {
    AuthStatus.initial ||
    AuthStatus.unauthenticated => 'Kết nối MetaMask để bắt đầu.',
    AuthStatus.checkingSession => 'Đang kiểm tra phiên đăng nhập...',
    AuthStatus.connectingWallet => 'Đang kết nối ví MetaMask...',
    AuthStatus.requestingChallenge => 'Đang chuẩn bị xác thực...',
    AuthStatus.awaitingSignature => 'Vui lòng xác nhận chữ ký trong MetaMask.',
    AuthStatus.verifying => 'Đang xác minh chữ ký...',
    AuthStatus.registrationRequired =>
      'Ví của bạn đã được xác minh. Hãy tạo tên nhân vật.',
    AuthStatus.registering => 'Đang tạo nhân vật của bạn...',
    AuthStatus.authenticated =>
      'Phiên cần được kiểm tra lại trước khi bắt đầu.',
    AuthStatus.loggingOut => 'Đang đăng xuất...',
    AuthStatus.error =>
      controller.logoutPending
          ? 'Hành trình đang khóa cho đến khi đối chiếu lại phiên.'
          : 'Chưa thể kết nối hành trình. Bạn có thể thử lại.',
  };
}

String _shortWallet(String address) => address.length > 14
    ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
    : address;

abstract final class _Palette {
  static const gold = Color(0xFFF1CF7A);
  static const parchment = Color(0xFFF5E3B5);
  static const woodLight = Color(0xFF4A3022);
  static const wood = Color(0xFF30231E);
  static const woodDark = Color(0xFF201B1B);
  static const night = Color(0xFF101B27);
  static const muted = Color(0xFFC8BBA0);
  static const mist = Color(0xFFABB8B4);
  static const sage = Color(0xFFB7DFAC);
}

class _GameTitle extends StatelessWidget {
  const _GameTitle({required this.narrow});
  final bool narrow;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'LỜI MỜI TỪ VÙNG ĐẤT VÀNG',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _Palette.gold,
          fontSize: 10,
          letterSpacing: 2.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        label: 'Gold Rush',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'GOLD RUSH',
            style: TextStyle(
              fontSize: narrow ? 55 : 76,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              color: _Palette.gold,
              shadows: const [
                Shadow(color: Color(0xFF50331C), offset: Offset(0, 4)),
                Shadow(color: Color(0xFF07121A), offset: Offset(3, 7)),
                Shadow(color: Color(0x66E3A008), blurRadius: 32),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'AI ADVENTURE & BLOCKCHAIN',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _Palette.parchment,
          fontSize: 11,
          letterSpacing: 2.7,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _AdventurerCrest extends StatelessWidget {
  const _AdventurerCrest();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _SpriteFrame(
          asset: 'assets/images/dong_xu.png',
          columns: 8,
          rows: 1,
          size: 32,
        ),
        const SizedBox(width: 18),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: const Color(0xFF182E29),
            shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: const BorderSide(color: _Palette.gold),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: _SpriteFrame(
              asset: 'assets/images/george.png',
              columns: 4,
              rows: 4,
              size: 48,
            ),
          ),
        ),
        const SizedBox(width: 18),
        const _SpriteFrame(
          asset: 'assets/images/dong_xu.png',
          columns: 8,
          rows: 1,
          size: 32,
        ),
      ],
    ),
  );
}

/// Shows only the top-left 16x16 frame, never the entire sprite sheet.
class _SpriteFrame extends StatelessWidget {
  const _SpriteFrame({
    required this.asset,
    required this.columns,
    required this.rows,
    required this.size,
  });
  final String asset;
  final int columns;
  final int rows;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size * columns,
        maxWidth: size * columns,
        minHeight: size * rows,
        maxHeight: size * rows,
        child: Image.asset(
          asset,
          width: size * columns,
          height: size * rows,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.none,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

class _GoldRule extends StatelessWidget {
  const _GoldRule();
  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Row(
      children: [
        Expanded(child: Divider(color: Color(0x665F5140), height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.diamond_outlined, size: 13, color: _Palette.gold),
        ),
        Expanded(child: Divider(color: Color(0x665F5140), height: 1)),
      ],
    ),
  );
}

class _QuestButton extends StatelessWidget {
  const _QuestButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.reducedMotion,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool busy;
  final bool reducedMotion;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton(
    key: const ValueKey('welcome-primary-action'),
    onPressed: onPressed,
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      ),
      animationDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return const Color(0xFF514638);
        }
        if (states.contains(WidgetState.pressed)) return CauHinh.mauChinh;
        if (states.contains(WidgetState.hovered)) {
          return const Color(0xFFFFDF8C);
        }
        return const Color(0xFFF6C65B);
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? _Palette.muted
            : _Palette.woodDark,
      ),
      elevation: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? 1
            : states.contains(WidgetState.hovered)
            ? 7
            : 4,
      ),
      shadowColor: const WidgetStatePropertyAll(Color(0xCC0D1010)),
      shape: WidgetStatePropertyAll(
        BeveledRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: _Palette.gold, width: 1.5),
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
              color: _Palette.gold,
            ),
          )
        else
          Icon(busy ? Icons.hourglass_top_rounded : icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              letterSpacing: .7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();
  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.shield_outlined, color: _Palette.muted, size: 17),
      SizedBox(height: 7),
      Text(
        'Ký thông điệp miễn phí – không mất phí gas.\n'
        'Không yêu cầu mật khẩu hoặc khóa bí mật.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _Palette.muted, fontSize: 11, height: 1.7),
      ),
    ],
  );
}

/// A fixed virtual landscape scales uniformly and crops instead of stretching.
/// Pixel blocks are painted without anti-aliasing. It does not load a map or
/// instantiate Flame; all drawing is deterministic and cached by its boundary.
class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(size.width / 512, size.height / 320);
    canvas.save();
    canvas.translate(
      (size.width - 512 * scale) / 2,
      (size.height - 320 * scale) / 2,
    );
    canvas.scale(scale);
    const bounds = Rect.fromLTWH(0, 0, 512, 320);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101E32), Color(0xFF244943), Color(0xFF152B26)],
        ).createShader(bounds),
    );
    for (var i = 0; i < 46; i++) {
      _block(
        canvas,
        12 + (i * 79 % 490).toDouble(),
        10 + (i * 31 % 126).toDouble(),
        i % 5 == 0 ? 2 : 1,
        1,
        i % 3 == 0 ? const Color(0xFF9DAB99) : const Color(0xFF667C7C),
      );
    }
    _block(canvas, 408, 28, 24, 36, const Color(0xFFB7BA94));
    _block(canvas, 402, 34, 36, 24, const Color(0xFFB7BA94));
    _block(canvas, 407, 34, 20, 26, const Color(0xFFE0D6A5));
    _ridge(canvas, 117, const Color(0xFF29474E), 0);
    _ridge(canvas, 151, const Color(0xFF25483F), 19);
    _castle(canvas);
    _block(canvas, 0, 195, 512, 125, const Color(0xFF1B3A2C));
    // Winding old road towards the castle, mostly behind the welcome board.
    final path = Path()
      ..moveTo(348, 184)
      ..lineTo(360, 184)
      ..lineTo(320, 220)
      ..lineTo(342, 252)
      ..lineTo(312, 286)
      ..lineTo(350, 320)
      ..lineTo(230, 320)
      ..lineTo(279, 275)
      ..lineTo(302, 252)
      ..lineTo(293, 222)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4B5140)
        ..isAntiAlias = false,
    );
    for (var i = 0; i < 17; i++) {
      _tree(
        canvas,
        i * 34.0 - 8,
        219 + (i % 3) * 10.0,
        49 + (i * 13 % 40).toDouble(),
        const Color(0xFF183B2D),
      );
    }
    for (final x in [-6.0, 40.0, 83.0, 435.0, 476.0, 518.0]) {
      _tree(canvas, x, 323, x < 100 ? 165 : 184, const Color(0xFF102B23));
    }
    for (var i = 0; i < 95; i++) {
      final x = (i * 47 % 512).toDouble();
      final y = 244 + (i * 19 % 75).toDouble();
      _block(canvas, x, y, 3, 1, const Color(0xFF31583A));
      if (i % 12 == 0) _block(canvas, x, y - 2, 1, 2, const Color(0xFF9C8B46));
    }
    _chest(canvas, 96, 275);
    _chest(canvas, 417, 291);
    canvas.restore();
  }

  void _block(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    Color color,
  ) => canvas.drawRect(
    Rect.fromLTWH(x, y, w, h),
    Paint()
      ..color = color
      ..isAntiAlias = false,
  );

  void _ridge(Canvas canvas, double y, Color color, double shift) {
    final path = Path()
      ..moveTo(0, 220)
      ..lineTo(0, y + 22);
    for (var i = 0; i < 13; i++) {
      final x = i * 44.0;
      final top = y - (i * 23 % 46) + shift;
      path
        ..lineTo(x, top + 12)
        ..lineTo(x + 18, top + 12)
        ..lineTo(x + 18, top)
        ..lineTo(x + 31, top)
        ..lineTo(x + 31, top + 18);
    }
    path
      ..lineTo(512, 220)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }

  void _tree(
    Canvas canvas,
    double x,
    double ground,
    double height,
    Color color,
  ) {
    _block(
      canvas,
      x - 3,
      ground - height * .35,
      6,
      height * .35,
      const Color(0xFF182B22),
    );
    for (var level = 0; level < 5; level++) {
      final width = height * (.10 + level * .095);
      final y = ground - height + level * height * .14;
      _block(canvas, x - width / 2, y, width, height * .19, color);
      _block(
        canvas,
        x - width / 2 + 3,
        y,
        math.max(1, width * .34),
        2,
        const Color(0xFF254735),
      );
    }
  }

  void _castle(Canvas canvas) {
    const stone = Color(0xFF55645F);
    const shadow = Color(0xFF354C48);
    _block(canvas, 350, 153, 72, 42, shadow);
    for (final x in [345.0, 400.0]) {
      _block(canvas, x, 123, 21, 71, stone);
      _block(canvas, x + 14, 123, 7, 71, shadow);
      _block(canvas, x - 2, 119, 25, 7, stone);
      for (var i = 0; i < 3; i++) {
        _block(canvas, x - 2 + i * 10, 113, 5, 7, stone);
      }
      _block(canvas, x + 7, 136, 4, 7, const Color(0xFFC3A369));
    }
    _block(canvas, 374, 103, 18, 54, stone);
    _block(canvas, 377, 96, 12, 7, stone);
    _block(canvas, 382, 83, 2, 15, const Color(0xFF7D8770));
    _block(canvas, 384, 83, 11, 6, const Color(0xFFBA9051));
    _block(canvas, 373, 176, 16, 19, const Color(0xFF172E29));
    _block(canvas, 377, 172, 8, 5, const Color(0xFF172E29));
    for (var i = 0; i < 5; i++) {
      _block(canvas, 350 + i * 15, 148, 7, 7, stone);
    }
  }

  void _chest(Canvas canvas, double x, double y) {
    _block(canvas, x - 2, y + 14, 31, 5, const Color(0xFF0D241E));
    _block(canvas, x, y, 27, 17, const Color(0xFF70482C));
    _block(canvas, x + 2, y - 4, 23, 6, const Color(0xFF8C6037));
    _block(canvas, x, y + 5, 27, 2, const Color(0xFFBC9850));
    _block(canvas, x + 3, y - 2, 2, 19, const Color(0xFFBC9850));
    _block(canvas, x + 21, y - 2, 2, 19, const Color(0xFFBC9850));
    _block(canvas, x + 11, y + 4, 5, 6, _Palette.gold);
  }

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) => false;
}

class _FirefliesPainter extends CustomPainter {
  _FirefliesPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 10; i++) {
      final phase = animation.value * math.pi * 2 + i * 1.9;
      final x = size.width * ((i * 79 + 13) % 97) / 100 + math.sin(phase) * 6;
      final y =
          size.height * (.22 + ((i * 31) % 67) / 100) + math.cos(phase) * 9;
      final opacity = .25 + (math.sin(phase) + 1) * .2;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: 9, height: 9),
        Paint()..color = _Palette.gold.withValues(alpha: opacity * .10),
      );
      canvas.drawRect(
        Rect.fromLTWH(x.floorToDouble(), y.floorToDouble(), 2, 2),
        Paint()
          ..color = _Palette.gold.withValues(alpha: opacity)
          ..isAntiAlias = false,
      );
    }
  }

  @override
  bool shouldRepaint(_FirefliesPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
