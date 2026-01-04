import 'dart:async';
import 'package:flutter/services.dart';

class HandDeltaState {
  final double dx;
  final double dy;
  final double confidence;
  final bool active;
  final DateTime ts;

  const HandDeltaState({
    required this.dx,
    required this.dy,
    required this.confidence,
    required this.active,
    required this.ts,
  });

  factory HandDeltaState.inactive() => HandDeltaState(
        dx: 0,
        dy: 0,
        confidence: 0,
        active: false,
        ts: DateTime.now(),
      );
}

class HandInputBridge {
  static const MethodChannel _ch = MethodChannel('hand_gesture/control');

  HandInputBridge._() {
    _wireOnce();
  }

  static final HandInputBridge instance = HandInputBridge._();

  final _ctrl = StreamController<HandDeltaState>.broadcast();
  Stream<HandDeltaState> get stream => _ctrl.stream;

  // Tuning
  static const double _minConf = 0.25;

  // If no deltas arrive for a while -> inactive
  static const Duration _inactiveAfter = Duration(milliseconds: 300);
  static const Duration _tickEvery = Duration(milliseconds: 60);

  bool _wired = false;
  bool _disposed = false;

  Timer? _tick;
  DateTime? _lastGood;

  bool _lastActive = false;

  void _wireOnce() {
    if (_wired) return;
    _wired = true;

    _ch.setMethodCallHandler((call) async {
      if (_disposed) return;

      if (call.method == 'handDelta') {
        final args = (call.arguments is Map) ? (call.arguments as Map) : const {};
        final dx = _toDouble(args['dx']);
        final dy = _toDouble(args['dy']);
        final conf = _toDouble(args['confidence']);

        if (dx == null || dy == null || conf == null) return;
        if (conf < _minConf) return;

        _lastGood = DateTime.now();

        _emit(HandDeltaState(
          dx: dx,
          dy: dy,
          confidence: conf.clamp(0.0, 1.0),
          active: true,
          ts: DateTime.now(),
        ));
      } else if (call.method == 'handLost') {
        _emit(HandDeltaState.inactive());
      }
    });

    _tick = Timer.periodic(_tickEvery, (_) {
      if (_disposed) return;
      final last = _lastGood;
      if (last == null) {
        if (_lastActive) _emit(HandDeltaState.inactive());
        return;
      }
      if (DateTime.now().difference(last) >= _inactiveAfter) {
        if (_lastActive) _emit(HandDeltaState.inactive());
      }
    });
  }

  Future<void> start() async {
    try { await _ch.invokeMethod('start'); } catch (_) {}
  }

  Future<void> stop() async {
    try { await _ch.invokeMethod('stop'); } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _tick?.cancel();
    _tick = null;
    await stop();
    await _ctrl.close();
  }

  void _emit(HandDeltaState s) {
    if (_disposed) return;
    _lastActive = s.active;
    _ctrl.add(s);
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
