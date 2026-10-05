import SwiftUI
import VisionKit

/// Live camera that reads barcodes on its own — no button, no photo.
struct ScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var regionOfInterest: CGRect? = nil   // only read barcodes inside this area (view coordinates)
    var onScan: (String) -> Void

    static var isSupported: Bool { DataScannerViewController.isSupported }
    static var isAvailable: Bool { DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.hasScanned = !isActive
        // Start/stop after the view is on screen.
        DispatchQueue.main.async {
            if let regionOfInterest, scanner.view.bounds.contains(regionOfInterest) {
                scanner.regionOfInterest = regionOfInterest
            }
            if isActive, !scanner.isScanning {
                try? scanner.startScanning()
            } else if !isActive, scanner.isScanning {
                scanner.stopScanning()
            }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        var hasScanned = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case .barcode(let code) = item,
                   let value = code.payloadStringValue, !value.isEmpty {
                    hasScanned = true
                    dataScanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}
