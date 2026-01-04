import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'hand_input_bridge.dart';

/// Trackpad-like demo:
/// - Native sends dx/dy impulses.
/// - Flutter integrates into position with inertia/friction.
class HandBallPage extends StatefulWidget {
  const HandBallPage({super.key});

  @override
  State<HandBallPage> createState() => _HandBallPageState();
}

class _HandBallPageState extends State<HandBallPage> with SingleTickerProviderStateMixin {
  static const double _ballSize = 26;

  final HandInputBridge _bridge = HandInputBridge.instance;

  late final ValueNotifier<_BallState> _ball =
      ValueNotifier<_BallState>(_BallState.center());

  StreamSubscription<HandDeltaState>? _sub;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Physics tuning (mouse-feel)
  // Impulse scale: how much dx/dy affects velocity.
  static const double _impulseGain = 2200; // higher = faster
  // Friction per second (0..1). Closer to 0 = heavy friction, closer to 1 = slippery.
  static const double _frictionPerSecond = 0.10; // 0.10 => strong damping
  // Max speed in normalized units per second
  static const double _maxSpeed = 2.5;

  @override
  void initState() {
    super.initState();
    _bridge.start();

    _sub = _bridge.stream.listen((e) {
      if (!e.active) {
        // stop velocity gradually; keep position
        _ball.value = _ball.value.copyWith(active: false);
        return;
      }

      final bs = _ball.value;

      // Convert dx/dy (normalized per update) into a velocity impulse.
      // We apply gain here to achieve cursor-like speed.
      final vx = (bs.vx + e.dx * _impulseGain);
      final vy = (bs.vy + e.dy * _impulseGain);

      _ball.value = bs.copyWith(vx: vx, vy: vy, active: true);
    });

    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    _ball.dispose();
    _bridge.dispose();
    super.dispose();
  }

  void _onTick(Duration now) {
    if (_lastTick == Duration.zero) {
      _lastTick = now;
      return;
    }

    final dt = (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    if (dt <= 0) return;

    final bs = _ball.value;

    // Apply friction exponentially based on dt
    final friction = math.pow(_frictionPerSecond, dt).toDouble(); // e.g. dt=1s => 0.10
    var vx = bs.vx * friction;
    var vy = bs.vy * friction;

    // Clamp speed
    final speed = math.sqrt(vx * vx + vy * vy);
    if (speed > _maxSpeed) {
      final k = _maxSpeed / speed;
      vx *= k;
      vy *= k;
    }

    // Integrate position
    var x = bs.x + vx * dt;
    var y = bs.y + vy * dt;

    // Boundaries with simple "stop at edge"
    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);

    // If we hit edges, damp velocity a lot to avoid jittering at boundary
    if (x == 0.0 || x == 1.0) vx *= 0.2;
    if (y == 0.0 || y == 1.0) vy *= 0.2;

    // If inactive, fade velocity quicker
    final active = bs.active;
    if (!active) {
      vx *= 0.7;
      vy *= 0.7;
    }

    // Only notify if something changes meaningfully
    if ((x - bs.x).abs() > 1e-5 || (y - bs.y).abs() > 1e-5 || (vx - bs.vx).abs() > 1e-4 || (vy - bs.vy).abs() > 1e-4) {
      _ball.value = bs.copyWith(x: x, y: y, vx: vx, vy: vy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF0B0F1A))),
              ValueListenableBuilder<_BallState>(
                valueListenable: _ball,
                builder: (context, bs, _) {
                  final half = _ballSize / 2;

                  final minX = half;
                  final maxX = size.width - half;
                  final minY = half;
                  final maxY = size.height - half;

                  final cx = (minX + (maxX - minX) * bs.x).clamp(minX, maxX);
                  final cy = (minY + (maxY - minY) * bs.y).clamp(minY, maxY);

                  final opacity = bs.active ? 1.0 : 0.25;

                  return Positioned(
                    left: cx - half,
                    top: cy - half,
                    child: Opacity(
                      opacity: opacity,
                      child: const _Ball(size: _ballSize),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Ball extends StatelessWidget {
  final double size;
  const _Ball({required this.size});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              blurRadius: 7,
              offset: Offset(0, 2),
              color: Color(0x33000000),
            ),
          ],
        ),
      ),
    );
  }
}

class _BallState {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final bool active;

  const _BallState({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.active,
  });

  factory _BallState.center() => const _BallState(x: 0.5, y: 0.55, vx: 0, vy: 0, active: false);

  _BallState copyWith({double? x, double? y, double? vx, double? vy, bool? active}) {
    return _BallState(
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      active: active ?? this.active,
    );
  }
}
