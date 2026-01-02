import Foundation
import AVFoundation
import Vision
import FlutterMacOS

/// Camera + Vision hand tracking:
/// - indexTip.x -> xNorm (0..1)
/// - distance(indexTip, thumbTip) -> scale
/// Sends to Flutter via MethodChannel:
///   method: "handPose"
///   args: { "x": Double, "scale": Double, "confidence": Double }
final class HandGestureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private var channel: FlutterMethodChannel?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "hand.gesture.video.queue")
    private let visionQueue = DispatchQueue(label: "hand.gesture.vision.queue")

    private var isRunning = false

    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    // Throttle Vision to reduce CPU load
    private var lastVisionTime: CFTimeInterval = 0
    private let visionInterval: CFTimeInterval = 1.0 / 12.0 // ~12fps

    // Pinch normalization & scale mapping (tweak to taste)
    private var pinchMin: CGFloat = 0.02   // near pinch
    private var pinchMax: CGFloat = 0.18   // open
    private var scaleMin: CGFloat = 0.70
    private var scaleMax: CGFloat = 1.70

    // Log throttle
    private var lastLogTime: CFTimeInterval = 0

    func setChannel(_ c: FlutterMethodChannel) {
        self.channel = c
    }

    func start() {
        if isRunning { return }
        isRunning = true

        NSLog("[HandGesture] start()")

        handPoseRequest.maximumHandCount = 1

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video) else {
            NSLog("[HandGesture] ERROR: no camera device")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            NSLog("[HandGesture] ERROR: camera input \(error)")
            return
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        // Mirror so the user feels natural left-right mapping.
        if let conn = output.connection(with: .video) {
            conn.isVideoMirrored = true
        }

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        if !isRunning { return }
        isRunning = false
        NSLog("[HandGesture] stop()")
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

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
                return
            }

            guard let obs = self.handPoseRequest.results?.first else {
                self.logThrottled("[HandGesture] no hand detected")
                return
            }

            guard
                let indexTip = try? obs.recognizedPoint(.indexTip),
                let thumbTip = try? obs.recognizedPoint(.thumbTip),
                indexTip.confidence > 0.2
            else {
                self.logThrottled("[HandGesture] keypoints missing/low confidence")
                return
            }

            // Normalized coordinates: 0..1
            var xNorm = CGFloat(indexTip.location.x)

            // If you find left-right inverted, toggle this:
            // xNorm = 1.0 - xNorm

            let dx = indexTip.location.x - thumbTip.location.x
            let dy = indexTip.location.y - thumbTip.location.y
            let pinch = sqrt(dx*dx + dy*dy)

            let p = self.clamp((pinch - self.pinchMin) / (self.pinchMax - self.pinchMin), 0, 1)
            let scale = self.scaleMin + (self.scaleMax - self.scaleMin) * p
            let conf = CGFloat(indexTip.confidence)

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let ch = self.channel else { return }
                ch.invokeMethod("handPose", arguments: [
                    "x": Double(self.clamp(xNorm, 0, 1)),
                    "scale": Double(self.clamp(scale, self.scaleMin, self.scaleMax)),
                    "confidence": Double(self.clamp(conf, 0, 1)),
                ])
            }

            self.logThrottled(String(format: "[HandGesture] x=%.3f pinch=%.3f scale=%.2f conf=%.2f",
                                     Double(xNorm), Double(pinch), Double(scale), Double(conf)))
        }
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
