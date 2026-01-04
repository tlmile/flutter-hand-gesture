import Foundation
import FlutterMacOS

final class HandGestureService {
    static let shared = HandGestureService()

    private let controller = HandGestureController()
    private var isWired = false

    private init() {}

    func wireIfNeeded(binaryMessenger: FlutterBinaryMessenger) {
        guard !isWired else { return }
        isWired = true

        let channel = FlutterMethodChannel(
            name: "hand_gesture/control",
            binaryMessenger: binaryMessenger
        )

        controller.setChannel(channel)

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "start":
                self.controller.start()
                result(true)
            case "stop":
                self.controller.stop()
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        NSLog("✅ HandGestureService wired (relative mode; waiting for Flutter start)")
    }
}
