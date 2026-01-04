import 'dart:async';
import 'package:flutter/material.dart';
import 'hand_input_bridge.dart';

/// Minimal demo page (macOS):
/// - Clean background
/// - Small movable ball
/// - Ball moves with x (0..1) and scales with pinch mapping
class HandBallPage extends StatefulWidget {
  const HandBallPage({super.key});

  @override
  State<HandBallPage> createState() => _HandBallPageState();
}

class _HandBallPageState extends State<HandBallPage> {
  static const double _ballBaseSize = 48; // smaller ball (36~56 is nice)

  final HandInputBridge _bridge = HandInputBridge.instance;

  late final ValueNotifier<HandInputState> _hand =
  ValueNotifier<HandInputState>(HandInputState.inactive());

  StreamSubscription<HandInputState>? _sub;

  @override
  void initState() {
    super.initState();

    // Start native camera/vision capture for this demo page.
    _bridge.start();

    // Only update notifier; avoid setState for whole page.
    _sub = _bridge.stream.listen((e) => _hand.value = e);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hand.dispose();

    // Release camera & close stream.
    _bridge.dispose();

    super.dispose();
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
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF0B0F1A)),
              ),

              ValueListenableBuilder<HandInputState>(
                valueListenable: _hand,
                builder: (context, hand, _) {
                  final scale = hand.scale;

                  // Scaled radius used for boundaries.
                  final halfScaled = (_ballBaseSize * scale) / 2;

                  final minX = halfScaled;
                  final maxX = size.width - halfScaled;

                  final cx = (minX + (maxX - minX) * hand.x).clamp(minX, maxX);
                  final cy = (size.height * 0.55)
                      .clamp(halfScaled, size.height - halfScaled);

                  // Show inactive state by lowering opacity (hand lost / low confidence).
                  final opacity = hand.active ? 1.0 : 0.25;

                  return Positioned(
                    left: cx - halfScaled,
                    top: cy - halfScaled,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(
                        scale: scale,
                        child: const _SimpleBall(size: _ballBaseSize),
                      ),
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

class _SimpleBall extends StatelessWidget {
  final double size;
  const _SimpleBall({required this.size});

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
              blurRadius: 10,
              spreadRadius: 0,
              offset: Offset(0, 2),
              color: Color(0x33000000),
            ),
          ],
        ),
      ),
    );
  }
}
