
struct ArcShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

struct AirDropSymbolView: View {
    var size: CGFloat = 24
    var color: Color = .cyan
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size * 0.22, height: size * 0.22)
            
            ArcShape(startAngle: .degrees(130), endAngle: .degrees(50))
                .stroke(color, style: StrokeStyle(lineWidth: max(1.2, size * 0.085), lineCap: .round))
                .frame(width: size * 0.50, height: size * 0.50)
            
            ArcShape(startAngle: .degrees(130), endAngle: .degrees(50))
                .stroke(color, style: StrokeStyle(lineWidth: max(1.2, size * 0.085), lineCap: .round))
                .frame(width: size * 0.76, height: size * 0.76)
            
            ArcShape(startAngle: .degrees(130), endAngle: .degrees(50))
                .stroke(color, style: StrokeStyle(lineWidth: max(1.2, size * 0.085), lineCap: .round))
                .frame(width: size * 1.0, height: size * 1.0)
        }
        .frame(width: size, height: size)
    }
}

struct AirDropPerson: Identifiable {
    let id = UUID()
    let name: String
    let device: String
    let deviceIcon: String
    let profileImage: NSImage?
    let initials: String
    let color: Color
}

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
        // Fast hardware-assisted 1x1 downsampling for instant zero-lag color extraction
        guard let tiffData = self.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiffData as CFData, nil) else {
            return .orange
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .orange
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bitmapData: [UInt8] = [0, 0, 0, 0]
        let context = CGContext(
            data: &bitmapData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .low
        context?.draw(thumbnail, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let multi: Double = 1.35
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
                    // 1. Dynamic Notch Theme Base Underneath
                    let cornerRadius = model.isExpanded ? 24.0 : model.compactCornerRadius
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius, topTrailingRadius: 0, style: .continuous)
                    
                    if !model.isExpanded && model.notchCompactAlwaysBlack {
                        shape.fill(Color.black)
                    } else {
                        switch model.notchTheme {
                        case .classicBlack:
                            shape.fill(Color.black)
                            
                        case .iosGlassCapsule:
                            // Authentic iOS Siri Smoked Glass Capsule Acrylic
                            ZStack {
                                shape.fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.92 * model.notchGlassOpacity),
                                            Color(red: 0.14, green: 0.13, blue: 0.16).opacity(0.72 * model.notchGlassOpacity),
                                            Color(white: 0.22).opacity(0.42 * model.notchGlassOpacity)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                shape.fill(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.18 * model.notchGlassOpacity), Color.clear],
                                        center: .top,
                                        startRadius: 10,
                                        endRadius: 180
                                    )
                                )
                            }
                            .overlay(
                                shape.stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.20 * model.notchGlowIntensity),
                                            Color.white.opacity(0.50 * model.notchGlowIntensity),
                                            Color.white.opacity(0.80 * model.notchGlowIntensity)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.2
                                )
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 10, y: 5)
                            
                        case .liquidGlass:
                            ZStack {
                                shape.fill(Color.black.opacity(0.85))
                                shape.fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.20 * model.notchGlassOpacity), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                            .overlay(
                                shape.stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35 * model.notchGlassOpacity), Color.white.opacity(0.10 * model.notchGlassOpacity)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.0
                                )
                            )
                        case .neonCyber:
                            ZStack {
                                shape.fill(Color(red: 0.05, green: 0.02, blue: 0.10))
                            }
                            .overlay(
                                shape.stroke(
                                    LinearGradient(
                                        colors: [Color(red: 0.0, green: 0.9, blue: 1.0).opacity(model.notchGlowIntensity), Color(red: 1.0, green: 0.1, blue: 0.6).opacity(model.notchGlowIntensity)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .shadow(color: Color.cyan.opacity(0.6 * model.notchGlowIntensity), radius: 6)
                            )
                        case .titaniumFrost:
                            ZStack {
                                shape.fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                shape.fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            }
                            .overlay(
                                shape.stroke(Color.white.opacity(0.25), lineWidth: 1.0)
                            )
                        case .auroraGlow:
                            ZStack {
                                shape.fill(Color(red: 0.04, green: 0.03, blue: 0.08))
                            }
                            .overlay(
                                shape.stroke(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(model.notchGlowIntensity), Color.teal.opacity(model.notchGlowIntensity)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .shadow(color: Color.purple.opacity(0.5 * model.notchGlowIntensity), radius: 6)
                            )
                        case .goldenTwilight:
                            ZStack {
                                shape.fill(Color(red: 0.08, green: 0.04, blue: 0.02))
                            }
                            .overlay(
                                shape.stroke(
                                    LinearGradient(
                                        colors: [Color.orange.opacity(model.notchGlowIntensity), Color.pink.opacity(model.notchGlowIntensity)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .shadow(color: Color.orange.opacity(0.5 * model.notchGlowIntensity), radius: 6)
                            )
                        }
                    }
                    
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
                    
                    // 3. AirDrop File/Photo Overflow Ambient Gradient across the whole Notch!
                    if (model.isExpanded && model.state == .expandedAirDrop) || model.isAirDropTargeted {
                        ZStack {
                            if let thumb = model.droppedFileThumbnail {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: model.width, height: model.height)
                                    .blur(radius: 28)
                                    .opacity(0.42)
                                    .clipped()
                            }
                            LinearGradient(
                                colors: [
                                    model.droppedFileColor.opacity(0.48),
                                    model.droppedFileColor.opacity(0.22),
                                    Color.black.opacity(0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: model.width, height: model.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous)
                        .stroke(Color.white.opacity(model.isExpanded ? 0.2 : 0.05), lineWidth: 0.5)
                )
                // Ambient Colored Glow around notch
                .shadow(
                    color: ((model.isExpanded && model.state == .expandedAirDrop) || model.isAirDropTargeted)
                        ? model.droppedFileColor.opacity(0.65)
                        : (((model.isMusicPlaying || model.state == .expandedMusic) && model.enableArtworkGlow) 
                            ? model.artworkColor.opacity(model.isExpanded ? 0.45 : 0.65) 
                            : Color.black.opacity(0.35)), 
                    radius: model.isExpanded ? 20 : 10, 
                    x: 0, 
                    y: model.isExpanded ? 6 : 3
                )

                if !model.isExpanded {
                    if model.airPodsShowingCompact {
                        compactAirPodsActivity
                            .frame(width: model.width, height: model.physicalNotchHeight)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                    } else if model.isMusicPlaying {
                        compactMusicActivity
                            .frame(width: model.width, height: model.physicalNotchHeight)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                    }
                }
                
                // Content Layer & Vertically Centered Switcher inside the Notch
                VStack(spacing: 0) {
                    Spacer().frame(height: model.physicalNotchHeight)
                    
                    if model.isAirDropTargeted && model.state != .expandedAirDrop {
                        // Large Spacious AirDrop Dropzone
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.cyan.opacity(0.18))
                                    .frame(width: 44, height: 44)
                                AirDropSymbolView(size: 26, color: .cyan)
                            }
                            
                            Text("Drop Files to AirDrop")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Release anywhere to select nearby recipients")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.cyan.opacity(0.8), style: StrokeStyle(lineWidth: 1.8, dash: [6, 4]))
                                .padding(6)
                        )
                    } else if model.isExpanded {
                        if model.state == .expandedAirDrop {
                            airDropExpandedView
                        } else {
                            ZStack(alignment: .center) {
                                // Main Content View: Dead-Centered with physical notch & perfectly symmetrical margins
                                Group {
                                    if model.state == .expandedMusic {
                                        musicView
                                    } else if model.state == .expandedFood {
                                        foodView
                                    } else {
                                        controlsView
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.leading, 20)
                                .padding(.trailing, 46) // Balances the right-side switcher dock
                                
                                // Right Side: Compact Liquid Glass Vertical Switcher
                                HStack {
                                    Spacer()
                                    VerticalSwitcher(model: model, activeState: model.state)
                                        .padding(.trailing, 8)
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                    }
                }
                .frame(width: model.width, height: model.height, alignment: .top)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: model.isExpanded ? 24 : model.compactCornerRadius, bottomTrailingRadius: model.isExpanded ? 24 : model.compactCornerRadius, topTrailingRadius: 0, style: .continuous))
                .compositingGroup()
                .onDrop(of: [.fileURL, .item], isTargeted: $model.isAirDropTargeted) { providers in
                    // 1. Try reading URLs immediately from drag pasteboard
                    let pboard = NSPasteboard(name: .drag)
                    if let directURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !directURLs.isEmpty {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            model.isAirDropTargeted = false
                            model.droppedAirDropFiles = directURLs
                            model.state = .expandedAirDrop
                        }
                        return true
                    }
                    
                    // 2. Asynchronous provider fallback
                    var loadedURLs: [URL] = []
                    let group = DispatchGroup()
                    
                    for provider in providers {
                        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                            group.enter()
                            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                                if let url = item as? URL {
                                    DispatchQueue.main.async { loadedURLs.append(url) }
                                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                    DispatchQueue.main.async { loadedURLs.append(url) }
                                }
                                group.leave()
                            }
                        }
                    }
                    
                    group.notify(queue: .main) {
                        let finalURLs = loadedURLs.isEmpty ? [URL(fileURLWithPath: "/Users/Shared/SharedFile")] : loadedURLs
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            model.isAirDropTargeted = false
                            model.droppedAirDropFiles = finalURLs
                            model.state = .expandedAirDrop
                        }
                    }
                    return true
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
            // Left ear: Authentic 3D Flipping AirPods
            AirPods3DView()
                .frame(width: 26, height: 26)
            
            Spacer(minLength: 0)
            
            // Right ear: Clean Circular Battery Ring
            CircularBatteryGauge(batteryLevel: model.airPodsBatteryLevel)
                .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 14)
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
                    HStack(spacing: 16) { AirDropSymbolView(size: 20, color: .cyan); Text("AirDrop Enabled").font(.headline) }.foregroundColor(.white)
                } else {
                    disabledFeatureNotice("AirDrop Sharing Disabled")
                }
            } else {
                if model.showControlCenter {
                    VStack(spacing: 8) {
                        // 1. Top Row: WiFi & Bluetooth Cards with Titles & Live Status
                        HStack(spacing: 8) {
                            ConnectivityCard(
                                title: "Wi-Fi",
                                subtitle: model.isWifiOn ? model.wifiSSID : "Off",
                                icon: "wifi",
                                isOn: model.isWifiOn,
                                activeTint: .blue,
                                variableValue: Double(model.wifiBars) / 3.0,
                                action: model.toggleWiFi
                            )
                            
                            ConnectivityCard(
                                title: "Bluetooth",
                                subtitle: model.isBluetoothOn ? "On" : "Off",
                                icon: "bluetooth.custom",
                                isOn: model.isBluetoothOn,
                                activeTint: .blue,
                                action: model.toggleBluetooth
                            )
                        }
                        .frame(width: 340)
                        
                        // 2. Middle Row: Brightness Slider with Title
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Brightness")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                                .padding(.leading, 2)
                            
                            CustomSlider(value: $model.brightness, icon: "sun.max.fill") { val in 
                                model.applySystemBrightness(forcedValue: val) 
                            }
                            .frame(width: 340, height: 28)
                        }
                        .frame(width: 340)
                        
                        // 3. Middle Row: Volume Slider with Title
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Volume")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                                .padding(.leading, 2)
                            
                            CustomSlider(value: $model.volume, icon: "speaker.wave.3.fill") { val in 
                                model.applySystemVolume(forcedValue: val) 
                            }
                            .frame(width: 340, height: 28)
                        }
                        .frame(width: 340)
                        
                        // 4. Bottom Row: AirPods Noise Control Liquid Glass Slider
                        AirPodsListeningModeSlider(model: model)
                            .frame(width: 340)
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
    
        @ViewBuilder var airDropExpandedView: some View {
        VStack(spacing: 12) {
            if model.isAirDropSending, let person = model.airDropTargetPerson {
                // Live Transfer Progress View with Animated Shrinking File into Person
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(person.color)
                                .frame(width: 48, height: 48)
                                .shadow(color: person.color.opacity(0.5), radius: 6)
                            Text(person.initials)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sending to \(person.name)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text(model.airDropProgress < 0.95 ? "Transferring file... \(Int(model.airDropProgress * 100))%" : "Waiting for \(person.name) to accept...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.cyan)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Liquid Glass Progress Bar
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 10)
                                
                                Capsule(style: .continuous)
                                    .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(10, geo.size.width * CGFloat(model.airDropProgress)), height: 10)
                                    .animation(.linear(duration: 0.08), value: model.airDropProgress)
                            }
                        }
                        .frame(height: 10)
                    }
                    .padding(.horizontal, 20)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if model.airDropSentSuccess, let person = model.airDropTargetPerson {
                // Sent Success State
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.green.opacity(0.4), radius: 6)
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sent to \(person.name)!")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("AirDrop transfer complete")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                // Top Section: Real File Preview Card + Close (X) button
                HStack(alignment: .center) {
                    AirDropFilePreviewCard(files: model.droppedAirDropFiles)
                    
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            model.droppedAirDropFiles = []
                            model.state = .compact
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                
                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.horizontal, 18)
                
                // Bottom Section: Real People Nearby to AirDrop to!
                VStack(alignment: .leading, spacing: 8) {
                    Text("People Nearby")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 18)
                    
                    HStack(spacing: 12) {
                        ForEach(model.discoverNearbyPeople()) { person in
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    model.sendAirDrop(to: person)
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill(person.color.opacity(0.85))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                                            )
                                        
                                        Text(person.initials)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        // Device Type Badge (iPhone, iPad, Mac, etc.)
                                        Image(systemName: person.deviceIcon)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(2.5)
                                            .background(Circle().fill(Color.black.opacity(0.85)))
                                            .offset(x: 2, y: 2)
                                    }
                                    
                                    VStack(spacing: 1) {
                                        Text(person.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        Text(person.device)
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.55))
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 76)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder var musicView: some View {
        VStack(spacing: 10) {
            // Header with 100% symmetrical spacing relative to physical notch
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.clear).frame(width: 46, height: 46)
                    ZStack {
                        if let img = model.currentArtwork { 
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.gray.opacity(0.3)).frame(width: 46, height: 46)
                            Image(systemName: "music.note").font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
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
                
                Spacer(minLength: 12)
                ZStack {
                    MusicWaveform(isPlaying: model.isMusicPlaying, color: model.artworkColor)
                }
                .frame(width: 32, height: 22)
                .matchedGeometryEffect(id: "musicWaveform", in: musicActivityNamespace)
                .zIndex(1)
            }
            .padding(.horizontal, 14)
            
            // Scrubber
            LiquidScrubber()
                .padding(.top, 4)
                .opacity(showsExpandedMusicDetails ? 1 : 0)
                .offset(y: showsExpandedMusicDetails ? 0 : -52)
            
            // Media Controls with large generous hitboxes (no accidental collapses)
            HStack(spacing: 28) {
                Button(action: {
                    bouncePrev += 1
                    DispatchQueue.global(qos: .background).async { 
                        _ = NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(nil) 
                    }
                }) {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 48, height: 44)
                            .contentShape(Rectangle())
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .symbolEffect(.bounce, value: bouncePrev)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    // Instantly visually swap with morphing animation
                    withAnimation { model.isMusicPlaying.toggle() }
                    DispatchQueue.global(qos: .background).async { 
                        _ = NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(nil) 
                    }
                }) {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 56, height: 48)
                            .contentShape(Rectangle())
                        Image(systemName: model.isMusicPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    bounceNext += 1
                    DispatchQueue.global(qos: .background).async { 
                        _ = NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(nil) 
                    }
                }) {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 48, height: 44)
                            .contentShape(Rectangle())
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .symbolEffect(.bounce, value: bounceNext)
                    }
                }
                .buttonStyle(.plain)
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
        if isAirDropTargeted { return 440 }
        if isExpanded {
            if state == .expandedAirDrop { return 440 }
            if state == .expandedMusic { return 420 } // Perfectly symmetrical 110px wings on left and right of physical notch
            if state == .expandedFood { return 360 }
            return 420
        }
        if airPodsShowingCompact {
            return baseNotchWidth + 90
        }
        if isMusicPlaying {
            return baseNotchWidth + 108
        }
        return baseNotchWidth
    }
    
    var height: CGFloat {
        if isAirDropTargeted && state != .expandedAirDrop {
            return physicalNotchHeight + 145 // Big comfortable height for dragging files
        }
        if isExpanded {
            if state == .expandedAirDrop { return 290 } // Extra height for BIG file/photo preview and devices underneath
            if state == .expandedMusic { return 215 }
            if state == .expandedFood { return 85 }
            if state == .expandedControls {
                return 270
            }
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


class AirDropShareDelegate: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropShareDelegate()
    var onComplete: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        DispatchQueue.main.async {
            self.onComplete?()
        }
    }
    
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        DispatchQueue.main.async {
            self.onError?(error)
        }
    }
}

class AirDropDiscoveryService: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = AirDropDiscoveryService()
    
    @Published var discoveredPeople: [AirDropPerson] = []
    @Published var isSearching: Bool = false
    
    private var browsers: [NetServiceBrowser] = []
    private var scanTimer: Timer?
    
    override init() {
        super.init()
        startDiscovery()
    }
    
    func startDiscovery() {
        isSearching = true
        refreshRecipients()
        
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        
        // Query genuine AirDrop bonjour service only
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_airdrop._tcp.", inDomain: "local.")
        browsers.append(browser)
        
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshRecipients()
        }
    }
    
    func refreshRecipients() {
        var list: [AirDropPerson] = []
        let myFullName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let firstName = myFullName.components(separatedBy: " ").first ?? myFullName
        let userPic = NSImage(named: NSImage.userAccountsName)
        
        // Check real paired & active Apple receiving devices (iPhone / iPad / Mac)
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                let majorClass = UInt32(device.deviceClassMajor)
                // Skip Audio (Headphones, earbuds, speakers) and peripherals (Keyboards, mice)
                if majorClass == 4 || majorClass == 5 { continue }
                
                guard let rawName = device.nameOrAddress, !rawName.isEmpty else { continue }
                let lower = rawName.lowercased()
                
                // Blacklist audio accessories and non-AirDrop devices
                let nonAirDropKeywords = [
                    "buds", "c500", "wf-", "wh-", "jbl", "px7", "airpods", "clip",
                    "mx master", "mx key", "keyboard", "mouse", "headphone", "speaker",
                    "soundbar", "tv", "slaapkamer", "living", "watch"
                ]
                if nonAirDropKeywords.contains(where: { lower.contains($0) }) {
                    continue
                }
                if (rawName.contains(":") || rawName.contains("-")) && rawName.count >= 14 && !rawName.contains(" ") {
                    continue
                }
                
                // Strictly parse real iPhone / iPad / Mac devices
                if lower.contains("iphone") || lower.contains("ipad") || lower.contains("mac") {
                    var personName = rawName
                    var deviceModel = "iPhone"
                    var icon = "iphone"
                    var color = Color.blue
                    
                    if lower.contains("iphone") {
                        deviceModel = "iPhone"
                        icon = "iphone"
                        color = .blue
                        if let idx = rawName.range(of: "’s iPhone", options: .caseInsensitive)?.lowerBound ?? rawName.range(of: "'s iPhone", options: .caseInsensitive)?.lowerBound {
                            personName = String(rawName[..<idx])
                        }
                    } else if lower.contains("ipad") {
                        deviceModel = "iPad"
                        icon = "ipad"
                        color = .indigo
                        if let idx = rawName.range(of: "’s iPad", options: .caseInsensitive)?.lowerBound ?? rawName.range(of: "'s iPad", options: .caseInsensitive)?.lowerBound {
                            personName = String(rawName[..<idx])
                        }
                    } else if lower.contains("mac") {
                        deviceModel = "Mac"
                        icon = "laptopcomputer"
                        color = .teal
                        if let idx = rawName.range(of: "’s Mac", options: .caseInsensitive)?.lowerBound ?? rawName.range(of: "'s Mac", options: .caseInsensitive)?.lowerBound {
                            personName = String(rawName[..<idx])
                        }
                    }
                    
                    // Assign authentic user account profile photo if person matches the user
                    var pic: NSImage? = nil
                    if personName.lowercased() == myFullName.lowercased() || personName.lowercased() == firstName.lowercased() || lower.contains(firstName.lowercased()) {
                        pic = userPic
                    }
                    
                    let initial = String(personName.prefix(1)).uppercased()
                    if !list.contains(where: { $0.name == personName && $0.device == deviceModel }) {
                        list.append(
                            AirDropPerson(
                                name: personName,
                                device: deviceModel,
                                deviceIcon: icon,
                                profileImage: pic,
                                initials: initial.isEmpty ? "A" : initial,
                                color: color
                            )
                        )
                    }
                }
            }
        }
        
        // If no external device detected, provide current user Mac recipient with real profile photo
        if list.isEmpty {
            let hostName = Host.current().localizedName ?? "MacBook Pro"
            list.append(
                AirDropPerson(
                    name: firstName,
                    device: hostName,
                    deviceIcon: "laptopcomputer",
                    profileImage: userPic,
                    initials: String(firstName.prefix(1)).uppercased(),
                    color: .blue
                )
            )
        }
        
        DispatchQueue.main.async {
            self.discoveredPeople = list
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let name = service.name
        guard !name.isEmpty else { return }
        
        let hostName = Host.current().localizedName ?? ""
        if name.lowercased() == hostName.lowercased() { return }
        
        let lower = name.lowercased()
        if lower.contains("iphone") || lower.contains("ipad") || lower.contains("mac") {
            DispatchQueue.main.async {
                self.refreshRecipients()
            }
        }
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
    @Published var showAirPodsLocalization: Bool = true
    @Published var showControlCenter: Bool = true
    @Published var showMusic: Bool = true
    @Published var showPhone: Bool = true
    @Published var showNotifications: Bool = true
    @Published var showAirDrop: Bool = true
    @Published var airDropMode: Int = 1 // 0: Off, 1: Contacts Only, 2: Everyone
    
    func fetchAirDropMode() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["read", "com.apple.sharingd", "DiscoverableMode"]
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    DispatchQueue.main.async {
                        if output.contains("Everyone") {
                            self.airDropMode = 2
                        } else if output.contains("Off") {
                            self.airDropMode = 0
                        } else {
                            self.airDropMode = 1 // Contacts Only
                        }
                    }
                }
            } catch {}
        }
    }
    
    func setAirDropMode(_ mode: Int) {
        self.airDropMode = mode
        let modeStr: String
        switch mode {
        case 0: modeStr = "Off"
        case 2: modeStr = "Everyone"
        default: modeStr = "Contacts Only"
        }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["write", "com.apple.sharingd", "DiscoverableMode", "-string", modeStr]
            try? process.run()
            process.waitUntilExit()
            
            let killSharingd = Process()
            killSharingd.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killSharingd.arguments = ["-HUP", "sharingd"]
            try? killSharingd.run()
        }
    }
    
    // Interactive AirDrop Drag & Drop State
    @Published var droppedAirDropFiles: [URL] = [] {
        didSet {
            updateAirDropAmbientColor()
        }
    }
    @Published var isAirDropTargeted: Bool = false
    @Published var droppedFileThumbnail: NSImage? = nil
    @Published var droppedFileColor: Color = Color.cyan
    
    private func updateAirDropAmbientColor() {
        guard let first = droppedAirDropFiles.first else {
            droppedFileThumbnail = nil
            droppedFileColor = Color.cyan
            return
        }
        let ext = first.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "icns"].contains(ext), let img = NSImage(contentsOf: first) {
            self.droppedFileThumbnail = img
            // Extract dominant color if available
            DispatchQueue.global(qos: .userInitiated).async {
                if let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let thumb = NSBitmapImageRep(cgImage: cgImage)
                    if let c = thumb.colorAt(x: thumb.pixelsWide / 2, y: thumb.pixelsHigh / 2) {
                        DispatchQueue.main.async {
                            self.droppedFileColor = Color(nsColor: c)
                        }
                        return
                    }
                }
                DispatchQueue.main.async {
                    self.droppedFileColor = Color.blue
                }
            }
        } else {
            let icon = NSWorkspace.shared.icon(forFile: first.path)
            self.droppedFileThumbnail = icon
            self.droppedFileColor = Color.cyan
        }
    }
    @Published var isAirDropSending: Bool = false
    @Published var airDropSentSuccess: Bool = false
    
    // System Permission On/Off Switchers (reflect real macOS settings state)
    @Published var isAccessibilityEnabled: Bool = AXIsProcessTrusted()
    @Published var isMusicScriptingEnabled: Bool = true
    @Published var isMicrophoneEnabled: Bool = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    @Published var isNotificationsEnabled: Bool = true
    @Published var isBluetoothPermissionEnabled: Bool = true
    
    func refreshPermissionStates() {
        self.isAccessibilityEnabled = AXIsProcessTrusted()
        self.isMicrophoneEnabled = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }
    
    func toggleAccessibility(enabled: Bool) {
        if enabled {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let trusted = AXIsProcessTrustedWithOptions(options)
            self.isAccessibilityEnabled = trusted
            self.showControlCenter = true
        } else {
            self.isAccessibilityEnabled = false
            self.showControlCenter = false
        }
    }
    
    func toggleMicrophone(enabled: Bool) {
        if enabled {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.isMicrophoneEnabled = granted
                    self.hasMicPermission = granted
                    if granted {
                        AudioAnalyzer.shared.startMonitoring()
                    }
                }
            }
        } else {
            self.isMicrophoneEnabled = false
            self.hasMicPermission = false
            AudioAnalyzer.shared.stopMonitoring()
        }
    }
    
    func toggleNotifications(enabled: Bool) {
        if enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    self.isNotificationsEnabled = granted
                    self.showNotifications = granted
                }
            }
        } else {
            self.isNotificationsEnabled = false
            self.showNotifications = false
        }
    }
    
    @Published var airDropProgress: Double = 0.0
    @Published var airDropTargetPerson: AirDropPerson? = nil
    
    func discoverNearbyPeople() -> [AirDropPerson] {
        return AirDropDiscoveryService.shared.discoveredPeople
    }
    
    func sendAirDrop(to person: AirDropPerson) {
        guard !droppedAirDropFiles.isEmpty else { return }
        airDropTargetPerson = person
        isAirDropSending = true
        airDropProgress = 0.1
        
        let filesToSend = self.droppedAirDropFiles
        
        // 1. Perform actual native macOS AirDrop file transfer
        DispatchQueue.main.async {
            if let service = NSSharingService(named: .sendViaAirDrop) {
                AirDropShareDelegate.shared.onComplete = { [weak self] in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self?.airDropProgress = 1.0
                        self?.isAirDropSending = false
                        self?.airDropSentSuccess = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self?.airDropSentSuccess = false
                            self?.droppedAirDropFiles = []
                            self?.airDropTargetPerson = nil
                            self?.airDropProgress = 0.0
                            self?.state = .compact
                        }
                    }
                }
                
                AirDropShareDelegate.shared.onError = { [weak self] _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self?.isAirDropSending = false
                        self?.airDropTargetPerson = nil
                    }
                }
                
                service.delegate = AirDropShareDelegate.shared
                if service.canPerform(withItems: filesToSend) {
                    service.perform(withItems: filesToSend)
                }
            }
        }
        
        // 2. Smooth Notch progress animation
        Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { timer in
            DispatchQueue.main.async {
                if self.isAirDropSending {
                    if self.airDropProgress < 0.92 {
                        self.airDropProgress += 0.035
                    }
                } else {
                    timer.invalidate()
                }
            }
        }
    }
    
    func sendAirDrop(to targetName: String? = nil) {
        let person = discoverNearbyPeople().first { $0.name == targetName || $0.device == targetName } 
            ?? discoverNearbyPeople().first 
            ?? AirDropPerson(name: "Nearby Device", device: "Apple Device", deviceIcon: "laptopcomputer", profileImage: nil, initials: "A", color: .blue)
        sendAirDrop(to: person)
    }
    
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
    @Published var wifiSSID: String = "Wi-Fi" 
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
    @Published var settingsBackgroundStyle: SettingsBackgroundStyle = {
        if let saved = UserDefaults.standard.string(forKey: "saved_settingsBackgroundStyle"),
           let style = SettingsBackgroundStyle(rawValue: saved) {
            return style
        }
        return .systemDefault
    }() {
        didSet {
            UserDefaults.standard.set(settingsBackgroundStyle.rawValue, forKey: "saved_settingsBackgroundStyle")
        }
    }
    @Published var settingsGlassIntensity: Double = 0.75
    @Published var settingsWindowOpacity: Double = 0.85
    @Published var settingsWallpaperBlur: Double = 0.0
    @Published var customWallpaperImage: NSImage? = nil
    @Published var isSidebarCollapsed: Bool = false
    @Published var notchCompactAlwaysBlack: Bool = {
        if UserDefaults.standard.object(forKey: "saved_notchCompactAlwaysBlack") != nil {
            return UserDefaults.standard.bool(forKey: "saved_notchCompactAlwaysBlack")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(notchCompactAlwaysBlack, forKey: "saved_notchCompactAlwaysBlack")
        }
    }
    @Published var notchTheme: NotchTheme = {
        if let saved = UserDefaults.standard.string(forKey: "saved_notchTheme"),
           let theme = NotchTheme(rawValue: saved) {
            return theme
        }
        return .classicBlack
    }() {
        didSet {
            UserDefaults.standard.set(notchTheme.rawValue, forKey: "saved_notchTheme")
        }
    }
    @Published var notchGlassOpacity: Double = 0.85 {
        didSet {
            UserDefaults.standard.set(notchGlassOpacity, forKey: "saved_notchGlassOpacity")
        }
    }
    @Published var notchGlowIntensity: Double = 0.75 {
        didSet {
            UserDefaults.standard.set(notchGlowIntensity, forKey: "saved_notchGlowIntensity")
        }
    }
    
    func pickCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let img = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    self.customWallpaperImage = img
                    self.settingsBackgroundStyle = .customPicture
                }
            }
        }
    }
    
    var updaterController: SPUStandardUpdaterController?
    
    @Published var isScreenTransitioning: Bool = false
    private var transitionDebounceTask: Task<Void, Never>? = nil

    init() {
        refreshPermissionStates()
        readSystemBrightness()
        readSystemVolume()
        startWifiMonitoring()
        startMusicMonitoring()
        startScreenTransitionMonitoring()
        startAirPodsMonitoring()
        startAudioDeviceMonitoring()
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
    
    private var precompiledMusicScript: NSAppleScript? = {
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
        let script = NSAppleScript(source: scriptSource)
        script?.compileAndReturnError(nil)
        return script
    }()
    
    private func startMusicMonitoring() {
        // 1. Instant zero-latency notifications on track/playback changes from Apple Music
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchCurrentMusicState()
        }
        
        // 2. Efficient periodic position tracking
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchCurrentMusicState()
        }
        fetchCurrentMusicState()
    }
    
    func fetchCurrentMusicState() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var err: NSDictionary?
            guard let script = self.precompiledMusicScript else { return }
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

    @Published var listeningMode: Int = 2 // 2: Noise Cancellation, 1: Off, 4: Adaptive, 3: Transparency
    @Published var adaptiveBalance: Double = 0.5 // 0.0: More Noise Cancellation <---> 1.0: More Transparency
    
    func setAirPodsMode(_ mode: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.listeningMode = mode
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            let sel = Selector("setListeningMode:")
            typealias SetListeningModeIMP = @convention(c) (AnyObject, Selector, UInt32) -> Bool
            
            for device in devices {
                let name = device.nameOrAddress ?? ""
                if name.contains("AirPods") || device.deviceClassMajor == 4 {
                    if device.responds(to: sel) {
                        let imp = device.method(for: sel)
                        let fn = unsafeBitCast(imp, to: SetListeningModeIMP.self)
                        _ = fn(device, sel, UInt32(mode))
                    }
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
    
    private var airPodsDismissWorkItem: DispatchWorkItem?

    func triggerAirPodsBanner() {
        airPodsDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.airPodsShowingCompact = true
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                self?.airPodsShowingCompact = false
            }
        }
        airPodsDismissWorkItem = work
        // Briefly display the battery & AirPods status, then shrink away cleanly so music live activity can take over!
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }

    func startAudioDeviceMonitoring() {
        // Notification when audio output changes (e.g. AirPods switch seamlessly from iPhone to Mac)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVSystemController_PickableRoutesDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
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
                    let wasConnected = self.airPodsConnected
                    self.airPodsName = airpods.name
                    self.airPodsBatteryLevel = airpods.battery
                    
                    if !wasConnected {
                        self.airPodsConnected = true
                        self.triggerAirPodsBanner()
                    }
                } else {
                    if self.airPodsConnected {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            self.airPodsConnected = false
                            self.airPodsShowingCompact = false
                        }
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
        
        if let ssid = interface.ssid(), !ssid.isEmpty {
            self.wifiSSID = ssid
        } else {
            self.wifiSSID = "Connected"
        }
    }
    func makeCustomIfNeeded() { if animationCurve != .custom { customC1 = animationCurve.defaultC1; customC2 = animationCurve.defaultC2; animationCurve = .custom } }
    
    var currentAnimation: Animation { switch animationCurve { case .spring: return .spring(response: animationDuration, dampingFraction: 0.62, blendDuration: 0.1); case .bouncy: return .spring(response: animationDuration, dampingFraction: 0.45, blendDuration: 0.1); case .smooth: return .easeInOut(duration: animationDuration); case .easeIn: return .easeIn(duration: animationDuration); case .easeOut: return .easeOut(duration: animationDuration); case .linear: return .linear(duration: animationDuration); case .custom: return .timingCurve(customC1.x, customC1.y, customC2.x, customC2.y, duration: animationDuration) } }
    func toggleState(_ nextState: IslandState) { if state == nextState { state = .compact } else { state = nextState } }
}


struct AirPods3DView: View {
    @State private var flipAngle: Double = 0
    @State private var floatOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 1.5) {
            // Left AirPod
            Image(systemName: "airpodspro.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: floatOffset)
                .rotation3DEffect(
                    .degrees(flipAngle),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    anchor: .center,
                    perspective: 0.35
                )
            
            // Right AirPod
            Image(systemName: "airpodspro.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: -floatOffset)
                .rotation3DEffect(
                    .degrees(flipAngle + 20),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    anchor: .center,
                    perspective: 0.35
                )
        }
        .onAppear {
            // Smooth iPhone-style 3D flip rotation
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                flipAngle = 360
                floatOffset = 1.2
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
    
    // Wave frequencies & phase offsets for continuous fluid Apple Music waveform animation
    let frequencies: [Double] = [3.8, 5.2, 4.1, 6.0, 4.7]
    let phases: [Double] = [0.0, 1.2, 2.4, 0.8, 1.9]
    let minHeight: CGFloat = 3.5
    let maxHeight: CGFloat = 16.0
    
    var body: some View {
        if isPlaying {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.2) {
                    ForEach(0..<5, id: \.self) { i in
                        let wave = (sin(time * frequencies[i] + phases[i]) + 1.0) / 2.0
                        let h = minHeight + CGFloat(wave) * (maxHeight - minHeight)
                        Capsule()
                            .fill(color)
                            .frame(width: 3.2, height: h)
                    }
                }
                .frame(height: maxHeight, alignment: .center)
            }
        } else {
            HStack(spacing: 2.2) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule()
                        .fill(color.opacity(0.6))
                        .frame(width: 3.2, height: minHeight)
                }
            }
            .frame(height: maxHeight, alignment: .center)
        }
    }
}



enum NotchTheme: String, CaseIterable, Identifiable {
    case classicBlack = "Classic Obsidian"
    case iosGlassCapsule = "iOS Smoked Glass"
    case liquidGlass = "Liquid Glass"
    case neonCyber = "Cyberpunk Neon"
    case titaniumFrost = "Titanium Slate"
    case auroraGlow = "Aurora Radiance"
    case goldenTwilight = "Golden Sunset"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .classicBlack: return "circle.fill"
        case .iosGlassCapsule: return "magnifyingglass.circle.fill"
        case .liquidGlass: return "drop.fill"
        case .neonCyber: return "bolt.fill"
        case .titaniumFrost: return "square.fill"
        case .auroraGlow: return "sparkles"
        case .goldenTwilight: return "sun.horizon.fill"
        }
    }
    
    var subtitle: String {
        switch self {
        case .classicBlack: return "Authentic Apple OLED Jet Black"
        case .iosGlassCapsule: return "iOS Siri smoked acrylic with glass bevel rim"
        case .liquidGlass: return "Frosted glass with specular rim"
        case .neonCyber: return "Glowing neon cyan & magenta rim"
        case .titaniumFrost: return "Brushed dark titanium finish"
        case .auroraGlow: return "Celestial purple & emerald rim"
        case .goldenTwilight: return "Warm amber twilight reflection"
        }
    }
}

enum SettingsBackgroundStyle: String, CaseIterable, Identifiable {
    case systemDefault = "Default (Auto)"
    case pureWhite = "Pure White"
    case pureBlack = "Pure Black"
    case liquidGlass = "Liquid Glass"
    case sonoma = "Sonoma Sunset"
    case sequoia = "Sequoia Pines"
    case aurora = "Cupertino Aurora"
    case neon = "Cyberpunk Neon"
    case obsidian = "Dark Obsidian"
    case dune = "Desert Dune"
    case slate = "Minimal Slate"
    case customPicture = "Custom Picture"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .systemDefault: return "circle.lefthalf.filled"
        case .pureWhite: return "sun.max.fill"
        case .pureBlack: return "moon.fill"
        case .liquidGlass: return "drop.fill"
        case .sonoma: return "sun.horizon.fill"
        case .sequoia: return "tree.fill"
        case .aurora: return "sparkles"
        case .neon: return "bolt.fill"
        case .obsidian: return "circle.fill"
        case .dune: return "wind"
        case .slate: return "square.fill"
        case .customPicture: return "photo.fill"
        }
    }
    
    var subtitle: String {
        switch self {
        case .systemDefault: return "Auto Light / Dark mode wallpaper"
        case .pureWhite: return "Minimalist crisp white frosted glass"
        case .pureBlack: return "Deep true black OLED noir"
        case .liquidGlass: return "Ultra frosted dynamic liquid glass"
        case .sonoma: return "Warm twilight landscape glow"
        case .sequoia: return "Deep pine forest emerald"
        case .aurora: return "Vibrant cosmic radiance"
        case .neon: return "Vivid synthwave glow"
        case .obsidian: return "High contrast midnight noir"
        case .dune: return "Golden hour desert warmth"
        case .slate: return "High contrast titanium slate"
        case .customPicture: return "Choose image from Photos / Finder"
        }
    }
    
    var isLight: Bool {
        switch self {
        case .pureWhite:
            return true
        default:
            return false
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance = "Appearance & Physics"
    case notchStyling = "Notch Styling"
    case background = "Window & Background"
    case display = "Hardware Calibration"
    case liveActivities = "Live Activities"
    case systemControls = "System Controls"
    case about = "About"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: return "sparkles"
        case .notchStyling: return "capsule.portrait.fill"
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


struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SettingsWindowBackground: View {
    let style: SettingsBackgroundStyle
    let opacity: Double
    let glass: Double
    var blurRadius: Double = 0.0
    var customImage: NSImage? = nil
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base visual effect blur for macOS vibrancy
            VisualEffect()
                .opacity(opacity)
            
            // Rich artistic wallpaper layer with configurable blur
            Group {
                switch style {
                case .systemDefault:
                    if colorScheme == .dark {
                        RadialGradient(
                            colors: [
                                Color(red: 0.14, green: 0.14, blue: 0.18).opacity(0.92 * opacity),
                                Color(red: 0.06, green: 0.06, blue: 0.09).opacity(0.96 * opacity),
                                Color(red: 0.02, green: 0.02, blue: 0.03).opacity(0.99 * opacity)
                            ],
                            center: .topLeading,
                            startRadius: 50,
                            endRadius: 700
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.98, blue: 1.0).opacity(0.95 * opacity),
                                Color(red: 0.92, green: 0.93, blue: 0.96).opacity(0.92 * opacity),
                                Color(red: 0.88, green: 0.90, blue: 0.94).opacity(0.90 * opacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    
                case .pureWhite:
                    LinearGradient(
                        colors: [
                            Color(white: 0.98).opacity(0.96 * opacity),
                            Color(white: 0.92).opacity(0.94 * opacity),
                            Color(white: 0.88).opacity(0.92 * opacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                case .pureBlack:
                    Color(white: 0.02).opacity(0.98 * opacity)
                    
                case .customPicture:
                    if let img = customImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(opacity)
                    } else {
                        LinearGradient(
                            colors: [Color.blue.opacity(0.7 * opacity), Color.purple.opacity(0.8 * opacity)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                case .liquidGlass:
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18 * glass),
                            Color(red: 0.12, green: 0.22, blue: 0.38).opacity(0.40 * opacity),
                            Color.black.opacity(0.50 * opacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .sonoma:
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.48, blue: 0.26).opacity(0.80 * opacity),
                            Color(red: 0.88, green: 0.22, blue: 0.48).opacity(0.75 * opacity),
                            Color(red: 0.38, green: 0.12, blue: 0.58).opacity(0.85 * opacity),
                            Color(red: 0.12, green: 0.06, blue: 0.28).opacity(0.92 * opacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .sequoia:
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.48, blue: 0.38).opacity(0.82 * opacity),
                            Color(red: 0.09, green: 0.32, blue: 0.28).opacity(0.78 * opacity),
                            Color(red: 0.04, green: 0.20, blue: 0.22).opacity(0.86 * opacity),
                            Color(red: 0.02, green: 0.09, blue: 0.14).opacity(0.94 * opacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .aurora:
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.18, blue: 0.90).opacity(0.82 * opacity),
                            Color(red: 0.18, green: 0.48, blue: 0.98).opacity(0.78 * opacity),
                            Color(red: 0.06, green: 0.80, blue: 0.70).opacity(0.72 * opacity),
                            Color(red: 0.06, green: 0.06, blue: 0.28).opacity(0.92 * opacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .neon:
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.12, blue: 0.65).opacity(0.82 * opacity),
                            Color(red: 0.48, green: 0.06, blue: 0.88).opacity(0.82 * opacity),
                            Color(red: 0.06, green: 0.58, blue: 0.98).opacity(0.78 * opacity),
                            Color(red: 0.05, green: 0.03, blue: 0.12).opacity(0.96 * opacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .obsidian:
                    RadialGradient(
                        colors: [
                            Color(red: 0.18, green: 0.18, blue: 0.24).opacity(0.92 * opacity),
                            Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.96 * opacity),
                            Color(red: 0.02, green: 0.02, blue: 0.04).opacity(0.99 * opacity)
                        ],
                        center: .topLeading,
                        startRadius: 50,
                        endRadius: 700
                    )
                case .dune:
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.68, blue: 0.38).opacity(0.82 * opacity),
                            Color(red: 0.88, green: 0.48, blue: 0.28).opacity(0.78 * opacity),
                            Color(red: 0.58, green: 0.28, blue: 0.38).opacity(0.82 * opacity),
                            Color(red: 0.18, green: 0.09, blue: 0.18).opacity(0.94 * opacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .slate:
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.31, blue: 0.38).opacity(0.88 * opacity),
                            Color(red: 0.18, green: 0.20, blue: 0.25).opacity(0.92 * opacity),
                            Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.97 * opacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .blur(radius: blurRadius)
            
            // Specular Liquid Glass Overlay & Edge Highlights
            if glass > 0 {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24 * glass),
                        Color.white.opacity(0.05 * glass),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .blendMode(.plusLighter)
            }
        }
    }
}


struct NotchCardView: View {
    let theme: NotchTheme
    let isSelected: Bool
    let isLightBg: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                labelSection
            }
            .padding(6)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            thumbnailBackground
                .frame(height: 54)
                .cornerRadius(8)
            
            Image(systemName: theme.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 3)
            
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 2.5)
                
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .background(Circle().fill(Color.white))
                            .font(.system(size: 13))
                            .padding(4)
                    }
                    Spacer()
                }
            }
        }
    }
    
    @ViewBuilder
    private var thumbnailBackground: some View {
        switch theme {
        case .classicBlack:
            Color.black
        case .iosGlassCapsule:
            LinearGradient(
                colors: [Color.black.opacity(0.95), Color(red: 0.18, green: 0.16, blue: 0.20), Color(white: 0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .liquidGlass:
            LinearGradient(colors: [Color.blue.opacity(0.4), Color.black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .neonCyber:
            LinearGradient(colors: [Color.purple.opacity(0.6), Color.cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .titaniumFrost:
            Color(red: 0.18, green: 0.20, blue: 0.24)
        case .auroraGlow:
            LinearGradient(colors: [Color.purple.opacity(0.7), Color.teal.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .goldenTwilight:
            LinearGradient(colors: [Color.orange.opacity(0.7), Color.pink.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(theme.rawValue)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                .lineLimit(1)
            Text(theme.subtitle)
                .font(.system(size: 9))
                .foregroundColor(isLightBg ? Color(red: 0.35, green: 0.35, blue: 0.45) : .white.opacity(0.6))
                .lineLimit(1)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.blue.opacity(0.18) : (isLightBg ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? Color.blue.opacity(0.6) : (isLightBg ? Color.black.opacity(0.1) : Color.white.opacity(0.12)), lineWidth: 1)
    }
}

struct NotchStylingView: View {
    @ObservedObject var model = IslandModel.shared
    @Environment(\.colorScheme) var colorScheme
    
    private var isLightBg: Bool {
        if model.settingsBackgroundStyle == .pureWhite { return true }
        if model.settingsBackgroundStyle == .systemDefault && colorScheme == .light { return true }
        return false
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live Interactive Notch Theme Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dynamic Notch Live Preview")
                        .font(.headline)
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    
                    ZStack {
                        // Blurred wallpaper ambient backdrop
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.25, blue: 0.18), Color(red: 0.12, green: 0.10, blue: 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 125)
                        
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Search or Ask • " + model.notchTheme.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "mic.fill")
                                    .foregroundColor(.white.opacity(0.85))
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 16)
                            .frame(width: 280, height: 38)
                            .background(
                                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 19, bottomTrailingRadius: 19, topTrailingRadius: 0, style: .continuous)
                                    .fill(notchPreviewBase)
                            )
                            .overlay(
                                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 19, bottomTrailingRadius: 19, topTrailingRadius: 0, style: .continuous)
                                    .stroke(notchPreviewBorder, lineWidth: 1.2)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                            
                            Spacer()
                        }
                    }
                    .frame(height: 125)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isLightBg ? Color.black.opacity(0.15) : Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 28)
                
                // Resting vs Expanded Notch Color Option
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resting Notch Behavior")
                        .font(.headline)
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep Notch Solid Black in Compact Mode")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                                Text(model.notchCompactAlwaysBlack ? "Resting notch stays pure black to blend invisibly with hardware sensors." : "Resting notch uses the chosen theme colors & glass speculars.")
                                    .font(.system(size: 11))
                                    .foregroundColor(isLightBg ? Color(red: 0.35, green: 0.35, blue: 0.45) : .white.opacity(0.6))
                            }
                            Spacer()
                            Toggle("", isOn: $model.notchCompactAlwaysBlack)
                                .labelsHidden()
                        }
                    }
                    .padding(14)
                    .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 28)
                
                // Notch Theme Gallery
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select Notch Theme")
                        .font(.headline)
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(NotchTheme.allCases) { theme in
                            NotchCardView(
                                theme: theme,
                                isSelected: model.notchTheme == theme,
                                isLightBg: isLightBg
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    model.notchTheme = theme
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                
                // Visual Effects & Translucency Controls
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Music Artwork Ambient Glow")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                            Text("Projects a vibrant colored aura under the notch matching active album artwork.")
                                .font(.system(size: 11))
                                .foregroundColor(isLightBg ? Color(red: 0.35, green: 0.35, blue: 0.45) : .white.opacity(0.6))
                        }
                        Spacer()
                        Toggle("", isOn: $model.enableArtworkGlow)
                            .labelsHidden()
                    }
                    .padding(14)
                    .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                    .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Liquid Glass Translucency", systemImage: "drop.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                            Spacer()
                            Text(model.notchGlassOpacity > 0.75 ? "Full Glass" : "Soft Frost")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $model.notchGlassOpacity, in: 0.2...1.0)
                    }
                    .padding(14)
                    .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                    .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Rim Glow & Glass Bevel Specular", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                            Spacer()
                            Text(model.notchGlowIntensity > 0.75 ? "Vibrant" : "Subtle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $model.notchGlowIntensity, in: 0.2...1.0)
                    }
                    .padding(14)
                    .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .padding(.top, 6)
        }
    }
    
    private var notchPreviewBase: AnyShapeStyle {
        switch model.notchTheme {
        case .classicBlack:
            return AnyShapeStyle(Color.black)
        case .iosGlassCapsule:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.92 * model.notchGlassOpacity),
                        Color(red: 0.14, green: 0.13, blue: 0.16).opacity(0.72 * model.notchGlassOpacity),
                        Color(white: 0.25).opacity(0.45 * model.notchGlassOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .liquidGlass:
            return AnyShapeStyle(Color.black.opacity(0.8))
        case .neonCyber:
            return AnyShapeStyle(Color(red: 0.05, green: 0.02, blue: 0.10))
        case .titaniumFrost:
            return AnyShapeStyle(Color(red: 0.12, green: 0.13, blue: 0.16))
        case .auroraGlow:
            return AnyShapeStyle(Color(red: 0.04, green: 0.03, blue: 0.08))
        case .goldenTwilight:
            return AnyShapeStyle(Color(red: 0.08, green: 0.04, blue: 0.02))
        }
    }
    
    private var notchPreviewBorder: AnyShapeStyle {
        switch model.notchTheme {
        case .classicBlack:
            return AnyShapeStyle(Color.clear)
        case .iosGlassCapsule:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.20 * model.notchGlowIntensity),
                        Color.white.opacity(0.55 * model.notchGlowIntensity),
                        Color.white.opacity(0.85 * model.notchGlowIntensity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .liquidGlass:
            return AnyShapeStyle(Color.white.opacity(0.4))
        case .neonCyber:
            return AnyShapeStyle(Color.cyan)
        case .titaniumFrost:
            return AnyShapeStyle(Color.white.opacity(0.3))
        case .auroraGlow:
            return AnyShapeStyle(Color.purple)
        case .goldenTwilight:
            return AnyShapeStyle(Color.orange)
        }
    }
}
struct ContentView: View {
    @ObservedObject var model = IslandModel.shared
    @State private var selectedPane: SettingsPane = .appearance
    @State private var hoveredPane: SettingsPane? = nil
    @Environment(\.colorScheme) var colorScheme
    
    private var isLightBg: Bool {
        if model.settingsBackgroundStyle == .pureWhite { return true }
        if model.settingsBackgroundStyle == .systemDefault && colorScheme == .light { return true }
        return false
    }
    
    var body: some View {
        ZStack {
            WindowAccessor()
            
            // Full-window wallpaper & liquid glass backdrop
            SettingsWindowBackground(
                style: model.settingsBackgroundStyle,
                opacity: model.settingsWindowOpacity,
                glass: model.settingsGlassIntensity,
                blurRadius: model.settingsWallpaperBlur,
                customImage: model.customWallpaperImage
            )
            .ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Minimizable Sidebar Navigation
                VStack(alignment: model.isSidebarCollapsed ? .center : .leading, spacing: 6) {
                    // Top-level Circular Liquid Glass Toggle Button (Zero text up top!)
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                model.isSidebarCollapsed.toggle()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(isLightBg ? 0.40 : 0.22),
                                                Color.white.opacity(isLightBg ? 0.18 : 0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.65), Color.white.opacity(0.18)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 1.0
                                            )
                                    )
                                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 1.5)
                                
                                Image(systemName: model.isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(isLightBg ? Color(red: 0.12, green: 0.12, blue: 0.18) : .white)
                            }
                            .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .help(model.isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
                        
                        if !model.isSidebarCollapsed {
                            Spacer()
                        }
                    }
                    .padding(.horizontal, model.isSidebarCollapsed ? 8 : 16)
                    .padding(.top, 36)
                    .padding(.bottom, 8)
                    
                    // Navigation Items
                    ForEach(SettingsPane.allCases) { pane in
                        let isSelected = selectedPane == pane
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                selectedPane = pane
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: pane.icon)
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                                    .frame(width: 24, alignment: .center)
                                
                                if !model.isSidebarCollapsed {
                                    Text(pane.rawValue)
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: model.isSidebarCollapsed ? .center : .leading)
                            .padding(.vertical, 9)
                            .padding(.horizontal, model.isSidebarCollapsed ? 6 : 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.blue : (hoveredPane == pane ? (isLightBg ? Color.black.opacity(0.08) : Color.white.opacity(0.12)) : Color.clear))
                            )
                            .foregroundStyle(isSelected ? Color.white : (isLightBg ? Color(red: 0.15, green: 0.15, blue: 0.22) : Color.white.opacity(0.9)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(pane.rawValue)
                        .onHover { hovering in
                            if hovering { hoveredPane = pane } else if hoveredPane == pane { hoveredPane = nil }
                        }
                        .padding(.horizontal, model.isSidebarCollapsed ? 6 : 10)
                    }
                    Spacer()
                }
                .frame(width: model.isSidebarCollapsed ? 58 : 235, alignment: model.isSidebarCollapsed ? .center : .leading)
                .frame(maxHeight: .infinity)
                .background(isLightBg ? Color.black.opacity(0.06) : Color.black.opacity(0.28))
                
                Divider()
                    .opacity(0.25)
                    .ignoresSafeArea()
                
                // Detail Content Area with High-Contrast Text
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(selectedPane.rawValue)
                            .font(.title2.bold())
                            .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                            .shadow(color: isLightBg ? .clear : .black.opacity(0.3), radius: 2)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 40)
                    .padding(.bottom, 12)
                    
                    switch selectedPane {
                    case .appearance:
                        AnimationSettingsView()
                    case .notchStyling:
                        NotchStylingView()
                    case .background:
                        BackgroundSettingsView(selectedPane: $selectedPane)
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
            }
        }
        .frame(width: 840, height: 680)
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

struct AnimationSettingsView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Morphing Physics"), footer: Text("Drag anywhere inside the Sandbox Graph to instantly trace out custom trajectories.")) { VStack(alignment: .leading, spacing: 30) { VStack(alignment: .leading, spacing: 18) { Picker("Curve Algorithm", selection: $model.animationCurve) { ForEach(AnimationCurve.allCases, id: \.self) { curve in Text(curve.rawValue).tag(curve) } }; VStack(alignment: .leading, spacing: 6) { HStack { Text("Duration Time"); Spacer(); Text(String(format: "%.1fs", model.animationDuration)).monospacedDigit().foregroundStyle(.secondary) }; Slider(value: $model.animationDuration, in: 0.1...1.5, step: 0.1) } }; VStack(alignment: .leading) { Text(model.animationCurve == .custom ? "Live Physics Sandbox" : "System Easing Math").font(.subheadline.weight(.medium)).foregroundStyle(model.animationCurve == .custom ? .orange : .secondary).padding(.bottom, 6); BezierGraph(model: model).frame(height: 250).padding(.horizontal, 26).padding(.vertical, 20).background(Color(NSColor.textBackgroundColor)).cornerRadius(12).shadow(color: model.animationCurve == .custom ? Color.orange.opacity(0.3) : .clear, radius: 10).animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.animationCurve) }.padding(.top, 4) }.padding(.vertical, 12) } }.formStyle(.grouped)
        .scrollContentBackground(.hidden) } }
struct HardwareCalibrationView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section(header: Text("Screen Target"), footer: Text("Select which physical display panels should draw the notch overlay.")) { HStack { Spacer(); GlassSegmentControl(selection: $model.displayMode).padding(.vertical, 8); Spacer() } }; Section(header: Text("Display Bezels"), footer: Text("Use this diagnostic tool to match the simulated bounds precisely to your hardware sensors.")) { HStack(spacing: 16) { Text("Resting Camouflage Width"); Slider(value: $model.baseNotchWidth, in: 120...260, step: 2); Text("\(Int(model.baseNotchWidth))px").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) }; HStack(spacing: 16) { Text("Resting Corner Radius"); Slider(value: $model.compactCornerRadius, in: 2...30, step: 1); Text("\(Int(model.compactCornerRadius))px").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing) } } }.formStyle(.grouped)
        .scrollContentBackground(.hidden) } }
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
struct ConnectivityCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isOn: Bool
    let activeTint: Color
    var variableValue: Double? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn ? activeTint : Color.white.opacity(0.18))
                        .frame(width: 26, height: 26)
                    
                    if let val = variableValue {
                        Image(systemName: icon, variableValue: val)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isOn ? .white : .white.opacity(0.6))
                    } else if icon == "bluetooth.custom" {
                        BluetoothShape()
                            .fill(isOn ? Color.white : Color.white.opacity(0.6))
                            .frame(width: 12, height: 16)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isOn ? .white : .white.opacity(0.6))
                    }
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}

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
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack(alignment: .leading) { 
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.15))
                
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: max(28, w * CGFloat(max(0, min(1, value)))))
                
                Image(systemName: dynamicIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(value > 0.12 ? .black : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.leading, 9) 
            }
            .frame(width: w, height: h)
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in 
                        let fraction = min(max(0.0, Double(gesture.location.x / w)), 1.0)
                        if abs(value - fraction) > 0.005 {
                            value = fraction
                            action?(fraction)
                        }
                    }
            )
        }
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
        VStack(spacing: 5) {
            switcherButton(icon: "switch.2", target: .expandedControls)
            switcherButton(icon: "music.note", target: .expandedMusic)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.45))
                .background(
                    VisualEffect()
                        .clipShape(Capsule(style: .continuous))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
        )
    }
    
    @ViewBuilder func switcherButton(icon: String, target: IslandState) -> some View {
        let isActive = (activeState == target)
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                model.state = target
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.white : Color.white.opacity(0.08))
                Image(systemName: icon)
                    .foregroundStyle(isActive ? Color.black : Color.white)
                    .font(.system(size: 10, weight: .bold))
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
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
                        .stroke(isOn ? Color.white : Color.gray, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 16)
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
            .frame(width: 36, height: 36)
            .background(isOn ? activeTint : Color.white.opacity(0.15))
            .clipShape(Circle())
            .scaleEffect(isOn ? 1.0 : 0.88)
        }
        .buttonStyle(.plain)
    }
}
struct AboutView: View { @ObservedObject var model = IslandModel.shared; var body: some View { Form { Section { VStack(spacing: 16) { Image(systemName: "capsule.portrait.fill").font(.system(size: 64)).rotationEffect(.degrees(90)); VStack(spacing: 4) { Text("Dynamic Island for Mac").font(.title.bold()); Text("Version 1.1").font(.subheadline).foregroundStyle(.secondary) }; Text("Brings the fluid Apple iOS Dynamic Island straight into your macOS menu bar.").font(.body).multilineTextAlignment(.center).padding(.horizontal); Button(action: { model.updaterController?.checkForUpdates(nil) }) { Text("Check for Updates...").padding(.horizontal, 8) }.buttonStyle(.borderedProminent).tint(.blue).padding(.top, 8) }.frame(maxWidth: .infinity).padding(.vertical, 24) } }.formStyle(.grouped)
        .scrollContentBackground(.hidden) } }
struct SystemControlsView: View {
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        Form {
            Section(header: Text("Hover & Interaction Behavior"), footer: Text("Controls how long the island stays open after you move your mouse away.")) {
                Picker("Auto-Close Behavior", selection: $model.autoCloseBehavior) {
                    ForEach(AutoCloseBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            
            Section(header: Text("System Permissions & Features"), footer: Text("Toggle individual permissions on or off. If already granted in macOS System Settings, it stays ON automatically.")) {
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility & System Controls")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required to control volume, brightness & system shortcuts")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isAccessibilityEnabled },
                        set: { val in model.toggleAccessibility(enabled: val) }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "applescript.fill")
                        .foregroundStyle(.pink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Events & Music Scripting")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required to read song info, album art & playback controls")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.isMusicScriptingEnabled)
                        .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone Audio Analysis")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required for live jumping audio waveform visualization")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isMicrophoneEnabled },
                        set: { val in model.toggleMicrophone(enabled: val) }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.red)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notification Center Access")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required to route alerts into the dynamic notch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isNotificationsEnabled },
                        set: { val in model.toggleNotifications(enabled: val) }
                    ))
                    .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "airpodspro")
                        .foregroundStyle(.cyan)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bluetooth & AirPods Detection")
                            .font(.system(size: 13, weight: .medium))
                        Text("Enables paired AirPods connection and battery monitoring")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.isBluetoothPermissionEnabled)
                        .labelsHidden()
                }
            }
            
            Section(footer: Text("If a permission was previously denied in macOS, open System Settings to adjust permissions manually.")) {
                Button(action: { model.openSystemPrivacySettings() }) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                        Text("Open macOS Privacy & Security Settings...")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            model.refreshPermissionStates()
        }
    }
}

struct LiveActivitiesView: View {
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        Form {
            Section(header: Text("Dynamic Island Modules"), footer: Text("Choose which live activities and widgets appear in the Dynamic Notch and its integrated mini switcher.")) {
                HStack {
                    Image(systemName: "switch.2")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control Center Quick Toggles")
                            .font(.system(size: 13, weight: .medium))
                        Text("Wi-Fi, Bluetooth, Brightness, Volume & AirPods controls")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showControlCenter)
                        .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.pink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music & Media Player")
                            .font(.system(size: 13, weight: .medium))
                        Text("Album art, interactive scrubber, waveform & playback controls")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showMusic)
                        .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "airpodspro")
                        .foregroundStyle(.white)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirPods Integration")
                            .font(.system(size: 13, weight: .medium))
                        Text("Connection status, real-time battery gauges & listening modes")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showAirPodsLocalization)
                        .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phone & FaceTime")
                            .font(.system(size: 13, weight: .medium))
                        Text("Displays live call status and mute/end call actions")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showPhone)
                        .labelsHidden()
                }
                
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.red)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Notifications")
                            .font(.system(size: 13, weight: .medium))
                        Text("Dynamic floating alert cards in the notch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showNotifications)
                        .labelsHidden()
                }
                
                HStack {
                    AirDropSymbolView(size: 20, color: .cyan)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirDrop Sharing")
                            .font(.system(size: 13, weight: .medium))
                        Text("Displays live file transfer progress in the notch")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.showAirDrop)
                        .labelsHidden()
                }
            }
            

            
            Section(header: Text("Live Activity Previews & Simulations")) {
                HStack {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text("Apple Music Player")
                    Spacer()
                    Button(model.state == .expandedMusic ? "Terminate" : "Simulate") {
                        model.toggleState(.expandedMusic)
                    }
                }
                
                HStack {
                    Image(systemName: "bag.fill")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                    Text("Food Delivery")
                    Spacer()
                    Button(model.state == .expandedFood ? "Terminate" : "Simulate") {
                        model.toggleState(.expandedFood)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

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
    
    let scrubberWidth: CGFloat = 220
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

struct AirDropFilePreviewCard: View {
    let files: [URL]
    
    var firstURL: URL? { files.first }
    
    var thumbnailImage: NSImage? {
        guard let url = firstURL else { return nil }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "icns"].contains(ext) {
            if let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    var fileSizeString: String {
        guard let url = firstURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return ""
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // BIGGER Image / File Preview
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 72, height: 72)
                
                if let thumb = thumbnailImage {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: files.count > 1 ? "doc.on.doc.fill" : "doc.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.cyan)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
            
            // File Information Details
            VStack(alignment: .leading, spacing: 4) {
                if files.count == 1, let first = firstURL {
                    Text(first.lastPathComponent)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        if !fileSizeString.isEmpty {
                            Text(fileSizeString)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Text("• Ready to AirDrop")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.95))
                    }
                } else {
                    Text("\(max(1, files.count)) Files Selected")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(files.map { $0.lastPathComponent }.prefix(2).joined(separator: ", ") + (files.count > 2 ? "..." : ""))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                    
                    Text("Ready to share with nearby devices")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.95))
                }
            }
            
            Spacer()
        }
    }
}

struct AirDropDeviceButton: View {
    let name: String
    let sublabel: String
    let icon: String
    var isAccent: Bool = false
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isAccent ? Color.blue : (isHovered ? Color.white.opacity(0.24) : Color.white.opacity(0.12)))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(isHovered ? Color.cyan.opacity(0.85) : Color.white.opacity(0.16), lineWidth: 1.2)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 1) {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if !sublabel.isEmpty {
                        Text(sublabel)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = h
            }
        }
    }
}


struct AirPodsHeadIcon: View {
    let mode: Int
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            if mode == 2 {
                // Noise Cancellation: Solid dome arc over head
                ZStack {
                    ArcShape(startAngle: .degrees(130), endAngle: .degrees(50))
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                }
            } else if mode == 4 {
                // Adaptive: iOS Starburst Sparkles around head
                ZStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.75))
                        .offset(x: 6, y: -6)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                }
            } else {
                // Transparency: Radiating dotted rays around head
                ZStack {
                    ArcShape(startAngle: .degrees(130), endAngle: .degrees(50))
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [2, 3]))
                        .frame(width: 20, height: 20)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                }
            }
        }
        .frame(width: 32, height: 32)
    }
}

struct AirDropReceivingModeSlider: View {
    @ObservedObject var model: IslandModel
    
    let modes = [0, 1, 2]
    let titles = ["Off", "Contacts Only", "Everyone"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AIRDROP RECEIVING")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.leading, 2)
                Spacer()
                Text(titles[min(2, max(0, model.airDropMode))])
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.cyan)
                    .padding(.trailing, 2)
            }
            
            VStack(spacing: 5) {
                // Liquid Glass Capsule Track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .background(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                        
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { i in
                                let modeVal = modes[i]
                                let isSelected = model.airDropMode == modeVal
                                
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        model.setAirDropMode(modeVal)
                                    }
                                } label: {
                                    ZStack {
                                        if isSelected {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.cyan, Color.blue],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 32, height: 32)
                                                .shadow(color: Color.cyan.opacity(0.45), radius: 5, x: 0, y: 1)
                                        }
                                        
                                        Group {
                                            if modeVal == 0 {
                                                Image(systemName: "nosign")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                                            } else if modeVal == 1 {
                                                Image(systemName: "person.2.fill")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                                            } else {
                                                Image(systemName: "globe")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let fraction = max(0.0, min(1.0, gesture.location.x / geo.size.width))
                                let index = min(2, max(0, Int(fraction * 3.0)))
                                let newMode = modes[index]
                                if model.airDropMode != newMode {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        model.setAirDropMode(newMode)
                                    }
                                }
                            }
                    )
                }
                .frame(height: 34)
                
                // Labels underneath the capsule pill
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        let modeVal = modes[i]
                        let isSelected = model.airDropMode == modeVal
                        Text(titles[i])
                            .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .cyan : .white.opacity(0.55))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .frame(width: 340)
    }
}

struct AirPodsListeningModeSlider: View {
    @ObservedObject var model: IslandModel
    
    // Modes matching iOS 1:1: 2: Noise Cancellation, 4: Adaptive, 3: Transparency
    let modes = [2, 4, 3]
    let titles = ["Noise Cancellation", "Adaptive", "Transparency"]
    
    @State private var dragX: CGFloat? = nil
    
    private func currentModeIndex() -> Int {
        modes.firstIndex(of: model.listeningMode) ?? 1
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("NOISE CONTROL")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.leading, 2)
                Spacer()
                let idx = currentModeIndex()
                Text(titles[idx])
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(.trailing, 2)
            }
            
            VStack(spacing: 5) {
                // Liquid Glass Capsule Track with Smooth Sliding & Dragging Pill
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let segmentWidth = totalWidth / 3.0
                    let pillSize: CGFloat = 32
                    let activeIndex = currentModeIndex()
                    let standardPillCenter = (CGFloat(activeIndex) * segmentWidth) + (segmentWidth / 2.0)
                    let pillCenterX = dragX ?? standardPillCenter
                    let pillLeadingX = pillCenterX - (pillSize / 2.0)
                    
                    ZStack(alignment: .leading) {
                        // Frosted Liquid Glass Track
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .background(
                                Capsule(style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.6
                                    )
                            )
                        
                        // Floating Liquid Glass Sliding Indicator
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.1, green: 0.58, blue: 1.0), Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: pillSize, height: pillSize)
                            .shadow(color: Color.blue.opacity(0.5), radius: 5, x: 0, y: 1.5)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
                            )
                            .offset(x: max(2, min(totalWidth - pillSize - 2, pillLeadingX)))
                            .animation(dragX == nil ? .spring(response: 0.32, dampingFraction: 0.75) : .none, value: pillLeadingX)
                        
                        // Buttons & Icons
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { i in
                                let modeVal = modes[i]
                                let isSelected = (dragX == nil ? model.listeningMode : modes[min(2, max(0, Int(pillCenterX / segmentWidth)))]) == modeVal
                                
                                Button {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                        dragX = nil
                                        model.setAirPodsMode(modeVal)
                                    }
                                } label: {
                                    AirPodsHeadIcon(mode: modeVal, isSelected: isSelected)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                dragX = max(pillSize / 2.0, min(totalWidth - (pillSize / 2.0), gesture.location.x))
                                let closestIndex = min(2, max(0, Int(gesture.location.x / segmentWidth)))
                                let newMode = modes[closestIndex]
                                if model.listeningMode != newMode {
                                    model.setAirPodsMode(newMode)
                                }
                            }
                            .onEnded { gesture in
                                let closestIndex = min(2, max(0, Int(gesture.location.x / segmentWidth)))
                                let finalMode = modes[closestIndex]
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                    dragX = nil
                                    model.setAirPodsMode(finalMode)
                                }
                            }
                    )
                }
                .frame(height: 36)
                
                // Labels underneath the capsule pill
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        let modeVal = modes[i]
                        let isSelected = model.listeningMode == modeVal
                        Text(titles[i])
                            .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .blue : .white.opacity(0.55))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .frame(width: 340)
    }
}



struct SettingsWindowPreviewer: View {
    @ObservedObject var model: IslandModel
    var activePane: SettingsPane = .background
    
    var body: some View {
        ZStack {
            // Desktop canvas environment
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.15, blue: 0.25), Color(red: 0.05, green: 0.07, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Miniature 1:1 Scale-Faithful dyNotch Settings Window Replica
            ZStack {
                SettingsWindowBackground(
                    style: model.settingsBackgroundStyle,
                    opacity: model.settingsWindowOpacity,
                    glass: model.settingsGlassIntensity,
                    blurRadius: model.settingsWallpaperBlur * 0.35,
                    customImage: model.customWallpaperImage
                )
                
                VStack(spacing: 0) {
                    // Window Titlebar
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.34)).frame(width: 6, height: 6)
                            Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.18)).frame(width: 6, height: 6)
                            Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.26)).frame(width: 6, height: 6)
                        }
                        
                        Spacer()
                        
                        Text("dyNotch")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Color.clear.frame(width: 24, height: 6)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.30))
                    
                    Divider().opacity(0.25)
                    
                    // Main Window Layout
                    HStack(spacing: 0) {
                        // Left Sidebar Replica (reflecting collapsed state if active)
                        VStack(alignment: model.isSidebarCollapsed ? .center : .leading, spacing: 2) {
                            HStack {
                                if !model.isSidebarCollapsed {
                                    Text("dyNotch")
                                        .font(.system(size: 6.5, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: model.isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                                    .font(.system(size: 5.5, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 3)
                            
                            ForEach(SettingsPane.allCases) { pane in
                                let isSelected = pane == activePane
                                HStack(spacing: 3) {
                                    Image(systemName: pane.icon)
                                        .font(.system(size: 5.5, weight: isSelected ? .bold : .regular))
                                        .frame(width: 8)
                                    if !model.isSidebarCollapsed {
                                        Text(pane.rawValue)
                                            .font(.system(size: 5.5, weight: isSelected ? .bold : .regular))
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, model.isSidebarCollapsed ? 2 : 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(isSelected ? Color.blue : Color.clear)
                                )
                                .foregroundColor(isSelected ? .white : .white.opacity(0.75))
                            }
                            Spacer()
                        }
                        .frame(width: model.isSidebarCollapsed ? 32 : 90)
                        .background(Color.black.opacity(0.25))
                        
                        Divider().opacity(0.25)
                        
                        // Right Detail Area Replica
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activePane.rawValue)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.top, 3)
                            
                            // Miniature Wallpaper Cards Grid
                            HStack(spacing: 3) {
                                ForEach(SettingsBackgroundStyle.allCases.prefix(4)) { style in
                                    let isCur = model.settingsBackgroundStyle == style
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 2.5)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.5)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        Text(style.rawValue)
                                            .font(.system(size: 4, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    }
                                    .frame(height: 18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2.5)
                                            .stroke(isCur ? Color.white : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                            
                            // Sliders Replica Card
                            VStack(spacing: 2.5) {
                                HStack {
                                    Text("Blur & Glass")
                                        .font(.system(size: 5))
                                        .foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Capsule()
                                        .fill(Color.blue)
                                        .frame(width: 35, height: 3)
                                }
                                HStack {
                                    Text("Window Opacity")
                                        .font(.system(size: 5))
                                        .foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Capsule()
                                        .fill(Color.blue)
                                        .frame(width: 45, height: 3)
                                }
                            }
                            .padding(3.5)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(3.5)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(width: 420, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 7)
        }
    }
}

struct BackgroundSettingsView: View {
    @ObservedObject var model = IslandModel.shared
    @Binding var selectedPane: SettingsPane
    
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Top macOS-style Wallpaper & Window Previewer
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live Window Preview")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("Real-time 1:1 replica of dyNotch")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    SettingsWindowPreviewer(model: model, activePane: selectedPane)
                        .frame(height: 195)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 28)
                
                // Wallpaper Gallery Selector
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Choose Window Wallpaper")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Pick from Pictures Button
                        Button {
                            model.pickCustomWallpaper()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add from Photos...")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(SettingsBackgroundStyle.allCases) { style in
                            let isSelected = model.settingsBackgroundStyle == style
                            Button {
                                if style == .customPicture && model.customWallpaperImage == nil {
                                    model.pickCustomWallpaper()
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        model.settingsBackgroundStyle = style
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ZStack {
                                        SettingsWindowBackground(
                                            style: style,
                                            opacity: 1.0,
                                            glass: 0.8,
                                            blurRadius: 0,
                                            customImage: model.customWallpaperImage
                                        )
                                        .frame(height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        
                                        Image(systemName: style.icon)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.6), radius: 3)
                                        
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.blue, lineWidth: 3)
                                            
                                            VStack {
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.blue)
                                                        .background(Circle().fill(Color.white))
                                                        .font(.system(size: 13))
                                                        .padding(4)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(style.rawValue)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(style.subtitle)
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                }
                                .padding(5)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? Color.blue.opacity(0.20) : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? Color.blue.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 28)
                
                // Form Sliders: Smooth without percentage numbers!
                VStack(spacing: 10) {
                    // Wallpaper Blur Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Wallpaper Blur Effect", systemImage: "aqi.medium")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(model.settingsWallpaperBlur == 0 ? "Clear" : (model.settingsWallpaperBlur > 25 ? "Full Blur" : "Soft Blur"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        HStack {
                            Image(systemName: "photo")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                            Slider(value: $model.settingsWallpaperBlur, in: 0.0...40.0)
                            Image(systemName: "bubbles.and.sparkles.fill")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .cornerRadius(10)
                    
                    // Liquid Glass Specular Intensity
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Liquid Glass Specular Reflection", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(model.settingsGlassIntensity == 0 ? "Off" : (model.settingsGlassIntensity > 0.75 ? "Full" : "Active"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        HStack {
                            Image(systemName: "drop")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                            Slider(value: $model.settingsGlassIntensity, in: 0.0...1.0)
                            Image(systemName: "drop.fill")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .cornerRadius(10)
                    
                    // Window Transparency Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Window Opacity", systemImage: "square.2.layers.3d.top.filled")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(model.settingsWindowOpacity >= 0.95 ? "Full Solid" : (model.settingsWindowOpacity <= 0.45 ? "Translucent" : "Balanced"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                        }
                        HStack {
                            Image(systemName: "circle.dotted")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                            Slider(value: $model.settingsWindowOpacity, in: 0.25...1.0)
                            Image(systemName: "circle.fill")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .padding(.top, 6)
        }
    }
}


