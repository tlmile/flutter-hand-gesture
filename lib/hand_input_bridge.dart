import 'dart:async';
import 'package:flutter/services.dart';

class HandPoseData {
  /// 0..1 (left..right)
  final double x;

  /// Recommended range: 0.7..1.7 (Flutter will clamp/smooth)
  final double scale;

  /// 0..1
  final double confidence;

  const HandPoseData({
    required this.x,
    required this.scale,
    required this.confidence,
  });

  factory HandPoseData.fromMap(Map<dynamic, dynamic> m) {
    double toD(dynamic v, double def) {
      if (v is num) return v.toDouble();
      return def;
    }

    return HandPoseData(
      x: toD(m['x'], 0.5).clamp(0.0, 1.0),
      scale: toD(m['scale'], 1.0).clamp(0.3, 3.0),
      confidence: toD(m['confidence'], 0.0).clamp(0.0, 1.0),
    );
  }
}

class HandInputBridge {
  static const MethodChannel _ch = MethodChannel('hand_gesture/control');

  final StreamController<HandPoseData> _ctrl = StreamController.broadcast();
  Stream<HandPoseData> get stream => _ctrl.stream;

  Future<void> start() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'handPose') {
        final args = (call.arguments as Map?) ?? {};
        _ctrl.add(HandPoseData.fromMap(args));
      }
    });

    // Optional: ask native side to start.
    try {
      await _ch.invokeMethod('start');
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  void dispose() {
    _ctrl.close();
  }
}
