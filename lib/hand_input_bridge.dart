import 'dart:async';
import 'package:flutter/services.dart';

/// Semantic hand input state delivered to Flutter UI.
///
/// - x: 0..1 (left..right)
/// - scale: recommended 0.7..1.7
/// - confidence: 0..1
/// - active: whether we are currently receiving usable hand data
class HandInputState {
  final double x;
  final double scale;
  final double confidence;
  final bool active;
  final DateTime ts;

  const HandInputState({
    required this.x,
    required this.scale,
    required this.confidence,
    required this.active,
    required this.ts,
  });

  factory HandInputState.inactive() => HandInputState(
    x: 0.5,
    scale: 1.0,
    confidence: 0.0,
    active: false,
    ts: DateTime.now(),
  );

  HandInputState copyWith({
    double? x,
    double? scale,
    double? confidence,
    bool? active,
    DateTime? ts,
  }) {
    return HandInputState(
      x: x ?? this.x,
      scale: scale ?? this.scale,
      confidence: confidence ?? this.confidence,
      active: active ?? this.active,
      ts: ts ?? this.ts,
    );
  }
}

/// Bridges macOS native Vision hand pose -> Flutter.
///
/// Native sends:
///   method: "handPose"
///   args: { "x": Double, "scale": Double, "confidence": Double }
///
/// Control methods to native:
///   start / stop
class HandInputBridge {
  static const MethodChannel _ch = MethodChannel('hand_gesture/control');

  HandInputBridge._() {
    _wireChannelOnce();
  }

  static final HandInputBridge instance = HandInputBridge._();

  final StreamController<HandInputState> _ctrl =
  StreamController<HandInputState>.broadcast();

  Stream<HandInputState> get stream => _ctrl.stream;

  // ---- config ----
  static const double _minConf = 0.25;

  // Clamp range from native
  static const double _scaleMin = 0.70;
  static const double _scaleMax = 1.70;

  // EMA smoothing (0..1). Larger => follow faster, smaller => smoother.
  static const double _alphaPos = 0.25;
  static const double _alphaScale = 0.18;

  // Inactivity timeout: if no good frame arrives, emit inactive once.
  static const Duration _inactiveAfter = Duration(milliseconds: 250);
  static const Duration _tickEvery = Duration(milliseconds: 60);

  // ---- internal state ----
  bool _wired = false;
  bool _disposed = false;

  Timer? _tickTimer;
  DateTime? _lastGoodFrameAt;

  // smoothed outputs
  double? _sx;
  double? _ss;

  // last emitted active flag (to avoid spamming)
  bool _lastActive = false;

  void _wireChannelOnce() {
    if (_wired) return;
    _wired = true;

    _ch.setMethodCallHandler((call) async {
      if (_disposed) return;

      if (call.method == 'handPose') {
        final args = (call.arguments is Map) ? (call.arguments as Map) : const {};
        final x = _toDouble(args['x']);
        final scale = _toDouble(args['scale']);
        final conf = _toDouble(args['confidence']);

        if (x == null || scale == null || conf == null) return;

        if (conf < _minConf) {
          // Treat as not-good; let inactivity timer handle active=false.
          return;
        }

        _lastGoodFrameAt = DateTime.now();

        final nx = _clamp(x, 0.0, 1.0);
        final ns = _clamp(scale, _scaleMin, _scaleMax);

        _sx = _ema(_sx, nx, _alphaPos);
        _ss = _ema(_ss, ns, _alphaScale);

        _emit(
          HandInputState(
            x: _sx ?? nx,
            scale: _ss ?? ns,
            confidence: _clamp(conf, 0.0, 1.0),
            active: true,
            ts: DateTime.now(),
          ),
        );
      } else if (call.method == 'handLost') {
        // Optional: if native side later implements this event.
        _emit(HandInputState.inactive());
      }
    });

    _tickTimer = Timer.periodic(_tickEvery, (_) {
      if (_disposed) return;

      final last = _lastGoodFrameAt;
      if (last == null) {
        if (_lastActive) _emit(HandInputState.inactive());
        return;
      }

      final diff = DateTime.now().difference(last);
      if (diff >= _inactiveAfter) {
        if (_lastActive) _emit(HandInputState.inactive());
      }
    });
  }

  Future<void> start() async {
    try {
      await _ch.invokeMethod('start');
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  /// Stop native capture and close the stream.
  ///
  /// Call this from page-level dispose (demo), or from app shutdown if you use it globally.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _tickTimer?.cancel();
    _tickTimer = null;

    await stop();
    await _ctrl.close();
  }

  void _emit(HandInputState s) {
    if (_disposed) return;
    _lastActive = s.active;
    _ctrl.add(s);
  }

  static double _ema(double? prev, double next, double a) {
    if (prev == null) return next;
    return prev + a * (next - prev);
  }

  static double _clamp(double v, double lo, double hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
