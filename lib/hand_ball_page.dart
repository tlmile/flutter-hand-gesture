import 'dart:ui';
import 'package:flutter/material.dart';

class HandBallPage extends StatefulWidget {
  const HandBallPage({super.key});

  @override
  State<HandBallPage> createState() => _HandBallPageState();
}

class _HandBallPageState extends State<HandBallPage> {
  // 你要小一点：180~210 都好看，这里取 190
  static const double ballSize = 190;

  Offset _center = const Offset(280, 320);
  Offset _dragStartLocal = Offset.zero;
  Offset _centerAtDragStart = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final Size size = Size(constraints.maxWidth, constraints.maxHeight);
          final double half = ballSize / 2;

          // clamp：保证球不会被拖出屏幕
          final double cx = _center.dx.clamp(half, size.width - half);
          final double cy = _center.dy.clamp(half, size.height - half);
          final Offset clampedCenter = Offset(cx, cy);

          // resize 后自动修正
          if (clampedCenter != _center) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _center = clampedCenter);
            });
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              const _NebulaBackground(),

              // 轻微“星尘划痕”高光层，增强氛围（无图片）
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
                left: clampedCenter.dx - half,
                top: clampedCenter.dy - half,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) {
                    _dragStartLocal = details.localPosition;
                    _centerAtDragStart = clampedCenter;
                  },
                  onPanUpdate: (details) {
                    final Offset delta = details.localPosition - _dragStartLocal;
                    final Offset next = _centerAtDragStart + delta;

                    final double nx = next.dx.clamp(half, size.width - half);
                    final double ny = next.dy.clamp(half, size.height - half);

                    setState(() => _center = Offset(nx, ny));
                  },
                  child: const _RealGlassBall(size: ballSize),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 无图片星云背景：冷暗 + 星点
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

/// 真实球面感：
/// - 大面积白雾
/// - 小深蓝内核
/// - 外圈白环 + 内细环
/// - 内阴影（inner shadow）
/// - 顶部弧形反光（specular highlight arc）
/// - 磨砂玻璃 blur
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
          // 外部浮影：让球“浮在”背景上
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
                  // ===== Layer A：基底（小深蓝内核 + 过渡）=====
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0.0, 0.18),
                        radius: 1.0,
                        colors: [
                          const Color(0xFF071A35).withOpacity(0.96), // 内核
                          const Color(0xFF0E2B55).withOpacity(0.78), // 过渡
                          Colors.white.withOpacity(0.28),           // 外侧开始偏白
                        ],
                        // 内核更小：越小越接近参考图
                        stops: const [0.0, 0.22, 1.0],
                      ),
                    ),
                  ),

                  // ===== Layer B：大面积白雾（关键：白区域占很大）=====
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0.0, 0.10),
                        radius: 1.0,
                        colors: [
                          Colors.transparent,              // 让内核透出来
                          Colors.white.withOpacity(0.18),  // 很靠近中心就开始起雾
                          Colors.white.withOpacity(0.36),
                          Colors.white.withOpacity(0.60),  // 外侧大面积偏白
                        ],
                        // 白雾从 0.18 开始明显出现（更像参考图）
                        stops: const [0.0, 0.18, 0.48, 1.0],
                      ),
                    ),
                  ),

                  // ===== Layer C：边缘更厚更亮的雾圈 =====
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
                        // 往内推：让“偏白边缘”更宽
                        stops: const [0.52, 0.74, 1.0],
                      ),
                    ),
                  ),

                  // ===== Layer D：内阴影（inner shadow）=====
                  // 通过在边缘叠加一层“暗化环”实现内阴影，增强球面厚度
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

                  // ===== Layer E：顶部弧形反光（真实感关键）=====
                  // 用 CustomPaint 画一条弧形高光 + 微弱次高光
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _SpecularArcPainter(),
                    ),
                  ),

                  // ===== Layer F：局部高光（玻璃漫反射）=====
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

                  // ===== 外圈白环 =====
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 7,
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                  ),

                  // ===== 内圈细环（增加厚度与层次）=====
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

/// 顶部弧形高光 painter：
/// 画两条弧线（主高光 + 次高光），更像玻璃球“镜面反射”
class _SpecularArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // 主高光弧：更亮、更细
    final mainPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.06
      ..color = Colors.white.withOpacity(0.16);

    // 次高光弧：更淡、更宽一点点
    final subPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.10
      ..color = Colors.white.withOpacity(0.06);

    // 弧形矩形区域（略小于圆，避免顶到边框）
    final rectMain = Rect.fromCircle(center: Offset(cx, cy - r * 0.10), radius: r * 0.78);
    final rectSub = Rect.fromCircle(center: Offset(cx, cy - r * 0.08), radius: r * 0.82);

    // 角度：从左上到右上（可微调更像参考图）
    final start = 3.55; // ~203°
    final sweep = 1.15; // ~66°

    canvas.drawArc(rectSub, start, sweep, false, subPaint);
    canvas.drawArc(rectMain, start + 0.06, sweep - 0.08, false, mainPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 固定星点，避免闪烁
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
      final r = (i % 3 + 1).toDouble();
      paint.color = Colors.white.withOpacity(0.07 + (i % 6) * 0.035);
      canvas.drawCircle(p, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
