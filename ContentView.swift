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

                if !model.isExpanded, model.isMusicPlaying {
                    compactMusicActivity
                        .frame(width: model.width, height: model.physicalNotchHeight)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
                HStack(spacing: 16) { Image(systemName: "airpodspro"); Text("AirPods Pro Locating...").font(.headline) }.foregroundColor(.white)
            } else if model.state == .expandedPhone {
                HStack(spacing: 16) { Image(systemName: "phone.fill").foregroundColor(.green); Text("Incoming Call...").font(.headline).foregroundColor(.white) }
            } else if model.state == .expandedNotifications {
                HStack(spacing: 16) { Image(systemName: "bell.fill").foregroundColor(.red); Text("No New Notifications").font(.headline).foregroundColor(.white) }
            } else if model.state == .expandedAirDrop {
                HStack(spacing: 16) { Image(systemName: "airdrop"); Text("AirDrop Enabled").font(.headline) }.foregroundColor(.white)
            } else {
                HStack(spacing: 16) {
                    HStack(spacing: 10) { 
                        ControlButton(isOn: $model.isWifiOn, iconOn: "wifi", iconOff: "wifi.slash", activeTint: .blue, variableValue: Double(model.wifiBars) / 3.0, action: model.toggleWiFi)
                        ControlButton(isOn: $model.isBluetoothOn, iconOn: "bluetooth.custom", iconOff: "bluetooth.custom", activeTint: .blue, action: model.toggleBluetooth) 
                    }
                    VStack(spacing: 8) { 
                        CustomSlider(value: $model.brightness, icon: "sun.max.fill") { val in model.applySystemBrightness(forcedValue: val) }
                        CustomSlider(value: $model.volume, icon: "speaker.wave.3.fill") { val in model.applySystemVolume(forcedValue: val) } 
                    }.frame(width: 140)
                    if model.airPodsConnected {
                        AirPodsListeningModeSlider(model: model)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
        .opacity(showsExpandedControls ? 1 : 0)
        .offset(y: showsExpandedControls ? 0 : -72)
        .allowsHitTesting(showsExpandedControls)
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
        if isMusicPlaying {
            return baseNotchWidth + 96
        }
        return airPodsShowingCompact ? baseNotchWidth + 60 : baseNotchWidth
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
    @Published var airPodsShowingCompact: Bool = false
    @Published var airPodsConnected: Bool = false {
        didSet {
            if airPodsConnected {
                airPodsShowingCompact = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { self.airPodsShowingCompact = false }
            } else { airPodsShowingCompact = false }
        }
    }
    
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
    
    @Published var physicalNotchHeight: CGFloat = 34 
    @Published var baseNotchWidth: CGFloat = 200 
    @Published var displayMode: ScreenDisplayMode = .both
    
    var updaterController: SPUStandardUpdaterController?
    
    @Published var isScreenTransitioning: Bool = false
    private var transitionDebounceTask: Task<Void, Never>? = nil

    init() {
        readSystemBrightness()
        readSystemVolume()
        startWifiMonitoring()
        startMusicMonitoring()
        startScreenTransitionMonitoring()
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

    @Published var listeningMode: Int = 3
    func setAirPodsMode(_ mode: Int) {
        self.listeningMode = mode
        DispatchQueue.global(qos: .userInitiated).async {
            guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            let sel = Selector("setListeningMode:")
            typealias SetListeningModeIMP = @convention(c) (AnyObject, Selector, UInt8) -> Bool
            for device in devices where device.isConnected() && device.responds(to: sel) {
                let imp = device.method(for: sel)
                let function = unsafeBitCast(imp, to: SetListeningModeIMP.self)
                _ = function(device, sel, UInt8(mode))
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


enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance = "Appearance & Physics"; case display = "Hardware Calibration"; case liveActivities = "Live Activities"; case systemControls = "System Controls"; case about = "About"
    var id: String { rawValue }
    var icon: String { switch self { case .appearance: return "sparkles"; case .display: return "display"; case .liveActivities: return "bolt.fill"; case .systemControls: return "switch.2"; case .about: return "info.circle" } }
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
    @State private var selectedPane: SettingsPane = .appearance
    var body: some View { HStack(spacing: 0) { VStack(alignment: .leading, spacing: 4) { Text("Preferences").font(.headline).padding(.horizontal, 14).padding(.top, 28).padding(.bottom, 12); ForEach(SettingsPane.allCases) { pane in Button(action: { selectedPane = pane }) { HStack(spacing: 12) { Image(systemName: pane.icon).frame(width: 20); Text(pane.rawValue); Spacer() }.padding(.vertical, 8).padding(.horizontal, 14).background(selectedPane == pane ? Color.accentColor.opacity(0.15) : Color.clear).foregroundStyle(selectedPane == pane ? Color.accentColor : Color.primary).cornerRadius(6) }.buttonStyle(.plain).padding(.horizontal, 8) }; Spacer() }.frame(width: 220, alignment: .leading).frame(maxHeight: .infinity).background(.thinMaterial); Divider().ignoresSafeArea(); VStack(spacing: 0) { switch selectedPane { case .appearance: AnimationSettingsView(); case .display: HardwareCalibrationView(); case .liveActivities: LiveActivitiesView(); case .systemControls: SystemControlsView(); case .about: AboutView() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(NSColor.controlBackgroundColor)) }.ignoresSafeArea().frame(width: 780, height: 640) }
}

struct BezierGraph: View {
    @ObservedObject var model: IslandModel
    
    var body: some View {
        GeometryReader { geo in
            let pad_x: CGFloat = 20; let pad_y: CGFloat = 70; let w = geo.size.width; let h = geo.size.height
            let drawW = max(1, w - (pad_x * 2)); let drawH = max(1, h - (pad_y * 2))
            
            let c1 = model.animationCurve == .custom ? model.customC1 : model.animationCurve.defaultC1
            let c2 = model.animationCurve == .custom ? model.customC2 : model.animationCurve.defaultC2
            let pStart = CGPoint(x: pad_x, y: pad_y + drawH); let pEnd = CGPoint(x: pad_x + drawW, y: pad_y)
            let p1 = CGPoint(x: pad_x + (c1.x * drawW), y: pad_y + (1 - c1.y) * drawH)
            let p2 = CGPoint(x: pad_x + (c2.x * drawW), y: pad_y + (1 - c2.y) * drawH)
            
            Path { p in p.move(to: pStart); p.addLine(to: CGPoint(x: pEnd.x, y: pStart.y)); p.addLine(to: pEnd); p.addLine(to: CGPoint(x: pStart.x, y: pEnd.y)); p.closeSubpath() }
                .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
            
            Path { p in p.move(to: pStart); p.addLine(to: p1) }.stroke(model.animationCurve == .custom ? Color.orange.opacity(0.6) : Color.primary.opacity(0.25), lineWidth: 1.5)
            Path { p in p.move(to: pEnd); p.addLine(to: p2) }.stroke(model.animationCurve == .custom ? Color.orange.opacity(0.6) : Color.primary.opacity(0.25), lineWidth: 1.5)
            Path { path in path.move(to: pStart); path.addCurve(to: pEnd, control1: p1, control2: p2) }.stroke(model.animationCurve == .custom ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            
            Circle().fill(Color.accentColor).frame(width: 8, height: 8).position(pStart)
            Circle().fill(Color.accentColor).frame(width: 8, height: 8).position(pEnd)
            Circle().fill(Color.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 3).overlay(Circle().stroke(model.animationCurve == .custom ? Color.orange : Color.gray, lineWidth: 2)).position(p1)
            Circle().fill(Color.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 3).overlay(Circle().stroke(model.animationCurve == .custom ? Color.orange : Color.gray, lineWidth: 2)).position(p2)
                
            Color.black.opacity(0.001).frame(width: w, height: h).contentShape(Rectangle()).gesture(
                    DragGesture(minimumDistance: 0).onChanged { val in model.makeCustomIfNeeded(); let nx = min(max(0, (val.location.x - pad_x) / drawW), 1); let maxY = 1 + (pad_y / drawH); let minY = 0 - (pad_y / drawH); let ny = min(max(minY, 1 - ((val.location.y - pad_y) / drawH)), maxY); if val.startLocation.x < w / 2 { model.customC1 = CGPoint(x: nx, y: ny) } else { model.customC2 = CGPoint(x: nx, y: ny) } }
                )
        }
    }
}

struct AnimationSettingsView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Morphing Physics"), footer: Text("Drag anywhere inside the Sandbox Graph to instantly trace out custom trajectories.")) { VStack(alignment: .leading, spacing: 30) { VStack(alignment: .leading, spacing: 18) { Picker("Curve Algorithm", selection: $model.animationCurve) { ForEach(AnimationCurve.allCases, id: \.self) { curve in Text(curve.rawValue).tag(curve) } }; VStack(alignment: .leading, spacing: 6) { HStack { Text("Duration Time"); Spacer(); Text(String(format: "%.1fs", model.animationDuration)).monospacedDigit().foregroundStyle(.secondary) }; Slider(value: $model.animationDuration, in: 0.1...1.5, step: 0.1) } }; VStack(alignment: .leading) { Text(model.animationCurve == .custom ? "Live Physics Sandbox" : "System Easing Math").font(.subheadline.weight(.medium)).foregroundStyle(model.animationCurve == .custom ? .orange : .secondary).padding(.bottom, 6); BezierGraph(model: model).frame(height: 250).padding(.horizontal, 26).padding(.vertical, 20).background(Color(NSColor.textBackgroundColor)).cornerRadius(12).shadow(color: model.animationCurve == .custom ? Color.orange.opacity(0.3) : .clear, radius: 10).animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.animationCurve) }.padding(.top, 4) }.padding(.vertical, 12) } }.formStyle(.grouped) } }
struct HardwareCalibrationView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Screen Target"), footer: Text("Select which physical display panels should draw the notch overlay.")) { HStack { Spacer(); GlassSegmentControl(selection: $model.displayMode).padding(.vertical, 8); Spacer() } }; Section(header: Text("Display Bezels"), footer: Text("Use this diagnostic tool to match the simulated bounds precisely to your hardware sensors.")) { HStack(spacing: 16) { Text("Resting Camouflage Width"); Slider(value: $model.baseNotchWidth, in: 120...260, step: 2); Text("\(Int(model.baseNotchWidth))px").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) }; HStack(spacing: 16) { Text("Resting Corner Radius"); Slider(value: $model.compactCornerRadius, in: 2...30, step: 1); Text("\(Int(model.compactCornerRadius))px").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) } } }.formStyle(.grouped) } }
struct GlassSegmentControl: View {
    @Binding var selection: ScreenDisplayMode; @GestureState private var isDragging: Bool = false
    var body: some View {
        GlassEffectContainer { ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)); GeometryReader { geo in let segmentWidth = (geo.size.width - 8) / CGFloat(ScreenDisplayMode.allCases.count); let index = CGFloat(ScreenDisplayMode.allCases.firstIndex(of: selection) ?? 0); RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.01)).glassEffect().scaleEffect(isDragging ? 1.05 : 1.0).shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 5 : 2, x: 0, y: isDragging ? 3 : 1).frame(width: segmentWidth, height: geo.size.height - 8).offset(x: 4 + (index * segmentWidth), y: 4).animation(.spring(response: 0.3, dampingFraction: 0.65), value: selection).animation(.spring(response: 0.3, dampingFraction: 0.65), value: isDragging) }; HStack(spacing: 0) { ForEach(ScreenDisplayMode.allCases, id: \.self) { mode in let isSelected = selection == mode; Text(mode.rawValue).font(.system(size: 13, weight: isSelected ? .bold : .medium)).foregroundStyle(isSelected ? Color.primary : Color.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).scaleEffect(isSelected && isDragging ? 1.05 : 1.0).contentShape(Rectangle()).onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = mode } } } } }.frame(width: 380, height: 38).gesture(DragGesture(minimumDistance: 0).updating($isDragging) { _, state, _ in state = true }.onChanged { value in let w: CGFloat = 380; let index = Int(max(0, min(value.location.x / (w / 3.0), 2.0))); let newMode = ScreenDisplayMode.allCases[index]; if selection != newMode { withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { selection = newMode } } }) }
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
    
    var body: some View { 
        GeometryReader { geo in 
            ZStack(alignment: .leading) { 
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(Color.white).frame(width: max(24, geo.size.width * CGFloat(value)))
                Image(systemName: dynamicIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(value > 0.15 ? .black : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.leading, 8) 
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in 
                let newValue = min(max(0, drag.location.x / geo.size.width), 1)
                if abs(value - newValue) > 0.01 {
                    value = newValue
                    action?(newValue)
                }
            }) 
        }
        .frame(height: 24) 
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
struct SystemControlsView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { 
    Section(header: Text("Behavior"), footer: Text("Controls how long the island stays open after you move your mouse away.")) { 
        Picker("Auto-Close Behavior", selection: $model.autoCloseBehavior) { 
            ForEach(AutoCloseBehavior.allCases) { Text($0.rawValue).tag($0) } 
        }.pickerStyle(.menu) 
    }
    Section(header: Text("Visible Items"), footer: Text("Some items require permission.")) {
        HStack { Image(systemName: "airpodspro").frame(width: 24); Toggle("AirPods Localization", isOn: $model.showAirPodsLocalization) }
        HStack { Image(systemName: "switch.2").frame(width: 24); Toggle("Control Center Controls", isOn: $model.showControlCenter) }
        HStack { Image(systemName: "music.note").frame(width: 24); Toggle("Music", isOn: $model.showMusic) }
        HStack { Image(systemName: "phone").frame(width: 24); Toggle("Phone", isOn: $model.showPhone) }
        HStack { Image(systemName: "bell").frame(width: 24); Toggle("Notifications", isOn: $model.showNotifications) }
        HStack { Image(systemName: "airdrop").frame(width: 24); Toggle("AirDrop", isOn: $model.showAirDrop) }
    }
}.formStyle(.grouped) } }
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

    var body: some View {
        let currentProgress = isDragging ? dragProgress : (model.playbackPosition / model.trackDuration)
        let safeProgress = currentProgress.isNaN ? 0.0 : max(0.0, min(1.0, currentProgress))
        let elapsed = Int(safeProgress * model.trackDuration)
        let remaining = Int(model.trackDuration) - elapsed
        
        HStack(spacing: 12) {
            Text(formatTime(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 34, alignment: .trailing)
            
            GeometryReader { geo in
                let currentWidth = max(0, CGFloat(safeProgress) * geo.size.width)
                
                ZStack(alignment: .leading) {
                    // Base Track (Constant height 6)
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 6)
                        
                    // Fill Track (Constant height 6)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: currentWidth, height: 6)
                        .animation(!isDragging ? .spring(response: 0.25, dampingFraction: 1.0) : .none, value: safeProgress)
                        
                    // Liquid Glass Thumb
                    Group {
                        if #available(macOS 26.0, *) {
                            Capsule()
                                .fill(Color.white.opacity(isDragging ? 0.12 : 0.22))
                                .glassEffect(.clear.tint(model.artworkColor.opacity(0.32)).interactive(), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.95), .white.opacity(0.28)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
                        }
                    }
                    .shadow(color: model.artworkColor.opacity(0.35), radius: isDragging ? 7 : 3, x: 0, y: 2)
                    .frame(width: isDragging ? 32 : 10, height: isDragging ? 16 : 10)
                    .offset(x: currentWidth - (isDragging ? 16 : 5))
                    .animation(.spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0.2), value: isDragging)
                    .animation(!isDragging ? .spring(response: 0.25, dampingFraction: 1.0) : .none, value: safeProgress)
                }
                .frame(height: 24, alignment: .center) // safe hit box
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0.2)) {
                                    isDragging = true
                                }
                            }
                            let percent = max(0, min(1, value.location.x / geo.size.width))
                            dragProgress = percent
                        }
                        .onEnded { value in
                            let percent = max(0, min(1, value.location.x / geo.size.width))
                            let newPos = percent * model.trackDuration
                            DispatchQueue.global(qos: .userInitiated).async {
                                _ = NSAppleScript(source: "tell application \"Music\" to set player position to \(newPos)")?.executeAndReturnError(nil)
                            }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0.2)) {
                                isDragging = false
                            }
                            // Only update locally if needed, model syncing handles state perfectly
                            model.playbackPosition = newPos 
                        }
                )
            }
            .frame(height: 24) 
            
            Text("-" + formatTime(remaining))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .contentTransition(.numericText())
                .frame(width: 40, alignment: .leading)
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
    @GestureState private var isDragging: Bool = false
    
    let modes = [2, 4, 3]
    let icons = ["waveform.path", "waveform.path.badge.plus", "waveform"]
    
    var body: some View {
        VStack(spacing: 6) {
            Text("Listening Mode").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            
            ZStack {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.1))
                    
                    GeometryReader { geo in 
                        let segmentWidth = (140 - 8) / 3.0
                        let index = CGFloat(modes.firstIndex(of: model.listeningMode) ?? 0)
                        
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                            .glassEffect()
                            .scaleEffect(isDragging ? 1.05 : 1.0)
                            .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 5 : 2, x: 0, y: isDragging ? 3 : 1)
                            .frame(width: segmentWidth, height: geo.size.height - 8)
                            .offset(x: 4 + (index * segmentWidth), y: 4)
                            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: model.listeningMode)
                            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isDragging)
                    }
                    
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { i in 
                            let isSelected = model.listeningMode == modes[i]
                            Image(systemName: icons[i])
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .scaleEffect(isSelected && isDragging ? 1.05 : 1.0)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        model.setAirPodsMode(modes[i])
                                    }
                                }
                        }
                    }
                }
                .frame(width: 140, height: 38)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            let w: CGFloat = 140
                            let index = Int(max(0, min(value.location.x / (w / 3.0), 2.0)))
                            let newMode = modes[index]
                            if model.listeningMode != newMode {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                                    model.setAirPodsMode(newMode)
                                }
                            }
                        }
                )
            }
        }
    }
}
