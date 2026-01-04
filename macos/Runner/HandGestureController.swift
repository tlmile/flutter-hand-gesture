import Foundation
import AVFoundation
import Vision
import FlutterMacOS

/// macOS Camera + Vision hand tracking (Relative / trackpad-like).
///
/// Native -> Flutter (MethodChannel: "hand_gesture/control"):
///   - method: "handDelta"
///     args: { "dx": Double, "dy": Double, "confidence": Double }
///       dx/dy are *relative movement impulses* in normalized screen units per update.
///       Flutter integrates these deltas into a cursor/ball position with inertia.
///   - method: "handLost"
///     args: nil
///
/// Flutter -> Native:
///   - "start" / "stop"
final class HandGestureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Public

    func setChannel(_ c: FlutterMethodChannel) { self.channel = c }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        NSLog("[HandGesture] start()")
        ensurePermissionThenStart()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSLog("[HandGesture] stop()")
        session.stopRunning()
        resetTracking()
        emitHandLostIfNeeded(force: true)
    }

    // MARK: - Internals

    private var channel: FlutterMethodChannel?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "hand.gesture.video.queue")
    private let visionQueue = DispatchQueue(label: "hand.gesture.vision.queue")

    private var isRunning = false
    private var isSessionConfigured = false

    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    // ---- Relative control parameters (trackpad feel) ----

    /// Update rate. Higher feels more responsive (but more CPU).
    private var lastVisionTime: CFTimeInterval = 0
    private let visionInterval: CFTimeInterval = 1.0 / 30.0

    /// Confidence threshold to avoid noisy points.
    private let minIndexConfidence: VNConfidence = 0.40

    /// Deadzone: ignore tiny jitter.
    private let deadzone: CGFloat = 0.0022

    /// Clamp raw delta per frame to avoid spikes (camera glitches).
    private let maxRawDelta: CGFloat = 0.06

    /// Base sensitivity multiplier. Higher = faster cursor.
    private let baseGain: CGFloat = 2.2

    /// Acceleration: faster hand movement => more gain (mouse-like).
    /// gain = baseGain * (1 + accelK * speed^accelP)
    private let accelK: CGFloat = 3.0
    private let accelP: CGFloat = 0.60

    /// Smooth the delta a bit (but not too much).
    private let deltaEmaAlpha: CGFloat = 0.35

    /// When the tracker "reappears" after being lost, don't emit a huge delta.
    /// We require a few stable frames before emitting deltas.
    private let warmupFrames: Int = 2

    // ----------------------------------------------------

    // Coordinate transform
    private let invertX: Bool = false
    private let invertY: Bool = true // Vision is bottom-left, Flutter is top-left

    // State
    private var lastX: CGFloat?
    private var lastY: CGFloat?
    private var smDx: CGFloat?
    private var smDy: CGFloat?
    private var warmupLeft: Int = 0

    // Hand-lost detection
    private var lastHandSeenTime: CFTimeInterval = 0
    private let handLostAfter: CFTimeInterval = 0.35
    private var handWasActive = false

    // Log throttle
    private var lastLogTime: CFTimeInterval = 0

    private func resetTracking() {
        lastX = nil
        lastY = nil
        smDx = nil
        smDy = nil
        warmupLeft = 0
    }

    private func ensurePermissionThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
            session.startRunning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if granted {
                        self.configureSessionIfNeeded()
                        self.session.startRunning()
                    } else {
                        self.logThrottled("[HandGesture] ❌ camera permission denied")
                        self.emitHandLostIfNeeded(force: true)
                    }
                }
            }
        default:
            logThrottled("[HandGesture] ❌ camera permission not available (\(AVCaptureDevice.authorizationStatus(for: .video)))")
            emitHandLostIfNeeded(force: true)
        }
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true

        handPoseRequest.maximumHandCount = 1

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video) else {
            logThrottled("[HandGesture] ERROR: no camera device")
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            logThrottled("[HandGesture] ERROR: camera input \(error)")
            session.commitConfiguration()
            return
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        if let conn = output.connection(with: .video) {
            conn.isVideoMirrored = true
        }

        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard isRunning else { return }

        let now = CACurrentMediaTime()
        if now - lastVisionTime < visionInterval { return }
        lastVisionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        visionQueue.async { [weak self] in
            guard let self = self else { return }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([self.handPoseRequest])
            } catch {
                self.logThrottled("[HandGesture] Vision perform error: \(error)")
                self.emitHandLostIfNeeded()
                return
            }

            guard let obs = self.handPoseRequest.results?.first else {
                self.emitHandLostIfNeeded()
                return
            }

            guard
                let indexTip = try? obs.recognizedPoint(.indexTip),
                indexTip.confidence >= self.minIndexConfidence
            else {
                self.emitHandLostIfNeeded()
                return
            }

            self.lastHandSeenTime = now
            self.handWasActive = true

            var x = CGFloat(indexTip.location.x)
            var y = CGFloat(indexTip.location.y)

            if self.invertX { x = 1.0 - x }
            if self.invertY { y = 1.0 - y }

            x = self.clamp(x, 0, 1)
            y = self.clamp(y, 0, 1)

            // First frame after reacquire: initialize and warm up.
            if self.lastX == nil || self.lastY == nil {
                self.lastX = x
                self.lastY = y
                self.warmupLeft = self.warmupFrames
                return
            }

            let rawDx = x - (self.lastX ?? x)
            let rawDy = y - (self.lastY ?? y)
            self.lastX = x
            self.lastY = y

            if self.warmupLeft > 0 {
                self.warmupLeft -= 1
                return
            }

            // Deadzone
            var dx = abs(rawDx) < self.deadzone ? 0 : rawDx
            var dy = abs(rawDy) < self.deadzone ? 0 : rawDy

            // Clamp spikes
            dx = self.clamp(dx, -self.maxRawDelta, self.maxRawDelta)
            dy = self.clamp(dy, -self.maxRawDelta, self.maxRawDelta)

            // Smooth deltas
            self.smDx = self.ema(self.smDx, dx, self.deltaEmaAlpha)
            self.smDy = self.ema(self.smDy, dy, self.deltaEmaAlpha)

            let sdx = self.smDx ?? dx
            let sdy = self.smDy ?? dy

            // Mouse acceleration
            let speed = sqrt(sdx*sdx + sdy*sdy) // normalized per update
            let gain = self.baseGain * (1.0 + self.accelK * pow(speed, self.accelP))

            let outDx = sdx * gain
            let outDy = sdy * gain

            if outDx == 0 && outDy == 0 { return }

            let conf = CGFloat(indexTip.confidence)

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let ch = self.channel else { return }
                ch.invokeMethod("handDelta", arguments: [
                    "dx": Double(outDx),
                    "dy": Double(outDy),
                    "confidence": Double(self.clamp(conf, 0, 1)),
                ])
            }

            self.logThrottled(String(format: "[HandGesture] delta(%.4f,%.4f) speed=%.4f gain=%.2f conf=%.2f",
                                     Double(outDx), Double(outDy), Double(speed), Double(gain), Double(conf)))
        }
    }

    private func emitHandLostIfNeeded(force: Bool = false) {
        let now = CACurrentMediaTime()

        if force {
            if handWasActive {
                handWasActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.channel?.invokeMethod("handLost", arguments: nil)
                }
            }
            return
        }

        if !handWasActive { return }

        if now - lastHandSeenTime >= handLostAfter {
            handWasActive = false
            resetTracking()
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod("handLost", arguments: nil)
            }
            logThrottled("[HandGesture] handLost")
        }
    }

    private func ema(_ prev: CGFloat?, _ next: CGFloat, _ a: CGFloat) -> CGFloat {
        guard let p = prev else { return next }
        return p + a * (next - p)
    }

    private func clamp<T: Comparable>(_ v: T, _ a: T, _ b: T) -> T { min(max(v, a), b) }

    private func logThrottled(_ msg: String) {
        let now = CACurrentMediaTime()
        if now - lastLogTime > 0.8 {
            lastLogTime = now
            NSLog(msg)
        }
    }
}
