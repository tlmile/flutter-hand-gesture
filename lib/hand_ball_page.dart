import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'hand_input_bridge.dart';

class HandBallPage extends StatefulWidget {
  const HandBallPage({super.key});

  @override
  State<HandBallPage> createState() => _HandBallPageState();
}

class _HandBallPageState extends State<HandBallPage> {
  // Ball base size (before Transform.scale).
  static const double ballSize = 190;

  final HandInputBridge _bridge = HandInputBridge();
  StreamSubscription<HandPoseData>? _sub;

  // Smoothed hand-driven state.
  double _xNorm = 0.5; // 0..1
  double _scale = 1.0;

  // EMA smoothing factors: bigger = more responsive, smaller = smoother.
  static const double _alphaPos = 0.22;
  static const double _alphaScale = 0.18;

  static const double _minConfidence = 0.25;

  // Scale range to use in UI.
  static const double _minScale = 0.70;
  static const double _maxScale = 1.70;

  // Debug: enable dragging fallback to compare.
  bool _dragFallback = false;

  // Drag fallback state.
  Offset _center = const Offset(280, 320);
  Offset _dragStartLocal = Offset.zero;
  Offset _centerAtDragStart = Offset.zero;

  @override
  void initState() {
    super.initState();

    _bridge.start();

    _sub = _bridge.stream.listen((data) {
      if (data.confidence < _minConfidence) return;

      final nx = _xNorm * (1 - _alphaPos) + data.x * _alphaPos;

      final targetScale = data.scale.clamp(_minScale, _maxScale);
      final ns = _scale * (1 - _alphaScale) + targetScale * _alphaScale;

      setState(() {
        _xNorm = nx.clamp(0.0, 1.0);
        _scale = ns.clamp(_minScale, _maxScale);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double base = ballSize;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final Size size = Size(constraints.maxWidth, constraints.maxHeight);

          // Map xNorm (0..1) to usable x range, considering scaled ball.
          final double halfScaled = (base * _scale) / 2;
          final double minX = halfScaled;
          final double maxX = size.width - halfScaled;
          final double cxFromHand = minX + (maxX - minX) * _xNorm;

          // Keep Y at a pleasant height (or make it driven by hand later).
          final double cyFromHand = size.height * 0.55;
          final Offset handCenter = Offset(cxFromHand, cyFromHand);

          // Choose center.
          final Offset centerToUse = _dragFallback ? _center : handCenter;

          // Clamp to screen.
          final double cx = centerToUse.dx.clamp(halfScaled, size.width - halfScaled);
          final double cy = centerToUse.dy.clamp(halfScaled, size.height - halfScaled);
          final Offset clamped = Offset(cx, cy);

          // If resizing makes drag center out-of-bounds, auto-correct.
          if (_dragFallback && clamped != _center) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _center = clamped);
            });
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              const _NebulaBackground(),

              // Ambient streak highlight (subtle)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.05),
                        Colors.transparent,
                        Colors.white.withOpacity(0.03),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.35, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              Positioned(
                left: clamped.dx - halfScaled,
                top: clamped.dy - halfScaled,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: !_dragFallback
                      ? null
                      : (details) {
                          _dragStartLocal = details.localPosition;
                          _centerAtDragStart = clamped;
                        },
                  onPanUpdate: !_dragFallback
                      ? null
                      : (details) {
                          final delta = details.localPosition - _dragStartLocal;
                          setState(() => _center = _centerAtDragStart + delta);
                        },
                  child: Transform.scale(
                    scale: _scale,
                    child: const _RealGlassBall(size: base),
                  ),
                ),
              ),

              // Small switch for debug
              Positioned(
                left: 18,
                top: 16,
                child: Row(
                  children: [
                    Switch(
                      value: _dragFallback,
                      onChanged: (v) => setState(() => _dragFallback = v),
                    ),
                    const Text(
                      'Drag fallback',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// No-image nebula background.
class _NebulaBackground extends StatelessWidget {
  const _NebulaBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.25, -0.45),
          radius: 1.35,
          colors: [
            Color(0xFF1B2A57),
            Color(0xFF0B1020),
            Color(0xFF05070F),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _StarPainter(),
              size: Size.infinite,
            ),
          ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 260,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Realistic glass ball:
/// - big milky white area
/// - small dark core
/// - bright rim
/// - inner shadow
/// - specular arc reflection
/// - frosted blur
class _RealGlassBall extends StatelessWidget {
  final double size;
  const _RealGlassBall({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Outer floating shadow
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  blurRadius: 65,
                  spreadRadius: 10,
                  offset: const Offset(0, 34),
                  color: Colors.black.withOpacity(0.42),
                ),
              ],
            ),
          ),

          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Layer A: base core + transition
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0.0, 0.18),
                        radius: 1.0,
                        colors: [
                          const Color(0xFF071A35).withOpacity(0.96),
                          const Color(0xFF0E2B55).withOpacity(0.78),
                          Colors.white.withOpacity(0.28),
                        ],
                        stops: const [0.0, 0.22, 1.0],
                      ),
                    ),
                  ),

                  // Layer B: big milky fog (the key)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0.0, 0.10),
                        radius: 1.0,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.18),
                          Colors.white.withOpacity(0.36),
                          Colors.white.withOpacity(0.60),
                        ],
                        stops: const [0.0, 0.18, 0.48, 1.0],
                      ),
                    ),
                  ),

                  // Layer C: thicker bright edge fog
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        radius: 0.98,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.10),
                          Colors.white.withOpacity(0.22),
                        ],
                        stops: const [0.52, 0.74, 1.0],
                      ),
                    ),
                  ),

                  // Layer D: inner shadow ring (adds thickness)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        radius: 1.0,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.08),
                          Colors.black.withOpacity(0.16),
                        ],
                        stops: const [0.70, 0.88, 1.0],
                      ),
                    ),
                  ),

                  // Layer E: specular reflection arc (realism key)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _SpecularArcPainter(),
                    ),
                  ),

                  // Layer F: soft highlight blob
                  Align(
                    alignment: const Alignment(-0.25, -0.40),
                    child: Container(
                      width: size * 0.68,
                      height: size * 0.68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.22),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.80],
                        ),
                      ),
                    ),
                  ),

                  // Outer rim
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 7,
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                  ),

                  // Inner thin ring
                  Padding(
                    padding: const EdgeInsets.all(9),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2,
                          color: Colors.white.withOpacity(0.32),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Specular arc reflection (two arcs).
class _SpecularArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.06
      ..color = Colors.white.withOpacity(0.16);

    final subPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.10
      ..color = Colors.white.withOpacity(0.06);

    final rectMain = Rect.fromCircle(center: Offset(cx, cy - r * 0.10), radius: r * 0.78);
    final rectSub = Rect.fromCircle(center: Offset(cx, cy - r * 0.08), radius: r * 0.82);

    final start = 3.55; // ~203°
    final sweep = 1.15; // ~66°

    canvas.drawArc(rectSub, start, sweep, false, subPaint);
    canvas.drawArc(rectMain, start + 0.06, sweep - 0.08, false, mainPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fixed stars to avoid flicker.
class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final stars = <Offset>[
      Offset(size.width * 0.10, size.height * 0.18),
      Offset(size.width * 0.22, size.height * 0.35),
      Offset(size.width * 0.38, size.height * 0.12),
      Offset(size.width * 0.55, size.height * 0.24),
      Offset(size.width * 0.72, size.height * 0.30),
      Offset(size.width * 0.86, size.height * 0.16),
      Offset(size.width * 0.64, size.height * 0.54),
      Offset(size.width * 0.28, size.height * 0.62),
      Offset(size.width * 0.14, size.height * 0.78),
      Offset(size.width * 0.72, size.height * 0.82),
      Offset(size.width * 0.90, size.height * 0.64),
      Offset(size.width * 0.45, size.height * 0.72),
      Offset(size.width * 0.06, size.height * 0.52),
      Offset(size.width * 0.96, size.height * 0.42),
    ];

    for (int i = 0; i < stars.length; i++) {
      final p = stars[i];
      final rr = (i % 3 + 1).toDouble();
      paint.color = Colors.white.withOpacity(0.07 + (i % 6) * 0.035);
      canvas.drawCircle(p, rr, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
