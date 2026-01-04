import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as three;

/// A full-screen page that renders a WebGL powered 3D Christmas tree
/// using flutter_gl + three_dart. All rendering happens inside Flutter
/// without relying on a WebView.
class ChristmasTree3DPage extends StatefulWidget {
  const ChristmasTree3DPage({super.key});

  @override
  State<ChristmasTree3DPage> createState() => _ChristmasTree3DPageState();
}

class _ChristmasTree3DPageState extends State<ChristmasTree3DPage>
    with SingleTickerProviderStateMixin {
  FlutterGlPlugin? _glPlugin;
  three.WebGLRenderer? _renderer;
  late three.Scene _scene;
  late three.PerspectiveCamera _camera;
  three.WebGLRenderTarget? _renderTarget;

  late Ticker _ticker;
  Duration _lastTime = Duration.zero;
  double _elapsedSeconds = 0.0;

  // View configuration
  double _width = 1;
  double _height = 1;
  double _dpr = 1.0;

  // Orbit state
  double _yaw = 0;
  double _pitch = 0.35;
  double _distance = 9.5;
  double _yawVelocity = 0;
  double _pitchVelocity = 0;
  double _zoomVelocity = 0;

  // Particles & decorations
  final List<_BlinkingBulb> _bulbs = [];
  three.Points? _snowPoints;
  late List<double> _snowSpeeds;
  final math.Random _rand = math.Random();

  // Gesture helpers
  double _lastScale = 1.0;
  bool _isReady = false;
  bool _isInitializing = false;

  three.Color _colorFromHex(int hex) {
    final r = ((hex >> 16) & 0xFF) / 255;
    final g = ((hex >> 8) & 0xFF) / 255;
    final b = (hex & 0xFF) / 255;
    return three.Color(r, g, b);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _renderer?.dispose();
    _renderTarget?.dispose();
    _glPlugin?.dispose();
    super.dispose();
  }

  Future<void> _initRenderer() async {
    if (_isInitializing || _isReady) return;
    _isInitializing = true;

    final size = MediaQuery.sizeOf(context);
    _width = size.width;
    _height = size.height;
    _dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);

    _glPlugin = FlutterGlPlugin();
    await _glPlugin!.initialize(options: {
      'antialias': true,
      'alpha': false,
      'width': (_width * _dpr).toInt(),
      'height': (_height * _dpr).toInt(),
      'dpr': _dpr,
    });

    await _glPlugin!.prepareContext();

    _renderer = three.WebGLRenderer({
      'gl': _glPlugin!.gl,
      'canvas': _glPlugin!.element,
      'antialias': true,
      'alpha': false,
    });
    _renderer!.setPixelRatio(_dpr);
    _renderer!.setSize(_width, _height, false);

    // Offscreen render target for mobile; updated into Flutter texture
    _renderTarget = three.WebGLRenderTarget(
      (_width * _dpr).toInt(),
      (_height * _dpr).toInt(),
      three.WebGLRenderTargetOptions({
        'samples': 4,
        'format': three.RGBAFormat,
      }),
    );
    _renderer!.setRenderTarget(_renderTarget);

    _setupScene();
    setState(() {
      _isReady = true;
      _isInitializing = false;
    });
  }

  void _setupScene() {
    _scene = three.Scene();
    _scene.background = _colorFromHex(0x000000);

    _camera = three.PerspectiveCamera(60, _width / _height, 0.1, 1000);
    _camera.position.set(0, 2.5, _distance);

    _scene.add(three.AmbientLight(_colorFromHex(0x404040), 1.2));
    final dirLight = three.DirectionalLight(_colorFromHex(0xffffff), 1.3);
    dirLight.position.set(5, 10, 7);
    dirLight.castShadow = true;
    _scene.add(dirLight);

    _buildGround();
    _buildTree();
    _buildGarland();
    _buildSnow();
  }

  void _buildGround() {
    final groundGeom = three.CircleGeometry(radius: 6, segments: 40);
    final groundMat = three.MeshPhongMaterial({
      'color': _colorFromHex(0x0f0f14),
      'emissive': _colorFromHex(0x070708),
      'side': three.DoubleSide,
    });
    final ground = three.Mesh(groundGeom, groundMat)
      ..rotation.x = -math.pi / 2
      ..position.y = -1.4;
    _scene.add(ground);
  }

  void _buildTree() {
    final treeGroup = three.Group();
    const levels = 3;
    for (int i = 0; i < levels; i++) {
      final radius = 2.3 - i * 0.5;
      final height = 2.6 - i * 0.3;
      final y = i * 0.9;
      final geometry = three.ConeGeometry(radius, height, 40, 12);
      final material = three.MeshStandardMaterial({
        'color': _colorFromHex(0x0c5f2d),
        'roughness': 0.45,
        'metalness': 0.1,
      });
      final mesh = three.Mesh(geometry, material)..position.y = y;
      treeGroup.add(mesh);
    }

    final trunk = three.Mesh(
      three.CylinderGeometry(0.4, 0.5, 1.4, 24),
      three.MeshStandardMaterial({
        'color': _colorFromHex(0x6a4b2c),
        'roughness': 0.9,
      }),
    )..position.y = -1.1;
    treeGroup.add(trunk);

    final star = three.Mesh(
      three.IcosahedronGeometry(0.5, 0),
      three.MeshStandardMaterial({
        'color': _colorFromHex(0xffe189),
        'emissive': _colorFromHex(0xffe189),
        'emissiveIntensity': 1.5,
        'metalness': 0.35,
        'roughness': 0.25,
      }),
    )
      ..position.y = 2.8
      ..rotation.y = math.pi / 4;
    treeGroup.add(star);

    _scene.add(treeGroup);
  }

  void _buildGarland() {
    const bulbCount = 120;
    const turns = 4.5;
    final colors = [
      _colorFromHex(0xff4757),
      _colorFromHex(0x5f9dff),
      _colorFromHex(0xffe45b),
      _colorFromHex(0xce7bff),
    ];

    for (int i = 0; i < bulbCount; i++) {
      final t = i / bulbCount;
      final angle = turns * 2 * math.pi * t;
      final height = -0.6 + t * 2.4;
      final radius = 2.2 - t * 1.4;
      final x = math.cos(angle) * radius;
      final z = math.sin(angle) * radius;
      final color = colors[_rand.nextInt(colors.length)];
      final bulb = three.Mesh(
        three.SphereGeometry(0.08, 14, 14),
        three.MeshStandardMaterial({
          'color': color,
          'emissive': color,
          'emissiveIntensity': 0.9,
          'roughness': 0.2,
        }),
      );
      bulb.position.set(x, height + 0.4, z);
      _scene.add(bulb);
      _bulbs.add(_BlinkingBulb(
        mesh: bulb,
        phase: _rand.nextDouble() * math.pi * 2,
        speed: 0.8 + _rand.nextDouble() * 1.2,
      ));
    }
  }

  void _buildSnow() {
    const count = 380;
    final positions = <double>[];
    _snowSpeeds = List<double>.generate(count, (_) => 0.6 + _rand.nextDouble() * 0.8);
    for (int i = 0; i < count; i++) {
      positions.add((_rand.nextDouble() - 0.5) * 10.0);
      positions.add(_rand.nextDouble() * 8.0 + 1.0);
      positions.add((_rand.nextDouble() - 0.5) * 10.0);
    }

    final geometry = three.BufferGeometry();
    geometry.setAttribute(
      'position',
      three.Float32BufferAttribute(three.Float32Array.from(positions), 3),
    );
    geometry.attributes['position']!.needsUpdate = true;
    final material = three.PointsMaterial({
      'color': _colorFromHex(0xffffff),
      'size': 0.06,
      'transparent': true,
      'opacity': 0.8,
      'depthWrite': false,
      'sizeAttenuation': true,
    });
    _snowPoints = three.Points(geometry, material);
    _scene.add(_snowPoints!);
  }

  void _updateSnow(double dt) {
    final positionsAttr = _snowPoints?.geometry?.getAttribute('position');
    if (positionsAttr == null) return;
    final array = positionsAttr.array as List<double>;
    for (int i = 0; i < _snowSpeeds.length; i++) {
      final index = i * 3 + 1;
      array[index] -= _snowSpeeds[i] * dt;
      if (array[index] < -1.6) {
        array[index] = _rand.nextDouble() * 7.0 + 2.0;
        array[index - 1] = (_rand.nextDouble() - 0.5) * 8.0;
        array[index + 1] = (_rand.nextDouble() - 0.5) * 8.0;
      }
    }
    positionsAttr.needsUpdate = true;
  }

  void _updateGarland(double dt) {
    for (final bulb in _bulbs) {
      final phase = bulb.phase + _elapsedSeconds * bulb.speed;
      final intensity = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(phase));
      final mat = bulb.mesh.material as three.MeshStandardMaterial;
      mat.emissiveIntensity = intensity;
      mat.needsUpdate = true;
    }
  }

  void _updateCamera(double dt) {
    // Apply inertial motion
    _yaw += _yawVelocity * dt;
    _pitch += _pitchVelocity * dt;
    _pitch = _pitch.clamp(-1.1, 1.1);
    _distance = (_distance + _zoomVelocity * dt * 18).clamp(4.0, 14.0);

    // Friction
    final rotationDrag = math.pow(0.9, dt * 60).toDouble();
    final zoomDrag = math.pow(0.8, dt * 60).toDouble();
    _yawVelocity *= rotationDrag;
    _pitchVelocity *= rotationDrag;
    _zoomVelocity *= zoomDrag;

    final x = _distance * math.cos(_pitch) * math.sin(_yaw);
    final y = _distance * math.sin(_pitch) + 1.2;
    final z = _distance * math.cos(_pitch) * math.cos(_yaw);
    _camera.position.set(x, y, z);
    _camera.lookAt(three.Vector3(0, 0.6, 0));
  }

  void _renderScene() {
    _renderer?.render(_scene, _camera);
    _glPlugin?.gl.flush();
    if (_renderTarget != null && _glPlugin != null) {
      _glPlugin!.updateTexture(_renderTarget!.texture);
    }
  }

  void _onTick(Duration elapsed) {
    if (!_isReady) return;
    if (_lastTime == Duration.zero) {
      _lastTime = elapsed;
      return;
    }
    final dt = (elapsed - _lastTime).inMicroseconds / 1e6;
    _lastTime = elapsed;
    _elapsedSeconds += dt;
    _updateCamera(dt);
    _updateGarland(dt);
    _updateSnow(dt);
    _renderScene();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 1) {
      _yawVelocity += details.focalPointDelta.dx * 0.0025;
      _pitchVelocity += details.focalPointDelta.dy * 0.0025;
    } else {
      final deltaScale = details.scale - _lastScale;
      _zoomVelocity -= deltaScale * 8.0;
      _lastScale = details.scale;
    }
  }

  /// Public control entry for external gesture/ML pipelines.
  /// dx/dy: relative rotation input (-1..1), zoom: zoom delta, conf: 0..1 confidence.
  void applyControl({
    required double dx,
    required double dy,
    required double zoom,
    required double conf,
  }) {
    final c = conf.clamp(0.0, 1.0);
    final gain = 0.05 * c;
    _yawVelocity += dx * gain;
    _pitchVelocity += dy * gain;
    _zoomVelocity -= zoom * (10 * c);
    if (c < 0.15) {
      _yawVelocity *= 0.92;
      _pitchVelocity *= 0.92;
      _zoomVelocity *= 0.85;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (!_isReady) {
            // Delay initialization until we have layout constraints.
            _initRenderer();
            return const Center(child: CircularProgressIndicator());
          }
          return GestureDetector(
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            child: Container(
              color: Colors.black,
              child: Texture(textureId: _glPlugin!.textureId!),
            ),
          );
        },
      ),
    );
  }
}

class _BlinkingBulb {
  _BlinkingBulb({required this.mesh, required this.phase, required this.speed});

  final three.Mesh mesh;
  final double phase;
  final double speed;
}
