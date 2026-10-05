import SwiftUI
import AVFoundation
import AudioToolbox

/// The only main screen: the camera, one instruction, and one backup button.
struct ContentView: View {
    @State private var service = PriceLookupService()
    @State private var showingKeypad = false
    @State private var showingSettings = false
    @State private var cameraAllowed: Bool?
    @State private var isSetUp = KeychainStore.string(for: SettingsKeys.apiKey) != nil
    @State private var demoItem = 1

    private var isScanning: Bool {
        service.state == .scanning && !showingKeypad && !showingSettings
    }

    private var showingResults: Binding<Bool> {
        Binding(
            get: { service.state != .scanning },
            set: { if !$0 { service.reset() } }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let zone = scanZone(in: geo.size)

            ZStack {
                Color.black

                if let demoImage = Demo.cameraImage(item: demoItem) {
                    Image(uiImage: demoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    ScanZoneOverlay(zone: zone)
                } else if cameraAllowed == true, ScannerView.isSupported {
                    ScannerView(isActive: isScanning, regionOfInterest: zone, onScan: handleScan)
                    ScanZoneOverlay(zone: zone)
                } else if cameraAllowed != nil {
                    cameraProblem
                }

                VStack(spacing: 14) {
                    topBar
                    Spacer()
                    BigButton(title: "Type the numbers", systemImage: "keyboard", style: .glass) {
                        showingKeypad = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, geo.safeAreaInsets.top + 8)
                .padding(.bottom, geo.safeAreaInsets.bottom + 12)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .task {
            if Demo.isOn {
                await runDemo()
                return
            }
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        .fullScreenCover(isPresented: showingResults) {
            ResultsView(service: service)
        }
        .fullScreenCover(isPresented: $showingKeypad) {
            KeypadView { number in
                showingKeypad = false
                service.lookUp(number)
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            isSetUp = KeychainStore.string(for: SettingsKeys.apiKey) != nil
        }) {
            SettingsView()
        }
    }

    /// Big scan area: nearly full width, centred a little above the middle.
    private func scanZone(in size: CGSize) -> CGRect {
        let width = size.width - 40
        let height = min(320, width * 0.75)
        return CGRect(x: 20, y: (size.height - height) / 2 - 20, width: width, height: height)
    }

    /// Walks through the app on its own so it can be screen-recorded (simulator demo only).
    private func runDemo() async {
        Demo.installKey()
        isSetUp = true
        Demo.mark("open");      await Demo.pause(4)
        Demo.mark("aim");       await Demo.pause(4)
        handleScan(Demo.barcode)
        Demo.mark("loading")
        while case .loading = service.state { await Demo.pause(0.2) }
        Demo.mark("answer");    await Demo.pause(9)
        Demo.mark("next");      await Demo.pause(2.5)
        if let second = Demo.barcode2 {
            demoItem = 2
            service.reset();    await Demo.pause(1.5)
            Demo.mark("aim2");  await Demo.pause(3.5)
            handleScan(second)
            Demo.mark("loading2")
            while case .loading = service.state { await Demo.pause(0.2) }
            Demo.mark("answer2b"); await Demo.pause(10)
            Demo.mark("next2"); await Demo.pause(2.5)
            demoItem = 1
        }
        service.reset();        await Demo.pause(2)
        Demo.mark("keypad")
        showingKeypad = true
        // KeypadView types the number and submits it; wait for the answer.
        while service.state == .scanning { await Demo.pause(0.2) }
        while case .loading = service.state { await Demo.pause(0.2) }
        Demo.mark("answer2");   await Demo.pause(5)
        Demo.mark("end")
    }

    private func handleScan(_ code: String) {
        AudioServicesPlaySystemSound(1057)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        service.lookUp(code)
    }

    // MARK: - Pieces

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                Text("Hold the barcode\ninside the frame")
                    .font(.rounded(.title, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.5), radius: 6)

                // Setup needs a 2-second press so nobody opens it by accident.
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 2) { showingSettings = true }
                    .accessibilityLabel("Setup. Press and hold for 2 seconds.")
            }

            if !isSetUp {
                // Before setup there's nothing to protect, so one tap opens Setup.
                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                        Text("Not set up yet — tap here")
                    }
                    .font(.rounded(.title3, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cameraProblem: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Theme.accent, in: Circle())
            Text(ScannerView.isSupported
                 ? "The camera is turned off for this app.\nAsk for help turning it on in the iPhone Settings app."
                 : "This iPhone can't scan barcodes with the camera.\nTap \"Type the numbers\" below.")
                .font(.rounded(.title2, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if ScannerView.isSupported {
                BigButton(title: "Open iPhone Settings", systemImage: "gear", style: .glass) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .padding(24)
    }
}

/// Dims everything outside the scan area and draws bright corner brackets with a soft moving line.
private struct ScanZoneOverlay: View {
    let zone: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .mask {
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .frame(width: zone.width, height: zone.height)
                            .position(x: zone.midX, y: zone.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }

            CornerBrackets(length: 44, radius: 28)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: zone.width, height: zone.height)
                .position(x: zone.midX, y: zone.midY)
                .shadow(color: Theme.accentColor.opacity(0.6), radius: 10)

            if !reduceMotion {
                Capsule()
                    .fill(LinearGradient(colors: [.clear] + Theme.accentColors + [.clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: zone.width - 48, height: 3)
                    .shadow(color: Theme.accentColor, radius: 6)
                    .position(x: zone.midX, y: zone.midY + (sweep ? 1 : -1) * (zone.height / 2 - 28))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            sweep = true
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Just the four rounded corners of a rectangle.
private struct CornerBrackets: Shape {
    let length: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = radius, l = length
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r + l, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - r - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + l))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r - l, y: rect.maxY))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX + r + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - l))
        return p
    }
}

/// Fallback: type the number printed under the barcode.
struct KeypadView: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { number.filter(\.isNumber).count >= 6 }

    private func typeForDemo(_ text: String) {
        Demo.mark("typing")
        Task { @MainActor in
            await Demo.pause(1.5)
            for digit in text {
                number.append(digit)
                await Demo.pause(0.22)
            }
            await Demo.pause(1.2)
            onDone(number)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Type the numbers\nunder the barcode")
                .font(.rounded(.largeTitle, .bold))

            TextField("", text: $number, prompt: Text("0 12345 67890 5"))
                .keyboardType(.numberPad)
                .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                .padding(.horizontal, 20)
                .frame(minHeight: 84)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(Theme.accent, lineWidth: focused ? 3 : 0)
                )
                .focused($focused)

            BigButton(title: "Look up prices", systemImage: "magnifyingglass") {
                onDone(number)
            }
            .disabled(!isValid)

            BigButton(title: "Cancel", style: .secondary) { dismiss() }

            Spacer()
        }
        .padding(20)
        .onAppear {
            focused = true
            // Simulator demo: type the number one digit at a time, then press "Look up prices".
            if Demo.isOn { typeForDemo(Demo.barcode) }
        }
    }
}
