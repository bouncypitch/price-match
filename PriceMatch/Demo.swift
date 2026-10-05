import UIKit

/// Simulator-only demo for recording a how-to video. Compiled out of release builds.
/// Launch with the `-demoMode` argument, plus environment variables:
///   DEMO_SERPAPI_KEY     price service key to install
///   DEMO_CAMERA_IMAGE    path to a picture shown where the camera would be
///   DEMO_BARCODE         barcode the demo "scans" and later types in
///   DEMO_CAMERA_IMAGE2 / DEMO_BARCODE2   optional second item to scan
enum Demo {
    static var isOn: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demoMode")
        #else
        return false
        #endif
    }

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Picture for the first or second item (DEMO_CAMERA_IMAGE / DEMO_CAMERA_IMAGE2).
    static func cameraImage(item: Int) -> UIImage? {
        guard isOn, let path = env[item == 1 ? "DEMO_CAMERA_IMAGE" : "DEMO_CAMERA_IMAGE2"] else { return nil }
        return UIImage(contentsOfFile: path)
    }

    static var barcode: String { env["DEMO_BARCODE"] ?? "0885911325905" }
    static var barcode2: String? { env["DEMO_BARCODE2"] }

    static func installKey() {
        guard isOn, let key = env["DEMO_SERPAPI_KEY"] else { return }
        KeychainStore.set(key, for: SettingsKeys.apiKey)
    }

    /// Prints a marker the recording script uses to time the captions.
    static func mark(_ step: String) {
        print("DEMO_STEP \(step) \(Date().timeIntervalSince1970)")
    }

    static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
