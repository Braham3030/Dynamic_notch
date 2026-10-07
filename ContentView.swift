import UserNotifications
import SwiftUI

import AVFoundation
import Accelerate

class AudioAnalyzer: ObservableObject {
    static let shared = AudioAnalyzer()
    
    @Published var peaks: [CGFloat] = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
    
    private var engine = AVAudioEngine()
    private var fftSetup: FFTSetup?
    private let bufferSize: UInt32 = 1024
    
    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(bufferSize))), FFTRadix(kFFTRadix2))
    }
    
    func startMonitoring() {
        if engine.isRunning { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    DispatchQueue.main.async { self.startEngine() }
                }
            }
        default: break
        }
    }
    
    func stopMonitoring() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async {
            self.peaks = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
        }
    }
    
    private func startEngine() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            
            let frameLength = Int(buffer.frameLength)
            var window = [Float](repeating: 0, count: frameLength)
            vDSP_hann_window(&window, vDSP_Length(frameLength), Int32(vDSP_HANN_NORM))
            
            var windowed = [Float](repeating: 0, count: frameLength)
            vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(frameLength))
            
            var real = [Float](repeating: 0, count: frameLength / 2)
            var imag = [Float](repeating: 0, count: frameLength / 2)
            
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    
                    windowed.withUnsafeBytes { ptr in
                        let fPtr = ptr.bindMemory(to: Float.self).baseAddress!
                        fPtr.withMemoryRebound(to: DSPComplex.self, capacity: frameLength / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(frameLength / 2))
                        }
                    }
                    
                    vDSP_fft_zrip(self.fftSetup!, &splitComplex, 1, vDSP_Length(log2(Float(frameLength))), FFTDirection(FFT_FORWARD))
                    
                    var magnitudes = [Float](repeating: 0.0, count: frameLength / 2)
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(frameLength / 2))
                    
                    let buckets = 6
                    var finalPeaks = [CGFloat](repeating: 0.2, count: buckets)
                    // Discard first few DC buckets, heavily weight bass & mids
                    let bandRanges = [
                        1..<3,      // Sub bass
                        3..<7,      // Bass
                        7..<15,     // Low Mid
                        15..<35,    // Mid
                        35..<80,    // High Mid
                        80..<200    // Treble
                    ]
                    
                    for i in 0..<buckets {
                        var sum: Float = 0
                        let range = bandRanges[i]
                        for j in range {
                            if j < magnitudes.count {
                                sum += magnitudes[j]
                            }
                        }
                        
                        let avg = sum / Float(range.count)
                        // Square root to boost lower volumes visually, scale down for aesthetics
                        let displayValue = CGFloat(min(1.0, max(0.2, (sqrt(avg) / 40.0) * 0.8 + 0.2)))
                        finalPeaks[i] = displayValue
                    }
                    
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                            self.peaks = finalPeaks
                        }
                    }
                }
            }
        }
        
        try? engine.start()
    }
}

import AppKit
import IOKit
import CoreAudio
import AudioToolbox
import Combine
import Sparkle
import CoreWLAN
import IOBluetooth
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func IOBluetoothPreferenceSetControllerPowerState(_ state: Int32)

// MARK: - Image Analysis Extension for Dynamic Color Glow
extension NSImage {
    var averageColor: Color {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .orange }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bitmapData: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(data: &bitmapData, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let multi: Double = 1.4 
        let r = min(Double(bitmapData[0]) / 255.0 * multi, 1.0)
        let g = min(Double(bitmapData[1]) / 255.0 * multi, 1.0)
        let b = min(Double(bitmapData[2]) / 255.0 * multi, 1.0)
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Custom Transitions
struct FlipModifier: ViewModifier {
    let angle: Double
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var artworkFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: 90, opacity: 0), identity: FlipModifier(angle: 0, opacity: 1)),
            removal: .modifier(active: FlipModifier(angle: -90, opacity: 0), identity: FlipModifier(angle: 0, opacity: 1))
        )
    }
    
    // Dynamic Horizontal Slides for Track Skipping (Left/Right Directional)
    static func textSlide(forward: Bool) -> AnyTransition {
        if forward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

enum IslandState {
    case compact; case expandedControls; case expandedMusic; case expandedFood; case expandedAirPods; case expandedPhone; case expandedNotifications; case expandedAirDrop
}

enum AnimationCurve: String, CaseIterable {
    case bouncy = "Bouncy Spring"; case spring = "Apple Spring"; case smooth = "Ease In Out"; case easeIn = "Ease In"; case easeOut = "Ease Out"; case linear = "Linear"; case custom = "Custom Sequence"
    
    var defaultC1: CGPoint {
        switch self { case .linear: return CGPoint(x: 0, y: 0); case .easeIn: return CGPoint(x: 0.42, y: 0); case .easeOut: return CGPoint(x: 0, y: 0); case .smooth: return CGPoint(x: 0.42, y: 0); case .spring: return CGPoint(x: 0.35, y: -0.25); case .bouncy: return CGPoint(x: 0.3, y: -0.5); case .custom: return .zero }
    }
    
    var defaultC2: CGPoint {
        switch self { case .linear: return CGPoint(x: 1.0, y: 1.0); case .easeIn: return CGPoint(x: 1.0, y: 1.0); case .easeOut: return CGPoint(x: 0.58, y: 1.0); case .smooth: return CGPoint(x: 0.58, y: 1.0); case .spring: return CGPoint(x: 0.65, y: 0.85); case .bouncy: return CGPoint(x: 0.6, y: 0.65); case .custom: return .zero }
    }
}

enum ScreenDisplayMode: String, CaseIterable {
    case both = "Both Screens"; case macbook = "MacBook Only"; case external = "External Only"
}


enum AutoCloseBehavior: String, CaseIterable, Identifiable {
    case immediate = "Close Directly"
    case threeSeconds = "Close in 3 Seconds"
    case fiveSeconds = "Close in 5 Seconds"
    case clickOutside = "Close on Click Outside"
    var id: Self { self }
}


struct IslandView: View {
    @ObservedObject var model = IslandModel.shared
    @State private var hovered = false
    @State private var bounceNext = 0
    @State private var bouncePrev = 0
    @State private var manualDragOffset: CGFloat = 0
    @State private var showsExpandedMusicDetails = false
    @State private var showsExpandedControls = false
    @Namespace private var musicActivityNamespace
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The Full Dynamic Notch Background
                ZStack {
                    // 1. Black Dynamic Notch Base Underneath
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous)
                        .fill(Color.black)
                    
                    // 2. Soft, Glassy Dynamic Notch Gradient with Music (Translucent & subtle, starts solid black in compact mode)
                    if model.isExpanded, model.state == .expandedMusic, model.enableArtworkGlow {
                        LinearGradient(
                            colors: [
                                model.artworkColor.opacity(0.40),
                                model.artworkColor.opacity(0.22),
                                model.artworkColor.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .transition(.opacity)
                    }
                }
                .frame(width: model.width, height: model.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous)
                        .stroke(Color.white.opacity(model.isExpanded ? 0.2 : 0.05), lineWidth: 0.5)
                )
                // Ambient Colored Glow around notch in both compact and expanded music modes
                .shadow(
                    color: ((model.isMusicPlaying || model.state == .expandedMusic) && model.enableArtworkGlow) 
                        ? model.artworkColor.opacity(model.isExpanded ? 0.45 : 0.65) 
                        : Color.black.opacity(0.35), 
                    radius: model.isExpanded ? 18 : 10, 
                    x: 0, 
                    y: model.isExpanded ? 6 : 3
                )

                if !model.isExpanded {
                    if model.airPodsShowingCompact || model.airPodsConnected {
                        compactAirPodsActivity
                            .frame(width: model.width, height: model.physicalNotchHeight)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else if model.isMusicPlaying {
                        compactMusicActivity
                            .frame(width: model.width, height: model.physicalNotchHeight)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                
                // Content Layer (Pushed underneath the physical notch area)
                VStack(spacing: 0) {
                    Spacer().frame(height: model.physicalNotchHeight)
                    
                    if model.isExpanded {
                        if model.state == .expandedMusic {
                            musicView
                        } else if model.state == .expandedFood {
                            foodView
                        } else {
                            controlsView
                        }
                    } else {
                        HStack(spacing: 8) {
                            if model.airPodsConnected { Image(systemName: "airpodspro").foregroundColor(.white) }
                        }.padding(.vertical, 4).padding(.horizontal, 16)
                    }
                }
                .frame(width: model.width, height: model.height, alignment: .top)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous))
                .compositingGroup()
                
                // Side Switcher Popout
                if model.isExpanded {
                    VerticalSwitcher(model: model, activeState: model.state)
                        .offset(x: (model.width / 2) + 24 + 18, y: model.physicalNotchHeight + ((model.height - model.physicalNotchHeight) / 2) - 40)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: model.width, height: model.height, alignment: .top)
            .animation(model.currentAnimation, value: model.width)
            .animation(model.currentAnimation, value: model.height)
            .animation(model.currentAnimation, value: model.state)
            .onChange(of: model.state) { _, newState in
                showsExpandedMusicDetails = false
                showsExpandedControls = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard model.state == newState else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showsExpandedMusicDetails = newState == .expandedMusic
                        showsExpandedControls = (newState != .compact && newState != .expandedMusic && newState != .expandedFood)
                    }
                }
            }
            .onAppear {
                showsExpandedMusicDetails = model.state == .expandedMusic
                showsExpandedControls = (model.state != .compact && model.state != .expandedMusic && model.state != .expandedFood)
            }
            .onHover { h in 
                hovered = h
                if h {
                    if !model.isExpanded { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { model.state = model.isMusicPlaying ? .expandedMusic : .expandedControls } }
                } else {
                    if model.autoCloseBehavior != .clickOutside {
                        let delay: TimeInterval = model.autoCloseBehavior == .immediate ? 0.2 : (model.autoCloseBehavior == .threeSeconds ? 3.0 : 5.0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            if !hovered { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { model.state = .compact } }
                        }
                    }
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if model.isExpanded {
                        model.state = .compact
                    } else {
                        model.state = model.isMusicPlaying ? .expandedMusic : .expandedControls
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
    
    @ViewBuilder private var compactAirPodsActivity: some View {
        HStack(spacing: 0) {
            // Left: Authentic 3D Flipping AirPods
            AirPods3DView()
                .frame(width: 26, height: 26)
            
            Spacer(minLength: 0)
            
            // Right: Clean Circular Battery Ring
            CircularBatteryGauge(batteryLevel: model.airPodsBatteryLevel)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var compactMusicActivity: some View {
        HStack(spacing: 0) {
            ZStack {
                Group {
                    if let artwork = model.currentArtwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white.opacity(0.18))
                    }
                }
                .id(model.currentTrackTitle)
                .transition(.flip3D(isForward: model.isForward))
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .matchedGeometryEffect(id: "musicArtwork", in: musicActivityNamespace)

            Spacer(minLength: 0)

            MusicWaveform(isPlaying: model.isMusicPlaying, color: model.artworkColor)
                .frame(width: 24, height: 16)
                .matchedGeometryEffect(id: "musicWaveform", in: musicActivityNamespace)
        }
        .padding(.horizontal, 12)
        .opacity(model.isScreenTransitioning ? 0 : 1)
        .scaleEffect(model.isScreenTransitioning ? 0.75 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: model.isScreenTransitioning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Music is playing")
    }

    @ViewBuilder var controlsView: some View {
        Group {
            if model.state == .expandedAirPods {
                if model.showAirPodsLocalization {
                    HStack(spacing: 16) { Image(systemName: "airpodspro"); Text("AirPods Pro Locating...").font(.headline) }.foregroundColor(.white)
                } else {
                    disabledFeatureNotice("AirPods & Bluetooth Disabled")
                }
            } else if model.state == .expandedPhone {
                if model.showPhone {
                    HStack(spacing: 16) { Image(systemName: "phone.fill").foregroundColor(.green); Text("Incoming Call...").font(.headline).foregroundColor(.white) }
                } else {
                    disabledFeatureNotice("Phone Access Disabled")
                }
            } else if model.state == .expandedNotifications {
                if model.showNotifications {
                    HStack(spacing: 16) { Image(systemName: "bell.fill").foregroundColor(.red); Text("No New Notifications").font(.headline).foregroundColor(.white) }
                } else {
                    disabledFeatureNotice("Notifications Disabled")
                }
            } else if model.state == .expandedAirDrop {
                if model.showAirDrop {
                    HStack(spacing: 16) { Image(systemName: "airdrop"); Text("AirDrop Enabled").font(.headline) }.foregroundColor(.white)
                } else {
                    disabledFeatureNotice("AirDrop Sharing Disabled")
                }
            } else {
                if model.showControlCenter {
                    HStack(spacing: 16) {
                        HStack(spacing: 10) { 
                            ControlButton(isOn: $model.isWifiOn, iconOn: "wifi", iconOff: "wifi.slash", activeTint: .blue, variableValue: Double(model.wifiBars) / 3.0, action: model.toggleWiFi)
                            ControlButton(isOn: $model.isBluetoothOn, iconOn: "bluetooth.custom", iconOff: "bluetooth.custom", activeTint: .blue, action: model.toggleBluetooth) 
                        }
                        VStack(spacing: 8) { 
                            CustomSlider(value: $model.brightness, icon: "sun.max.fill") { val in model.applySystemBrightness(forcedValue: val) }
                            CustomSlider(value: $model.volume, icon: "speaker.wave.3.fill") { val in model.applySystemVolume(forcedValue: val) } 
                        }.frame(width: 140)
                        if model.airPodsConnected && model.showAirPodsLocalization {
                            AirPodsListeningModeSlider(model: model)
                        }
                    }
                } else {
                    disabledFeatureNotice("Control Center Quick Toggles Disabled")
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
        .opacity(showsExpandedControls ? 1 : 0)
        .offset(y: showsExpandedControls ? 0 : -72)
        .allowsHitTesting(showsExpandedControls)
    }
    
    @ViewBuilder func disabledFeatureNotice(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.slash.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder var musicView: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.clear).frame(width: 50, height: 50)
                    ZStack {
                        if let img = model.currentArtwork { 
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.gray.opacity(0.3)).frame(width: 50, height: 50)
                            Image(systemName: "music.note").font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                    .id(model.currentTrackTitle)
                    .transition(.flip3D(isForward: model.isForward))
                }
                .matchedGeometryEffect(id: "musicArtwork", in: musicActivityNamespace)
                .zIndex(1)
                
                ZStack(alignment: .leading) {
                    // Previous Track (Hidden 200px to the left, slides in when dragging right)
                    if manualDragOffset > 0 && !model.prevTrackName.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.prevTrackName).font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                            Text("Previous").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.4)).lineLimit(1).textCase(.uppercase)
                        }
                        .offset(x: manualDragOffset - 240)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.currentTrackTitle).font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text(model.currentTrackArtist).font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                    }
                    .offset(x: manualDragOffset)
                    
                    // Next Track (Hidden 200px to the right, slides in when dragging left)
                    if manualDragOffset < 0 && !model.nextTrackName.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.nextTrackName).font(.system(size: 15, weight: .bold)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                            Text("Next").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.4)).lineLimit(1).textCase(.uppercase)
                        }
                        .offset(x: manualDragOffset + 240)
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1.0)
                    ]), startPoint: .leading, endPoint: .trailing)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            manualDragOffset = value.translation.width
                        }
                        .onEnded { drag in
                            if drag.translation.width < -40 {
                                model.isForward = true
                                model.lastManualSkipTime = Date()
                                withAnimation(.easeIn(duration: 0.2)) { manualDragOffset = -400 }
                                
                                DispatchQueue.global(qos: .userInitiated).async {
                                    _ = NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(nil)
                                    usleep(300_000) // Wait 300ms for Apple Music to jump track
                                    model.fetchCurrentMusicState() // Force fetch state manually
                                    
                                    DispatchQueue.main.async {
                                        manualDragOffset = 400
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { manualDragOffset = 0 }
                                        }
                                    }
                                }
                            } else if drag.translation.width > 40 {
                                model.isForward = false
                                model.lastManualSkipTime = Date()
                                withAnimation(.easeIn(duration: 0.2)) { manualDragOffset = 400 }
                                
                                DispatchQueue.global(qos: .userInitiated).async {
                                    _ = NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(nil)
                                    usleep(300_000)
                                    model.fetchCurrentMusicState()
                                    
                                    DispatchQueue.main.async {
                                        manualDragOffset = -400
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { manualDragOffset = 0 }
                                        }
                                    }
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { manualDragOffset = 0 }
                            }
                        }
                )
                .zIndex(0)
                .opacity(showsExpandedMusicDetails ? 1 : 0)
                .offset(y: showsExpandedMusicDetails ? 0 : -72)
                .allowsHitTesting(showsExpandedMusicDetails)
                
                Spacer(minLength: 0)
                ZStack {
                    MusicWaveform(isPlaying: model.isMusicPlaying, color: model.artworkColor)
                }
                .frame(width: 34, height: 24)
                .matchedGeometryEffect(id: "musicWaveform", in: musicActivityNamespace)
                .padding(.horizontal, 4)
                .zIndex(1)
            }
            
            // Scrubber
            LiquidScrubber()
                .padding(.top, 4)
                .padding(.horizontal, 4)
                .opacity(showsExpandedMusicDetails ? 1 : 0)
                .offset(y: showsExpandedMusicDetails ? 0 : -52)
            
            // Media Controls
            HStack(spacing: 36) {
                Button(action: {
                    bouncePrev += 1
                    DispatchQueue.global(qos: .background).async { 
                        _ = NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(nil) 
                    }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, value: bouncePrev)
                }.buttonStyle(.plain)
                
                Button(action: {
                    // Instantly visually swap with morphing animation
                    withAnimation { model.isMusicPlaying.toggle() }
                    DispatchQueue.global(qos: .background).async { 
                        _ = NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(nil) 
                    }
                }) {
                    Image(systemName: model.isMusicPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect(.replace))
                }.buttonStyle(.plain)
                
                Button(action: {
                    bounceNext += 1
                    DispatchQueue.global(qos: .background).async { 
                        _ = NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(nil) 
                    }
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, value: bounceNext)
                }.buttonStyle(.plain)
            }
            .padding(.top, 4)
            .opacity(showsExpandedMusicDetails ? 1 : 0)
            .offset(y: showsExpandedMusicDetails ? 0 : -36)
            .allowsHitTesting(showsExpandedMusicDetails)
        }
        .padding(16)
    }
    
    @ViewBuilder var foodView: some View {
        HStack(spacing: 16) {
            Image(systemName: "bag.fill").foregroundColor(.green).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 4) {
                Text("Order Arriving").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text("Your food is 3 mins away").font(.system(size: 12)).foregroundColor(.gray)
            }
            Spacer()
            Text("03:12").font(.system(.body, design: .monospaced)).foregroundColor(.green)
        }.padding(.horizontal, 16)
    }
}



extension IslandModel {
    var isExpanded: Bool {
        return state != .compact || isHoverExpanded
    }
    var width: CGFloat {
        if isScreenTransitioning {
            return baseNotchWidth
        }
        if isExpanded {
            if state == .expandedMusic { return 420 }
            if state == .expandedControls && airPodsConnected { return 450 }
            if state == .expandedFood { return 360 }
            return 380
        }
        if airPodsConnected || airPodsShowingCompact {
            return baseNotchWidth + 80
        }
        if isMusicPlaying {
            return baseNotchWidth + 96
        }
        return baseNotchWidth
    }
    
    var height: CGFloat {
        if isExpanded {
            if state == .expandedMusic { return 215 }
            if state == .expandedFood { return 85 }
            return 120
        }
        return physicalNotchHeight
    }
    
    var currentTrackTitle: String { currentTrack }
    var currentTrackArtist: String { currentArtist }
    var musicProgress: Double { 0.4 }
    
    func skipDummyTrack(forward: Bool) {
        let dummies = [
            ("Don\'t Stop Me Now", "Queen"),
            ("Starboy", "The Weeknd"),
            ("Blinding Lights", "The Weeknd"),
            ("Cruel Summer", "Taylor Swift"),
            ("Hotel California", "Eagles")
        ]
        if let idx = dummies.firstIndex(where: { $0.0 == currentTrack }) {
            let next = forward ? (idx + 1) % dummies.count : (idx - 1 + dummies.count) % dummies.count
            currentTrack = dummies[next].0
            currentArtist = dummies[next].1
        } else {
            currentTrack = dummies[0].0
            currentArtist = dummies[0].1
        }
    } // dummy for UI
}

struct SwitcherMenu: View {
    @ObservedObject var model = IslandModel.shared
    var body: some View {
        EmptyView() // just a stub if missing
    }
}

class IslandModel: ObservableObject {
    var pendingArtworkRetry: Bool = false
    var artworkRetryCount: Int = 0
    var lastArtworkData: Data? = nil
    private var lastVolumeAppleScriptTime: Date = Date()
    private var volumeWorkItem: DispatchWorkItem?
    static let shared = IslandModel()
    
    @Published var state: IslandState = .compact
    @Published var compactCornerRadius: CGFloat = 12.0
    
    @Published var autoCloseBehavior: AutoCloseBehavior = .immediate
    @Published var isHoverExpanded: Bool = false
    var hoverCloseTask: Task<Void, Never>? = nil
    @Published var showAirPodsLocalization: Bool = false
    @Published var showControlCenter: Bool = false
    @Published var showMusic: Bool = false
    @Published var showPhone: Bool = false
    @Published var showNotifications: Bool = false
    @Published var showAirDrop: Bool = false
    
    func handleHover(_ isHovering: Bool) {
        hoverCloseTask?.cancel()
        if isHovering {
            isHoverExpanded = true
        } else {
            switch autoCloseBehavior {
            case .immediate:
                isHoverExpanded = false
            case .threeSeconds:
                hoverCloseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !Task.isCancelled { self.isHoverExpanded = false }
                }
            case .fiveSeconds:
                hoverCloseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled { self.isHoverExpanded = false }
                }
            case .clickOutside:
                break // Wait for global click
            }
        }
    }
    @Published var airPodsName: String = "AirPods Pro"
    @Published var airPodsBatteryLevel: Double = 0.85
    @Published var hasMicPermission: Bool = false
    
    func requestControlCenterPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for Control Center"
            alert.informativeText = "Dynamic Notch requires permission to interact with macOS System Events and Accessibility to adjust screen brightness, system volume, Wi-Fi, and Bluetooth.\n\nWould you like to grant permission to modify system controls?"
            alert.addButton(withTitle: "Allow System Access")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                _ = AXIsProcessTrustedWithOptions(options)
                self.showControlCenter = true
                completion(true)
            } else {
                self.showControlCenter = false
                completion(false)
            }
        }
    }

    func requestMusicPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for Apple Music"
            alert.informativeText = "Dynamic Notch requires permission to communicate with Apple Music to retrieve track information, album art, and control playback.\n\nWould you like to grant permission to use the Apple Music service?"
            alert.addButton(withTitle: "Allow Music Access")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let script = "tell application \"Music\" to get player state"
                var error: NSDictionary?
                if let scriptObj = NSAppleScript(source: script) {
                    _ = scriptObj.executeAndReturnError(&error)
                }
                self.showMusic = true
                self.startMusicMonitoring()
                completion(true)
            } else {
                self.showMusic = false
                self.isMusicPlaying = false
                completion(false)
            }
        }
    }
    
    func requestAirPodsPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for Bluetooth & AirPods"
            alert.informativeText = "Dynamic Notch requires Bluetooth permission to detect nearby paired AirPods, read real-time connection status, and show battery level gauges.\n\nWould you like to grant Bluetooth access?"
            alert.addButton(withTitle: "Allow Bluetooth Access")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.showAirPodsLocalization = true
                self.triggerAirPodsConnectSimulation()
                completion(true)
            } else {
                self.showAirPodsLocalization = false
                self.airPodsShowingCompact = false
                completion(false)
            }
        }
    }
    
    func requestMicPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for Waveform Visualizer"
            alert.informativeText = "Dynamic Notch requests microphone access for real-time FFT audio frequency analysis to animate music waveforms in the notch.\n\nWould you like to grant microphone access?"
            alert.addButton(withTitle: "Allow Microphone Access")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        self.hasMicPermission = granted
                        if granted {
                            AudioAnalyzer.shared.startMonitoring()
                        } else {
                            AudioAnalyzer.shared.stopMonitoring()
                        }
                        completion(granted)
                    }
                }
            } else {
                self.hasMicPermission = false
                AudioAnalyzer.shared.stopMonitoring()
                completion(false)
            }
        }
    }
    
    func requestNotificationsPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for Notifications"
            alert.informativeText = "Dynamic Notch requires notification permissions to present floating alert banners inside the notch.\n\nWould you like to allow notifications?"
            alert.addButton(withTitle: "Allow Notifications")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        self.showNotifications = granted
                        completion(granted)
                    }
                }
            } else {
                self.showNotifications = false
                completion(false)
            }
        }
    }
    
    func requestPhonePermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for Phone & Calls"
            alert.informativeText = "Dynamic Notch requires permission to detect active phone and FaceTime calls.\n\nWould you like to grant permission?"
            alert.addButton(withTitle: "Allow Phone Access")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            let response = alert.runModal()
            self.showPhone = (response == .alertFirstButtonReturn)
            completion(self.showPhone)
        }
    }
    
    func requestAirDropPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required for AirDrop Sharing"
            alert.informativeText = "Dynamic Notch requires permission to observe active incoming and outgoing AirDrop transfers.\n\nWould you like to grant AirDrop access?"
            alert.addButton(withTitle: "Allow AirDrop Access")
            alert.addButton(withTitle: "Don't Allow")
            alert.alertStyle = .informational
            let response = alert.runModal()
            self.showAirDrop = (response == .alertFirstButtonReturn)
            completion(self.showAirDrop)
        }
    }
    
    func triggerAirPodsConnectSimulation() {
        guard showAirPodsLocalization else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.airPodsConnected = true
            self.airPodsShowingCompact = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                self.airPodsShowingCompact = false
            }
        }
    }
    
    func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    @Published var airPodsShowingCompact: Bool = false
    @Published var airPodsConnected: Bool = false
    
        @Published var brightness: Double = 0.65 {
        didSet { applySystemBrightness() }
    }
        @Published var volume: Double = 0.5 {
        didSet { applySystemVolume() }
    }
    @Published var isWifiOn: Bool = true
    @Published var isBluetoothOn: Bool = true
    @Published var wifiBars: Int = 3
    private var wifiTimer: Timer?
    
    @Published var currentTrack: String = ""
    @Published var currentArtist: String = ""
    @Published var nextTrackName: String = ""
    @Published var prevTrackName: String = ""
    @Published var trackDuration: Double = 1.0
    @Published var playbackPosition: Double = 0.0
    @Published var currentArtwork: NSImage? = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/MusicIcon.icns")
    @Published var artworkColor: Color = .orange
    @Published var isMusicPlaying: Bool = false
    @Published var enableArtworkGlow: Bool = true
    
    // Track transition overrides
    @Published var isForward: Bool = true
    var lastManualSkipTime: Date = .distantPast
    
    @Published var animationCurve: AnimationCurve = .spring
    @Published var animationDuration: Double = 0.45 
    
    @Published var customC1: CGPoint = CGPoint(x: 0.42, y: 0.0)
    @Published var customC2: CGPoint = CGPoint(x: 0.58, y: 1.0)
    
    @Published var physicalNotchHeight: CGFloat = 32 
    @Published var baseNotchWidth: CGFloat = 200 
    @Published var displayMode: ScreenDisplayMode = .both
    @Published var settingsBackgroundStyle: SettingsBackgroundStyle = .liquidGlass
    @Published var settingsGlassIntensity: Double = 0.75
    @Published var settingsWindowOpacity: Double = 0.85
    
    var updaterController: SPUStandardUpdaterController?
    
    @Published var isScreenTransitioning: Bool = false
    private var transitionDebounceTask: Task<Void, Never>? = nil

    init() {
        readSystemBrightness()
        readSystemVolume()
        startWifiMonitoring()
        startMusicMonitoring()
        startScreenTransitionMonitoring()
        startAirPodsMonitoring()
    }

    func startScreenTransitionMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.endSwipeExpansion()
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.triggerScreenTransitionPulse()
            }
        }
    }
    
    func beginSwipeCollapse() {
        transitionDebounceTask?.cancel()
        withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
            self.isScreenTransitioning = true
        }
        transitionDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.65)) {
                    self.isScreenTransitioning = false
                }
            }
        }
    }
    
    func endSwipeExpansion() {
        transitionDebounceTask?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                self.isScreenTransitioning = false
            }
        }
    }
    
    func triggerScreenTransitionPulse() {
        transitionDebounceTask?.cancel()
        transitionDebounceTask = Task { @MainActor in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                self.isScreenTransitioning = true
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                    self.isScreenTransitioning = false
                }
            }
        }
    }
    
    // Centralized Music Actions
    func skipTrack(forward: Bool) {
        DispatchQueue.main.async {
            self.isForward = forward
            self.lastManualSkipTime = Date()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = NSAppleScript(source: forward ? "tell application \"Music\" to next track" : "tell application \"Music\" to previous track")?.executeAndReturnError(nil)
            Thread.sleep(forTimeInterval: 0.2) // Allow music app to register skip before fetching!
            self.fetchCurrentMusicState()
        }
    }
    
    func togglePlayPause() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(nil)
            self.fetchCurrentMusicState()
        }
    }
    
    func openAppleMusic() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = NSAppleScript(source: "tell application \"Music\" to activate")?.executeAndReturnError(nil)
        }
    }
    
    private func startMusicMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.fetchCurrentMusicState() }
        fetchCurrentMusicState()
    }
    
    func fetchCurrentMusicState() {
        DispatchQueue.global(qos: .userInitiated).async {
            let scriptSource = """
            if application "Music" is running then
                tell application "Music"
                    if player state is playing then
                        set tTrack to name of current track
                        set tArtist to artist of current track
                        set tDur to duration of current track
                        set tPos to player position
                        set rArt to missing value
                        try
                            set rArt to raw data of artwork 1 of current track
                        end try
                        set pTrack to ""
                        set nTrack to ""
                        try
                            set curr to index of current track
                            if curr > 1 then
                                set pTrack to name of track (curr - 1)
                            end if
                            set nTrack to name of track (curr + 1)
                        end try
                        return {tTrack, tArtist, tDur, tPos, rArt, pTrack, nTrack}
                    end if
                end tell
            end if
            return missing value
            """
            
            var err: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else { return }
            let desc = script.executeAndReturnError(&err)
            
            if desc.numberOfItems < 2 {
                DispatchQueue.main.async {
                    if self.isMusicPlaying {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            self.isMusicPlaying = false
                        }
                    }
                }
                return
            }
            
            let tTrack = desc.atIndex(1)?.stringValue ?? "Unknown Track"
            let tArtist = desc.atIndex(2)?.stringValue ?? "Unknown Artist"
            let tDuration = desc.atIndex(3)?.doubleValue ?? 100.0
            let tPosition = desc.atIndex(4)?.doubleValue ?? 0.0
            let pTrack = desc.atIndex(6)?.stringValue ?? ""
            let nTrack = desc.atIndex(7)?.stringValue ?? ""
            
            var fetchNewArt = false
            DispatchQueue.main.sync {
                self.trackDuration = tDuration > 0 ? tDuration : 1.0
                self.playbackPosition = tPosition
                if self.currentTrack != tTrack || self.pendingArtworkRetry {
                    fetchNewArt = true
                    if self.currentTrack != tTrack && Date().timeIntervalSince(self.lastManualSkipTime) > 2.0 {
                        self.isForward = true
                    }
                }
            }
            
            var newImage: NSImage? = nil
            var finalColor: Color = .orange
            var fetchedData: Data? = nil
            
            if fetchNewArt {
                if let dataDesc = desc.atIndex(5) {
                    let rawData = dataDesc.data
                    fetchedData = rawData
                    
                    if let img = NSImage(data: rawData) {
                        newImage = img
                        finalColor = img.averageColor
                    }
                }
            }
            
            DispatchQueue.main.async {
                if fetchNewArt {
                    var doFlip = false
                    if self.currentTrack != tTrack { 
                        doFlip = true 
                        self.artworkRetryCount = 0
                    }
                    
                    let isStale = (self.lastArtworkData != nil && fetchedData == self.lastArtworkData)
                    let isMissing = (fetchedData == nil)
                    
                    if (isStale || isMissing) && self.artworkRetryCount < 10 {
                        self.pendingArtworkRetry = true
                        self.artworkRetryCount += 1
                    } else {
                        self.pendingArtworkRetry = false
                        if fetchedData != nil { self.lastArtworkData = fetchedData }
                    }
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        self.isMusicPlaying = true
                        self.currentTrack = tTrack
                        self.currentArtist = tArtist
                        self.prevTrackName = pTrack
                        self.nextTrackName = nTrack
                        // Commit the image if we got one, or if we gave up on retrying!
                        if newImage != nil || !self.pendingArtworkRetry || doFlip {
                            self.currentArtwork = newImage ?? NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/MusicIcon.icns")
                            if newImage != nil { self.artworkColor = finalColor }
                        }
                    }
                } else if !self.isMusicPlaying {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        self.isMusicPlaying = true
                    }
                }
            }
        }
    }

    private func startWifiMonitoring() {
        updateWifiStrength()
        refreshBluetoothState()
        wifiTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateWifiStrength()
            self?.refreshBluetoothState()
        }
    }

    func toggleWiFi() {
        guard let interface = CWWiFiClient.shared().interface() else {
            isWifiOn = false
            wifiBars = 0
            return
        }

        do {
            try interface.setPower(!interface.powerOn())
            updateWifiStrength()
        } catch {
            updateWifiStrength()
        }
    }

    func toggleBluetooth() {
        let newState = !isBluetoothOn
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isBluetoothOn = newState
        }
        DispatchQueue.global(qos: .background).async {
            IOBluetoothPreferenceSetControllerPowerState(newState ? 1 : 0)
        }
    }

    @Published var listeningMode: Int = 2
    func setAirPodsMode(_ mode: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.listeningMode = mode
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            let sel1 = Selector("setListeningMode:")
            let sel2 = Selector("setNoiseCancellationMode:")
            let sel3 = Selector("setListeningMode:error:")
            typealias SetListeningModeIMP = @convention(c) (AnyObject, Selector, UInt8) -> Bool
            for device in devices where device.isConnected() {
                if device.responds(to: sel1) {
                    let imp = device.method(for: sel1)
                    let fn = unsafeBitCast(imp, to: SetListeningModeIMP.self)
                    _ = fn(device, sel1, UInt8(mode))
                } else if device.responds(to: sel2) {
                    let imp = device.method(for: sel2)
                    let fn = unsafeBitCast(imp, to: SetListeningModeIMP.self)
                    _ = fn(device, sel2, UInt8(mode))
                }
            }
        }
    }

    func openBluetoothSettings() {
        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: settingsURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    private func refreshBluetoothState() {
        isBluetoothOn = IOBluetoothHostController.default().powerState == kBluetoothHCIPowerStateON
    }
    
    private var airPodsMonitorTimer: Timer?
    
    func startAirPodsMonitoring() {
        checkRealAirPodsStatus()
        airPodsMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkRealAirPodsStatus()
        }
    }
    
    func checkRealAirPodsStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            
            var foundConnectedAirPods: (name: String, battery: Double)? = nil
            
            for device in devices {
                let name = device.nameOrAddress ?? ""
                let isAirPods = name.localizedCaseInsensitiveContains("AirPods")
                if isAirPods && device.isConnected() {
                    var leftBat: Double = -1
                    var rightBat: Double = -1
                    var singleBat: Double = -1
                    
                    let selSingle = Selector(("batteryPercentSingle"))
                    let selLeft = Selector(("batteryPercentLeft"))
                    let selRight = Selector(("batteryPercentRight"))
                    
                    typealias BatIMP = @convention(c) (AnyObject, Selector) -> UInt8
                    
                    if device.responds(to: selLeft) {
                        let imp = device.method(for: selLeft)
                        let fn = unsafeBitCast(imp, to: BatIMP.self)
                        let val = fn(device, selLeft)
                        if val > 0 && val <= 100 { leftBat = Double(val) / 100.0 }
                    }
                    if device.responds(to: selRight) {
                        let imp = device.method(for: selRight)
                        let fn = unsafeBitCast(imp, to: BatIMP.self)
                        let val = fn(device, selRight)
                        if val > 0 && val <= 100 { rightBat = Double(val) / 100.0 }
                    }
                    if device.responds(to: selSingle) {
                        let imp = device.method(for: selSingle)
                        let fn = unsafeBitCast(imp, to: BatIMP.self)
                        let val = fn(device, selSingle)
                        if val > 0 && val <= 100 { singleBat = Double(val) / 100.0 }
                    }
                    
                    var bestBattery: Double = 0.80
                    if singleBat > 0 {
                        bestBattery = singleBat
                    } else if leftBat > 0 || rightBat > 0 {
                        bestBattery = max(leftBat > 0 ? leftBat : 0, rightBat > 0 ? rightBat : 0)
                    }
                    
                    foundConnectedAirPods = (name: name, battery: bestBattery)
                    break
                }
            }
            
            DispatchQueue.main.async {
                if let airpods = foundConnectedAirPods {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        self.airPodsName = airpods.name
                        self.airPodsBatteryLevel = airpods.battery
                        self.airPodsConnected = true
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        self.airPodsConnected = false
                    }
                }
            }
        }
    }

    private func updateWifiStrength() {
        guard let interface = CWWiFiClient.shared().interface() else {
            isWifiOn = false
            wifiBars = 0
            return
        }

        isWifiOn = interface.powerOn()
        guard isWifiOn else {
            wifiBars = 0
            return
        }

        let rssi = interface.rssiValue()
        if rssi == 0 {
            wifiBars = 0
        } else if rssi > -55 {
            wifiBars = 3
        } else if rssi > -70 {
            wifiBars = 2
        } else {
            wifiBars = 1
        }
    }
    func makeCustomIfNeeded() { if animationCurve != .custom { customC1 = animationCurve.defaultC1; customC2 = animationCurve.defaultC2; animationCurve = .custom } }
    
    var currentAnimation: Animation { switch animationCurve { case .spring: return .spring(response: animationDuration, dampingFraction: 0.62, blendDuration: 0.1); case .bouncy: return .spring(response: animationDuration, dampingFraction: 0.45, blendDuration: 0.1); case .smooth: return .easeInOut(duration: animationDuration); case .easeIn: return .easeIn(duration: animationDuration); case .easeOut: return .easeOut(duration: animationDuration); case .linear: return .linear(duration: animationDuration); case .custom: return .timingCurve(customC1.x, customC1.y, customC2.x, customC2.y, duration: animationDuration) } }
    func toggleState(_ nextState: IslandState) { if state == nextState { state = .compact } else { state = nextState } }
}


struct AirPods3DView: View {
    @State private var flipDegrees: Double = 0
    @State private var floatBob: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 1.5) {
            // Left AirPod with 3D Y-Axis Flip & Perspective
            Image(systemName: "airpodspro.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .offset(y: floatBob)
                .rotation3DEffect(
                    .degrees(flipDegrees),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    anchor: .center,
                    perspective: 0.25
                )
            
            // Right AirPod with subtle staggered 3D Flip & Perspective
            Image(systemName: "airpodspro.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .offset(y: -floatBob)
                .rotation3DEffect(
                    .degrees(flipDegrees),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    anchor: .center,
                    perspective: 0.25
                )
        }
        .padding(.leading, 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: false)) {
                flipDegrees = 360
                floatBob = 1.0
            }
        }
    }
}

struct CircularBatteryGauge: View {
    var batteryLevel: Double = 0.85
    
    var body: some View {
        ZStack {
            // Track circle
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 3.0)
            
            // Active Progress circle (No percentage text!)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, min(1.0, batteryLevel))))
                .stroke(
                    batteryLevel > 0.2 ? Color.green : Color.red,
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: batteryLevel)
            
            // Mini center power dot
            Circle()
                .fill(batteryLevel > 0.2 ? Color.green.opacity(0.9) : Color.red.opacity(0.9))
                .frame(width: 4, height: 4)
        }
        .frame(width: 18, height: 18)
    }
}

struct MusicWaveform: View {
    var isPlaying: Bool
    var color: Color = .white
    @State private var isAnimating = false
    
    let heights: [CGFloat] = [8, 14, 10, 16, 12]
    let durations: [Double] = [0.35, 0.4, 0.25, 0.45, 0.3]
    
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(color).frame(width: 3.5, height: isAnimating ? heights[i] : 4)
                    .animation(isPlaying ? .easeInOut(duration: durations[i]).repeatForever(autoreverses: true).delay(Double(i) * 0.1) : .spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
            }
        }.frame(height: 16, alignment: .center)
        .onChange(of: isPlaying) { _, play in isAnimating = play }
        .onAppear { isAnimating = isPlaying }
    }
}


enum SettingsBackgroundStyle: String, CaseIterable, Identifiable {
    case liquidGlass = "Liquid Glass"
    case obsidian = "Dark Obsidian"
    case aurora = "Aurora Glow"
    case sunset = "Sunset Mirage"
    case slate = "Minimal Slate"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .liquidGlass: return "drop.fill"
        case .obsidian: return "circle.fill"
        case .aurora: return "sparkles"
        case .sunset: return "sun.horizon.fill"
        case .slate: return "square.fill"
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance = "Appearance & Physics"
    case background = "Window & Background"
    case display = "Hardware Calibration"
    case liveActivities = "Live Activities"
    case systemControls = "System Controls"
    case about = "About"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: return "sparkles"
        case .background: return "paintpalette.fill"
        case .display: return "display"
        case .liveActivities: return "bolt.fill"
        case .systemControls: return "switch.2"
        case .about: return "info.circle"
        }
    }
}

struct SkipButtonStyle: ButtonStyle {
    let direction: CGFloat 
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .offset(x: configuration.isPressed ? direction * 14 : 0) // Jumps massively left or right!
            .scaleEffect(configuration.isPressed ? 0.8 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
struct PlayPauseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.foregroundStyle(.white).scaleEffect(configuration.isPressed ? 0.8 : 1.0).opacity(configuration.isPressed ? 0.7 : 1.0).animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed) }
}

struct ContentView: View {
    @ObservedObject var model = IslandModel.shared
    @State private var selectedPane: SettingsPane = .appearance
    @State private var hoveredPane: SettingsPane? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 4) {
                Text("Preferences")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 44)
                    .padding(.bottom, 12)
                
                ForEach(SettingsPane.allCases) { pane in
                    let isSelected = selectedPane == pane
                    Button {
                        selectedPane = pane
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pane.icon)
                                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                                .frame(width: 24, alignment: .center)
                            Text(pane.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.22) : (hoveredPane == pane ? Color.primary.opacity(0.06) : Color.clear))
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { hoveredPane = pane } else if hoveredPane == pane { hoveredPane = nil }
                    }
                    .padding(.horizontal, 10)
                }
                Spacer()
            }
            .frame(width: 235, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(
                VisualEffect()
                    .opacity(model.settingsWindowOpacity)
            )
            
            Divider().ignoresSafeArea()
            
            // Detail Content
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selectedPane.rawValue)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 12)
                
                switch selectedPane {
                case .appearance:
                    AnimationSettingsView()
                case .background:
                    BackgroundSettingsView()
                case .display:
                    HardwareCalibrationView()
                case .liveActivities:
                    LiveActivitiesView()
                case .systemControls:
                    SystemControlsView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                settingsPaneBackground
            )
        }
        .ignoresSafeArea()
        .frame(width: 840, height: 680)
    }
    
    @ViewBuilder private var settingsPaneBackground: some View {
        ZStack {
            VisualEffect()
                .opacity(model.settingsWindowOpacity)
            
            switch model.settingsBackgroundStyle {
            case .liquidGlass:
                Color(NSColor.controlBackgroundColor).opacity(0.4 * model.settingsWindowOpacity)
                LinearGradient(
                    colors: [Color.white.opacity(0.12 * model.settingsGlassIntensity), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .obsidian:
                Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.85 * model.settingsWindowOpacity)
            case .aurora:
                LinearGradient(
                    colors: [Color.purple.opacity(0.25 * model.settingsWindowOpacity), Color.teal.opacity(0.20 * model.settingsWindowOpacity)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .sunset:
                LinearGradient(
                    colors: [Color.orange.opacity(0.22 * model.settingsWindowOpacity), Color.pink.opacity(0.18 * model.settingsWindowOpacity)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .slate:
                Color(red: 0.16, green: 0.18, blue: 0.22).opacity(0.75 * model.settingsWindowOpacity)
            }
        }
    }
}

struct BezierGraph: View {
    @ObservedObject var model: IslandModel
    
    let w: CGFloat = 460
    let h: CGFloat = 200
    let pad_x: CGFloat = 24
    let pad_y: CGFloat = 32
    
    var body: some View {
        let drawW = w - (pad_x * 2)
        let drawH = h - (pad_y * 2)
        
        let c1 = model.animationCurve == .custom ? model.customC1 : model.animationCurve.defaultC1
        let c2 = model.animationCurve == .custom ? model.customC2 : model.animationCurve.defaultC2
        let pStart = CGPoint(x: pad_x, y: pad_y + drawH)
        let pEnd = CGPoint(x: pad_x + drawW, y: pad_y)
        let p1 = CGPoint(x: pad_x + (c1.x * drawW), y: pad_y + (1 - c1.y) * drawH)
        let p2 = CGPoint(x: pad_x + (c2.x * drawW), y: pad_y + (1 - c2.y) * drawH)
        
        ZStack {
            Path { p in
                p.move(to: pStart)
                p.addLine(to: CGPoint(x: pEnd.x, y: pStart.y))
                p.addLine(to: pEnd)
                p.addLine(to: CGPoint(x: pStart.x, y: pEnd.y))
                p.closeSubpath()
            }
            .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
            
            Path { p in p.move(to: pStart); p.addLine(to: p1) }
                .stroke(model.animationCurve == .custom ? Color.orange.opacity(0.6) : Color.primary.opacity(0.25), lineWidth: 1.5)
            Path { p in p.move(to: pEnd); p.addLine(to: p2) }
                .stroke(model.animationCurve == .custom ? Color.orange.opacity(0.6) : Color.primary.opacity(0.25), lineWidth: 1.5)
            Path { path in
                path.move(to: pStart)
                path.addCurve(to: pEnd, control1: p1, control2: p2)
            }
            .stroke(model.animationCurve == .custom ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            
            Circle().fill(Color.accentColor).frame(width: 8, height: 8).position(pStart)
            Circle().fill(Color.accentColor).frame(width: 8, height: 8).position(pEnd)
            Circle().fill(Color.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 3).overlay(Circle().stroke(model.animationCurve == .custom ? Color.orange : Color.gray, lineWidth: 2)).position(p1)
            Circle().fill(Color.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 3).overlay(Circle().stroke(model.animationCurve == .custom ? Color.orange : Color.gray, lineWidth: 2)).position(p2)
            
            Color.black.opacity(0.001)
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { val in
                        model.makeCustomIfNeeded()
                        let nx = min(max(0, (val.location.x - pad_x) / drawW), 1)
                        let maxY = 1 + (pad_y / drawH)
                        let minY = 0 - (pad_y / drawH)
                        let ny = min(max(minY, 1 - ((val.location.y - pad_y) / drawH)), maxY)
                        if val.startLocation.x < w / 2 {
                            model.customC1 = CGPoint(x: nx, y: ny)
                        } else {
                            model.customC2 = CGPoint(x: nx, y: ny)
                        }
                    }
                )
        }
        .frame(width: w, height: h)
    }
}

struct AnimationSettingsView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Morphing Physics"), footer: Text("Drag anywhere inside the Sandbox Graph to instantly trace out custom trajectories.")) { VStack(alignment: .leading, spacing: 30) { VStack(alignment: .leading, spacing: 18) { Picker("Curve Algorithm", selection: $model.animationCurve) { ForEach(AnimationCurve.allCases, id: \.self) { curve in Text(curve.rawValue).tag(curve) } }; VStack(alignment: .leading, spacing: 6) { HStack { Text("Duration Time"); Spacer(); Text(String(format: "%.1fs", model.animationDuration)).monospacedDigit().foregroundStyle(.secondary) }; Slider(value: $model.animationDuration, in: 0.1...1.5, step: 0.1) } }; VStack(alignment: .leading) { Text(model.animationCurve == .custom ? "Live Physics Sandbox" : "System Easing Math").font(.subheadline.weight(.medium)).foregroundStyle(model.animationCurve == .custom ? .orange : .secondary).padding(.bottom, 6); BezierGraph(model: model).frame(height: 250).padding(.horizontal, 26).padding(.vertical, 20).background(Color(NSColor.textBackgroundColor)).cornerRadius(12).shadow(color: model.animationCurve == .custom ? Color.orange.opacity(0.3) : .clear, radius: 10).animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.animationCurve) }.padding(.top, 4) }.padding(.vertical, 12) } }.formStyle(.grouped) } }
struct HardwareCalibrationView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Screen Target"), footer: Text("Select which physical display panels should draw the notch overlay.")) { HStack { Spacer(); GlassSegmentControl(selection: $model.displayMode).padding(.vertical, 8); Spacer() } }; Section(header: Text("Display Bezels"), footer: Text("Use this diagnostic tool to match the simulated bounds precisely to your hardware sensors.")) { HStack(spacing: 16) { Text("Resting Camouflage Width"); Slider(value: $model.baseNotchWidth, in: 120...260, step: 2); Text("\(Int(model.baseNotchWidth))px").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) }; HStack(spacing: 16) { Text("Resting Corner Radius"); Slider(value: $model.compactCornerRadius, in: 2...30, step: 1); Text("\(Int(model.compactCornerRadius))px").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) } } }.formStyle(.grouped) } }
struct GlassSegmentControl: View {
    @Binding var selection: ScreenDisplayMode
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ScreenDisplayMode.allCases, id: \.self) { mode in
                let isSelected = selection == mode
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = mode
                    }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
        .frame(width: 400)
    }
}
struct BluetoothShape: Shape { func path(in rect: CGRect) -> Path { var path = Path(); let midX = rect.midX; let w = rect.width * 0.25; let h = rect.height * 0.4; let startY = rect.midY - h; let endY = rect.midY + h; path.move(to: CGPoint(x: midX - w, y: startY + h*0.5)); path.addLine(to: CGPoint(x: midX + w, y: endY - h*0.5)); path.addLine(to: CGPoint(x: midX, y: endY)); path.addLine(to: CGPoint(x: midX, y: startY)); path.addLine(to: CGPoint(x: midX + w, y: startY + h*0.5)); path.addLine(to: CGPoint(x: midX - w, y: endY - h*0.5)); return path } }
struct CustomSlider: View { 
    @Binding var value: Double
    var icon: String
    var action: ((Double) -> Void)? = nil
    
    var dynamicIcon: String {
        if icon == "sun.max.fill" {
            if value < 0.2 { return "sun.min.fill" }
            return "sun.max.fill" 
        } else if icon == "speaker.wave.3.fill" {
            if value < 0.1 { return "speaker.fill" }
            if value < 0.4 { return "speaker.wave.1.fill" }
            if value < 0.7 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
        return icon
    }
    
    let sliderWidth: CGFloat = 140
    let sliderHeight: CGFloat = 24
    
    var body: some View { 
        ZStack(alignment: .leading) { 
            Capsule().fill(Color.white.opacity(0.15))
            Capsule().fill(Color.white).frame(width: max(24, sliderWidth * CGFloat(value)))
            Image(systemName: dynamicIcon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(value > 0.15 ? .black : .white)
                .contentTransition(.symbolEffect(.replace))
                .padding(.leading, 8) 
        }
        .frame(width: sliderWidth, height: sliderHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in 
            let newValue = min(max(0, drag.location.x / sliderWidth), 1)
            if abs(value - newValue) > 0.01 {
                value = newValue
                action?(newValue)
            }
        }) 
    } 
}


struct BrightVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        view.material = .popover
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct VerticalSwitcher: View {
    @ObservedObject var model: IslandModel
    var activeState: IslandState
    
    var body: some View {
        VStack(spacing: 12) {
            if model.showAirPodsLocalization { switcherButton(icon: "airpodspro", target: .expandedAirPods) }
            if model.showControlCenter { switcherButton(icon: "switch.2", target: .expandedControls) }
            if model.showMusic { switcherButton(icon: "music.note", target: .expandedMusic) }
            if model.showPhone { switcherButton(icon: "phone", target: .expandedPhone) }
            if model.showNotifications { switcherButton(icon: "bell", target: .expandedNotifications) }
            if model.showAirDrop { switcherButton(icon: "airdrop", target: .expandedAirDrop) }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
                .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 16)))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
    }
    
    @ViewBuilder func switcherButton(icon: String, target: IslandState) -> some View {
        let isActive = (activeState == target)
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                model.state = target
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.white : Color.white.opacity(0.1))
                Image(systemName: icon)
                    .foregroundStyle(isActive ? Color.black : Color.white)
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}


// - Hardware Management Extensions
extension IslandModel {
    func readSystemBrightness() {
        let path = "/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") {
            typealias CBGetUserBrightness = @convention(c) (CGDirectDisplayID) -> Double
            let getBrightness = unsafeBitCast(sym, to: CBGetUserBrightness.self)
            self.brightness = getBrightness(CGMainDisplayID())
        }
    }
    
    func applySystemBrightness(forcedValue: Double? = nil) {
        let targetValue = forcedValue ?? self.brightness
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        if result == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                IODisplaySetFloatParameter(service, 0, "brightness" as CFString, Float(targetValue))
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
        if let handle = dlopen(path, RTLD_LAZY),
           let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            typealias DSSB = @convention(c) (CGDirectDisplayID, Float) -> Int
            let setBrightness = unsafeBitCast(sym, to: DSSB.self)
            _ = setBrightness(CGMainDisplayID(), Float(targetValue))
        }
    }
    
    func readSystemVolume() {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID)
        
        var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var vol: Float32 = 0.0
        var volSize = UInt32(MemoryLayout.size(ofValue: vol))
        if defaultOutputDeviceID != 0 {
            AudioObjectGetPropertyData(defaultOutputDeviceID, &volumeAddress, 0, nil, &volSize, &vol)
            self.volume = Double(vol)
        }
    }
    
    func applySystemVolume(forcedValue: Double? = nil) {
        let targetValue = forcedValue ?? self.volume
        let val = Int(targetValue * 100)
        
        
        // Fast API
        var defaultOutputDeviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID)
        
        var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var floatVol = Float32(targetValue)
        let volSize = UInt32(MemoryLayout.size(ofValue: floatVol))
        if defaultOutputDeviceID != 0 {
            _ = AudioObjectSetPropertyData(defaultOutputDeviceID, &volumeAddress, 0, nil, volSize, &floatVol)
        }
        
        // Bulletproof AppleScript fallback via debounced dispatch
        self.volumeWorkItem?.cancel()
        let item = DispatchWorkItem {
            let script = "set volume output volume \(val)"
            _ = NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
        self.volumeWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.03, execute: item)
}
}
struct ControlButton: View {
    @Binding var isOn: Bool
    var iconOn: String
    var iconOff: String
    var activeTint: Color
    var variableValue: Double? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if let action {
                    action()
                } else {
                    isOn.toggle()
                }
            }
        }) {
            ZStack {
                if iconOn == "bluetooth.custom" {
                    BluetoothShape()
                        .stroke(isOn ? Color.white : Color.gray, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 11, height: 15)
                } else if let value = variableValue, isOn {
                    Image(systemName: iconOn, variableValue: value)
                        .foregroundStyle(.white)
                        .font(.system(size: 14, weight: .bold))
                } else {
                    Image(systemName: isOn ? iconOn : iconOff)
                        .foregroundStyle(isOn ? .white : .gray)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(width: 38, height: 38)
            .background(isOn ? activeTint : Color.white.opacity(0.15))
            .clipShape(Circle())
            .scaleEffect(isOn ? 1.0 : 0.85)
        }
        .buttonStyle(.plain)
    }
}
struct AboutView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section { VStack(spacing: 16) { Image(systemName: "capsule.portrait.fill").font(.system(size: 64)).rotationEffect(.degrees(90)); VStack(spacing: 4) { Text("Dynamic Island for Mac").font(.title.bold()); Text("Version 1.1").font(.subheadline).foregroundStyle(.secondary) }; Text("Brings the fluid Apple iOS Dynamic Island straight into your macOS menu bar.").font(.body).multilineTextAlignment(.center).padding(.horizontal); Button(action: { model.updaterController?.checkForUpdates(nil) }) { Text("Check for Updates...").padding(.horizontal, 8) }.buttonStyle(.borderedProminent).tint(.blue).padding(.top, 8) }.frame(maxWidth: .infinity).padding(.vertical, 24) } }.formStyle(.grouped) } }
struct SystemControlsView: View {
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        Form {
            Section(header: Text("Behavior"), footer: Text("Controls how long the island stays open after you move your mouse away.")) {
                Picker("Auto-Close Behavior", selection: $model.autoCloseBehavior) {
                    ForEach(AutoCloseBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            
            Section(header: Text("System Permissions & Integrations"), footer: Text("All integrations require system permission before making changes or reading data. Disabling an item instantly terminates its active notch activities.")) {
                HStack {
                    Image(systemName: "switch.2")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control Center Quick Toggles")
                            .font(.system(size: 13, weight: .medium))
                        Text("Allows adjusting brightness, volume, Wi-Fi & Bluetooth")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.showControlCenter },
                        set: { newVal in
                            if newVal {
                                model.requestControlCenterPermission { _ in }
                            } else {
                                model.showControlCenter = false
                            }
                        }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.pink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music Access")
                            .font(.system(size: 13, weight: .medium))
                        Text("Connects to Apple Music server for track info & controls")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.showMusic },
                        set: { newVal in
                            if newVal {
                                model.requestMusicPermission { _ in }
                            } else {
                                model.showMusic = false
                                model.isMusicPlaying = false
                            }
                        }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "airpodspro")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirPods & Bluetooth Localization")
                            .font(.system(size: 13, weight: .medium))
                        Text("Finds paired AirPods and displays connection & battery gauges")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.showAirPodsLocalization },
                        set: { newVal in
                            if newVal {
                                model.requestAirPodsPermission { _ in }
                            } else {
                                model.showAirPodsLocalization = false
                                model.airPodsShowingCompact = false
                            }
                        }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Audio Waveforms (Microphone)")
                            .font(.system(size: 13, weight: .medium))
                        Text("Analyzes real-time sound to render live waveforms")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.hasMicPermission },
                        set: { newVal in
                            if newVal {
                                model.requestMicPermission { _ in }
                            } else {
                                model.hasMicPermission = false
                                AudioAnalyzer.shared.stopMonitoring()
                            }
                        }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.red)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Notifications")
                            .font(.system(size: 13, weight: .medium))
                        Text("Floating banners for incoming macOS alerts")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.showNotifications },
                        set: { newVal in
                            if newVal {
                                model.requestNotificationsPermission { _ in }
                            } else {
                                model.showNotifications = false
                            }
                        }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phone & FaceTime")
                            .font(.system(size: 13, weight: .medium))
                        Text("Shows live active call status in Dynamic Notch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.showPhone },
                        set: { newVal in
                            if newVal {
                                model.requestPhonePermission { _ in }
                            } else {
                                model.showPhone = false
                            }
                        }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "airdrop")
                        .foregroundStyle(.cyan)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirDrop Sharing")
                            .font(.system(size: 13, weight: .medium))
                        Text("Displays active transfer progress in the notch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.showAirDrop },
                        set: { newVal in
                            if newVal {
                                model.requestAirDropPermission { _ in }
                            } else {
                                model.showAirDrop = false
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }
            
            Section(footer: Text("If an item was denied previously in macOS, open Privacy & Security Settings to grant access.")) {
                Button(action: { model.openSystemPrivacySettings() }) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                        Text("Open macOS Privacy & Security Settings...")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
struct LiveActivitiesView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Global Settings"), footer: Text("Projects a lush, vibrant colored shadow directly onto the ambient background perfectly matched to the dominant color of the active Apple Music track artwork.")) { Toggle("Live Background Glow Effect", isOn: $model.enableArtworkGlow) }; Section(header: Text("Active Layout Modules")) { HStack { Image(systemName: "music.note.list").foregroundStyle(.orange).frame(width: 24); Text("Apple Music Overlay"); Spacer(); Button(model.state == .expandedMusic ? "Terminate" : "Simulate") { model.toggleState(.expandedMusic) } }; HStack { Image(systemName: "bag.fill").foregroundStyle(.green).frame(width: 24); Text("Food Delivery"); Spacer(); Button(model.state == .expandedFood ? "Terminate" : "Simulate") { model.toggleState(.expandedFood) } } } }.formStyle(.grouped) } }

struct FlipTransitionModifier: ViewModifier {
    var angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0.0, y: 1.0, z: 0.0), perspective: 0.5)
            .opacity(abs(angle) >= 89.9 ? 0 : 1.0)
    }
}
extension AnyTransition {
    static func flip3D(isForward: Bool) -> AnyTransition {
        return .asymmetric(
            insertion: .modifier(
                active: FlipTransitionModifier(angle: isForward ? -90 : 90),
                identity: FlipTransitionModifier(angle: 0)
            ),
            removal: .modifier(
                active: FlipTransitionModifier(angle: isForward ? 90 : -90),
                identity: FlipTransitionModifier(angle: 0)
            )
        )
    }
}


struct LiquidScrubber: View {
    @ObservedObject var model = IslandModel.shared
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0.0
    
    let scrubberWidth: CGFloat = 200
    let scrubberHeight: CGFloat = 24

    var body: some View {
        let currentProgress = isDragging ? dragProgress : (model.playbackPosition / model.trackDuration)
        let safeProgress = currentProgress.isNaN ? 0.0 : max(0.0, min(1.0, currentProgress))
        let elapsed = Int(safeProgress * model.trackDuration)
        let remaining = Int(model.trackDuration) - elapsed
        let currentTrackWidth = max(0, CGFloat(safeProgress) * scrubberWidth)
        
        HStack(spacing: 10) {
            Text(formatTime(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, alignment: .trailing)
            
            ZStack(alignment: .leading) {
                // Base Track
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: scrubberWidth, height: 6)
                    
                // Fill Track
                Capsule()
                    .fill(Color.white)
                    .frame(width: currentTrackWidth, height: 6)
                    .animation(!isDragging ? .spring(response: 0.25, dampingFraction: 1.0) : .none, value: safeProgress)
                    
                // Thumb
                Capsule()
                    .fill(Color.white)
                    .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
                    .shadow(color: model.artworkColor.opacity(0.35), radius: isDragging ? 7 : 3, x: 0, y: 2)
                    .frame(width: isDragging ? 24 : 10, height: isDragging ? 16 : 10)
                    .offset(x: min(max(0, currentTrackWidth - (isDragging ? 12 : 5)), scrubberWidth - (isDragging ? 24 : 10)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0.2), value: isDragging)
            }
            .frame(width: scrubberWidth, height: scrubberHeight, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging { isDragging = true }
                        dragProgress = Double(min(max(0, value.location.x / scrubberWidth), 1))
                    }
                    .onEnded { value in
                        let finalProgress = Double(min(max(0, value.location.x / scrubberWidth), 1))
                        let newPos = finalProgress * model.trackDuration
                        DispatchQueue.global(qos: .userInitiated).async {
                            _ = NSAppleScript(source: "tell application \"Music\" to set player position to \(newPos)")?.executeAndReturnError(nil)
                        }
                        model.playbackPosition = newPos
                        dragProgress = finalProgress
                        isDragging = false
                    }
            )
            
            Text("-" + formatTime(remaining))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 38, alignment: .leading)
        }
    }
    
    func formatTime(_ totalSeconds: Int) -> String {
        let safeSecs = max(0, totalSeconds)
        let m = safeSecs / 60
        let s = safeSecs % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct AirPodsListeningModeSlider: View {
    @ObservedObject var model: IslandModel
    
    // Mode 2: Noise Cancellation, Mode 3: Off, Mode 1 or 4: Transparency
    let modes = [2, 3, 4]
    let icons = ["earbuds", "speaker.slash.fill", "waveform"]
    let titles = ["ANC", "Off", "Transp."]
    
    var body: some View {
        VStack(spacing: 4) {
            Text("AirPods Mode")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
            
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let modeVal = modes[i]
                    let isSelected = model.listeningMode == modeVal
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            model.setAirPodsMode(modeVal)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: icons[i])
                                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                            Text(titles[i])
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .frame(width: 44, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.white : Color.white.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)
        }
        .frame(width: 146)
    }
}

struct SettingsWindowPreviewer: View {
    @ObservedObject var model: IslandModel
    
    var body: some View {
        ZStack {
            // Simulated macOS Desktop Wallpaper
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.35, blue: 0.75),
                        Color(red: 0.65, green: 0.25, blue: 0.65),
                        Color(red: 0.95, green: 0.55, blue: 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Desktop shapes to show off transparency and glass blur
                Circle()
                    .fill(Color.yellow.opacity(0.7))
                    .frame(width: 80, height: 80)
                    .offset(x: -70, y: -20)
                
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.cyan.opacity(0.6))
                    .frame(width: 130, height: 70)
                    .offset(x: 80, y: 30)
                
                // Mini Simulated Settings Window
                HStack(spacing: 0) {
                    // Mini Sidebar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Circle().fill(Color.yellow).frame(width: 5, height: 5)
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                        }
                        .padding(.bottom, 4)
                        
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.3)).frame(width: 35, height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.2)).frame(width: 45, height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.2)).frame(width: 30, height: 4)
                        Spacer()
                    }
                    .padding(8)
                    .frame(width: 75)
                    .background(Color.black.opacity(0.35))
                    
                    Divider().opacity(0.3)
                    
                    // Mini Content Pane with selected background style applied!
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.4)).frame(width: 70, height: 6)
                        HStack {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(height: 18)
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(height: 18)
                        }
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(height: 28)
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        previewBackgroundLayer(style: model.settingsBackgroundStyle, opacity: model.settingsWindowOpacity, glass: model.settingsGlassIntensity)
                    )
                }
                .frame(width: 360, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.2 + (model.settingsGlassIntensity * 0.3)), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
            }
        }
    }
    
    @ViewBuilder func previewBackgroundLayer(style: SettingsBackgroundStyle, opacity: Double, glass: Double) -> some View {
        ZStack {
            switch style {
            case .liquidGlass:
                Color.black.opacity(0.45 * opacity)
                LinearGradient(colors: [Color.white.opacity(0.15 * glass), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .obsidian:
                Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.92 * opacity)
            case .aurora:
                LinearGradient(colors: [Color.purple.opacity(0.6 * opacity), Color.teal.opacity(0.5 * opacity)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .sunset:
                LinearGradient(colors: [Color.orange.opacity(0.55 * opacity), Color.pink.opacity(0.5 * opacity)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .slate:
                Color(red: 0.18, green: 0.20, blue: 0.24).opacity(0.85 * opacity)
            }
        }
    }
}

struct BackgroundSettingsView: View {
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top macOS-style Wallpaper & Window Previewer
                VStack(alignment: .leading, spacing: 10) {
                    Text("Live Window Preview")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    SettingsWindowPreviewer(model: model)
                        .frame(height: 190)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 28)
                
                // Settings Form Controls
                Form {
                    Section(header: Text("Theme Preset")) {
                        Picker("Background Style", selection: $model.settingsBackgroundStyle) {
                            ForEach(SettingsBackgroundStyle.allCases) { style in
                                Label(style.rawValue, systemImage: style.icon).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    Section(
                        header: Text("Liquid Glass & Materials"),
                        footer: Text("Fine-tunes the liquid glass blur dispersion, specular edge sheen, and background distortion.")
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Liquid Glass Intensity")
                                Spacer()
                                Text("\(Int(model.settingsGlassIntensity * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $model.settingsGlassIntensity, in: 0.0...1.0, step: 0.05)
                        }
                    }
                    
                    Section(
                        header: Text("Window Transparency"),
                        footer: Text("Adjusts how translucent the settings window is against your desktop background and open apps.")
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Desktop Transparency")
                                Spacer()
                                Text("\(Int((1.0 - model.settingsWindowOpacity) * 100))% transparent")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $model.settingsWindowOpacity, in: 0.25...1.0, step: 0.05)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minHeight: 320)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}
