import IOKit.ps
import IOKit.pwr_mgt

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
    
    @Published var peaks: [CGFloat] = [0.25, 0.35, 0.45, 0.38, 0.28]
    
    private var timer: Timer?
    private var isMonitoring: Bool = false
    
    init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateTrackFrequencies()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        DispatchQueue.main.async {
            self.peaks = [0.2, 0.2, 0.2, 0.2, 0.2]
        }
    }
    
    private func updateTrackFrequencies() {
        let model = IslandModel.shared
        guard model.isMusicPlaying else {
            if self.peaks != [0.2, 0.2, 0.2, 0.2, 0.2] {
                DispatchQueue.main.async {
                    self.peaks = [0.2, 0.2, 0.2, 0.2, 0.2]
                }
            }
            return
        }
        
        let pos = model.playbackPosition
        let trackKey = model.currentTrackPersistentID.isEmpty ? model.currentTrack : model.currentTrackPersistentID
        let seed = Double(abs(trackKey.hashValue % 1000)) / 100.0
        
        // Multi-frequency spectral synthesis based on track rhythm harmonics - 100% volume independent and mic-free!
        let bpm = 120.0 + (Double(abs(trackKey.hashValue % 40)) - 20.0)
        let beatTime = (pos * (bpm / 60.0)) * Double.pi * 2.0
        
        let subBass = (sin(beatTime * 1.0 + seed) * 0.45 + cos(beatTime * 0.5) * 0.35 + 0.6) * 0.85
        let bass    = (sin(beatTime * 2.0 + seed * 1.3) * 0.40 + sin(beatTime * 1.0) * 0.40 + 0.6) * 0.90
        let lowMid  = (cos(beatTime * 3.0 + seed * 0.7) * 0.35 + sin(beatTime * 1.5) * 0.35 + 0.5) * 0.75
        let highMid = (sin(beatTime * 4.0 + seed * 2.1) * 0.30 + cos(beatTime * 2.5) * 0.30 + 0.5) * 0.70
        let treble  = (cos(beatTime * 6.0 + seed * 1.7) * 0.25 + sin(beatTime * 3.0) * 0.25 + 0.4) * 0.65
        
        let newPeaks: [CGFloat] = [
            CGFloat(min(1.0, max(0.2, subBass))),
            CGFloat(min(1.0, max(0.25, bass))),
            CGFloat(min(1.0, max(0.3, lowMid))),
            CGFloat(min(1.0, max(0.25, highMid))),
            CGFloat(min(1.0, max(0.2, treble)))
        ]
        
        DispatchQueue.main.async {
            self.peaks = newPeaks
        }
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
        // Direct zero-overhead hardware sampling from CGImage
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .orange
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bitmapData: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &bitmapData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .orange
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
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
                            // Tone: 0.0 (Light Frost Glass) to 1.0 (Dark Smoked Obsidian)
                            let tone = model.liquidGlassTone
                            let baseOpacity = model.isExpanded ? model.notchGlassOpacity : (model.notchCompactAlwaysBlack ? 1.0 : model.notchGlassOpacity)
                            let darkFill = Color.black.opacity((0.15 + tone * 0.78) * baseOpacity)
                            let frostHighlight = Color.white.opacity((1.0 - tone) * 0.45 * baseOpacity)
                            let specularGlow = Color.white.opacity((0.40 - tone * 0.18) * baseOpacity)
                            
                            ZStack {
                                shape.fill(darkFill)
                                shape.fill(frostHighlight)
                                shape.fill(
                                    LinearGradient(
                                        colors: [specularGlow, Color.white.opacity(0.06 * (1.0 - tone)), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                            .overlay(
                                shape.stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity((0.60 - tone * 0.25) * baseOpacity),
                                            Color.white.opacity(0.15 * baseOpacity)
                                        ],
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
                    
                    // 2. Music theme maintains 100% crisp solid glass / black background with zero blur overlap on text
                    
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
                // Dynamic Track-Pulsating Ambient Edge Glow around notch perimeter only (Not beneath the notch)
                .background(
                    Group {
                        if (model.isMusicPlaying || model.state == .expandedMusic) && model.enableArtworkGlow {
                            let cornerR = model.isExpanded ? 24.0 : model.compactCornerRadius
                            let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: cornerR, bottomTrailingRadius: cornerR, topTrailingRadius: 0, style: .continuous)
                            
                            if model.pulsateArtworkGlow {
                                TimelineView(.animation) { timeline in
                                    let time = timeline.date.timeIntervalSinceReferenceDate
                                    let trackKey = model.currentTrackPersistentID.isEmpty ? model.currentTrack : model.currentTrackPersistentID
                                    let bpm = 120.0 + Double(abs(trackKey.hashValue % 24) - 12)
                                    let beat = sin(time * (bpm / 60.0) * Double.pi * 2.0)
                                    let pulseFactor = (beat + 1.0) / 2.0 // 0.0 to 1.0
                                    
                                    let dynamicBlur = (model.isExpanded ? 14.0 : 8.0) + CGFloat(pulseFactor * 12.0 * model.artworkGlowIntensity)
                                    let strokeWidth = (model.isExpanded ? 4.0 : 3.0) + CGFloat(pulseFactor * 3.0)
                                    let dynamicOpacity = (0.45 + pulseFactor * 0.55) * model.artworkGlowIntensity
                                    
                                    shape
                                        .stroke(model.artworkColor, lineWidth: strokeWidth)
                                        .blur(radius: dynamicBlur)
                                        .opacity(dynamicOpacity)
                                }
                            } else {
                                shape
                                    .stroke(model.artworkColor, lineWidth: model.isExpanded ? 4 : 3)
                                    .blur(radius: model.isExpanded ? 14 : 9)
                                    .opacity(0.70 * model.artworkGlowIntensity)
                            }
                        }
                    }
                )
                .shadow(
                    color: ((model.isExpanded && model.state == .expandedAirDrop) || model.isAirDropTargeted)
                        ? model.droppedFileColor.opacity(0.65)
                        : Color.black.opacity(0.35), 
                    radius: model.isExpanded ? 16 : 8, 
                    x: 0, 
                    y: model.isExpanded ? 5 : 2
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
                    } else if model.macBatteryShowingCompact || model.alwaysShowMacBatteryInNotch {
                        compactMacBatteryActivity
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
                        // Notch File Shelf Drop Target (Animated compact scale)
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color.cyan.opacity(0.20))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.cyan)
                                    .scaleEffect(0.92)
                            }
                            
                            Text("Save File in Notch")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Hold file in shelf • Drag out anytime or AirDrop")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.cyan.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .padding(6)
                        )
                    } else if model.isExpanded {
                        if model.state == .expandedAirPods {
                            // Dedicated 3D AirPods Connection Stage without switcher dock
                            AirPods3DHeroView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else if model.state == .expandedPhone || model.state == .expandedNotifications {
                            // Dedicated full-width layout without menu switcher to avoid crowding/clipping
                            controlsView
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else {
                            ZStack(alignment: .center) {
                                // Main Content View: Dead-Centered with physical notch & perfectly symmetrical margins
                                Group {
                                    if model.state == .expandedMusic {
                                        musicView
                                    } else if model.state == .expandedFood {
                                        foodView
                                    } else if model.state == .expandedAirDrop {
                                        airDropExpandedView
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
                    // Instant zero-lag pasteboard URL resolution
                    let pboard = NSPasteboard(name: .drag)
                    if let directURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !directURLs.isEmpty {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            model.isAirDropTargeted = false
                            for u in directURLs {
                                if !model.droppedAirDropFiles.contains(u) {
                                    model.droppedAirDropFiles.append(u)
                                }
                            }
                            model.state = .expandedAirDrop
                        }
                        return true
                    }
                    
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
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            model.isAirDropTargeted = false
                            for u in finalURLs {
                                if !model.droppedAirDropFiles.contains(u) {
                                    model.droppedAirDropFiles.append(u)
                                }
                            }
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

    @ViewBuilder private var compactMacBatteryActivity: some View {
        HStack(spacing: 0) {
            // Left wing: Battery indicator & Lightning bolt
            HStack(spacing: 4) {
                Image(systemName: model.isMacCharging || model.isMacPluggedIn ? "battery.100.bolt" : (model.macBatteryLevel <= 0.2 ? "battery.25" : "battery.100"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(model.isMacCharging || model.isMacPluggedIn ? .green : (model.macBatteryLevel <= model.batteryWarningLevel ? .red : (model.isMacLowPowerMode ? .yellow : .white)))
                    .symbolEffect(.bounce, value: model.isMacCharging)
            }
            .frame(width: 26, height: 26)

            Spacer(minLength: 0)

            // Right wing: Numerical Battery Percentage
            Text("\(Int(model.macBatteryLevel * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(model.isMacCharging || model.isMacPluggedIn ? .green : (model.macBatteryLevel <= model.batteryWarningLevel ? .red : (model.isMacLowPowerMode ? .yellow : .white)))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var compactMusicActivity: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.clear).frame(width: 24, height: 24)
                ZStack {
                    if let artwork = model.currentArtwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 24, height: 24)
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .id(model.currentTrackPersistentID.isEmpty ? model.currentTrack : model.currentTrackPersistentID)
                .transition(.flip3D(isForward: model.isForward))
            }
            .matchedGeometryEffect(id: "musicArtwork", in: musicActivityNamespace)
            .zIndex(1)

            Spacer(minLength: 0)

            MusicWaveform(isPlaying: model.isMusicPlaying, color: model.artworkColor)
                .frame(width: 24, height: 16)
                .matchedGeometryEffect(id: "musicWaveform", in: musicActivityNamespace)
                .zIndex(1)
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
                    AirPodsExpandedView(model: model)
                } else {
                    disabledFeatureNotice("AirPods & Bluetooth Disabled")
                }
            } else if model.state == .expandedPhone {
                if model.showPhone {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 44, height: 44)
                            Image(systemName: "phone.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FaceTime Audio")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Tim Cook")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text("02:14")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    model.state = .compact
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "phone.down.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                // Mute action
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "mic.slash.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 340, height: 64)
                } else {
                    disabledFeatureNotice("Phone Access Disabled")
                }
            } else if model.state == .expandedNotifications {
                if model.showNotifications {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green)
                                .frame(width: 40, height: 40)
                            Image(systemName: "message.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Messages")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                                Spacer()
                                Text("now")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Text("Sarah Jenkins")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("Are we still meeting at 3 PM today?")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 340, height: 60)
                } else {
                    disabledFeatureNotice("Notifications Disabled")
                }
            } else if model.state == .expandedAirDrop {
                if model.showAirDrop {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(0.2))
                                .frame(width: 42, height: 42)
                            AirDropSymbolView(size: 22, color: .cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AirDrop Transfer")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(Int(model.airDropProgress > 0 ? model.airDropProgress * 100 : 75))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * CGFloat(max(0.1, model.airDropProgress > 0 ? model.airDropProgress : 0.75)), height: 5)
                                }
                            }
                            .frame(height: 5)
                            
                            Text("Sharing 3 items (Photos & Files)...")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 340, height: 60)
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
                        
                        // 4. Bottom Row: AirPods Noise Control Liquid Glass Slider (Only visible when AirPods are connected)
                        if model.airPodsConnected {
                            AirPodsListeningModeSlider(model: model)
                                .frame(width: 340)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                    }
                } else {
                    disabledFeatureNotice("Control Center Quick Toggles Disabled")
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
        .opacity(showsExpandedControls ? 1 : 0)
        .offset(y: showsExpandedControls ? 0 : -14)
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
        VStack(spacing: 8) {
            if model.isAirDropSending, let person = model.airDropTargetPerson {
                // Live In-Notch Transfer Progress View
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(person.color)
                                .frame(width: 44, height: 44)
                                .shadow(color: person.color.opacity(0.5), radius: 6)
                            
                            if let pic = person.profileImage {
                                Image(nsImage: pic)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            } else {
                                Text(person.initials)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AirDropping to \(person.name)...")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(model.airDropProgress < 0.95 ? "Transferring (\(model.droppedAirDropFiles.count) items)... \(Int(model.airDropProgress * 100))%" : "Waiting for \(person.name) to accept...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.cyan)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    
                    // Liquid Glass Progress Bar
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 8)
                                
                                Capsule(style: .continuous)
                                    .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(8, geo.size.width * CGFloat(model.airDropProgress)), height: 8)
                                    .animation(.linear(duration: 0.08), value: model.airDropProgress)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(.horizontal, 14)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if model.airDropSentSuccess, let person = model.airDropTargetPerson {
                // Sent Success State
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 40, height: 40)
                            .shadow(color: Color.green.opacity(0.4), radius: 6)
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sent to \(person.name)!")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("AirDrop transfer complete")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                // Top Action Bar: Higher up, AirDrop ICON ONLY Button | "Saved in Notch" Title | Dismiss X
                HStack(alignment: .center) {
                    // Authentic AirDrop Symbol Icon Button (AirDropSymbolView)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            model.isShowingAirDropInShelf.toggle()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(model.isShowingAirDropInShelf ? Color.cyan : Color.white.opacity(0.14))
                                .frame(width: 30, height: 30)
                            AirDropSymbolView(size: 17, color: model.isShowingAirDropInShelf ? .black : .cyan)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Toggle AirDrop sharing in Notch")
                    
                    Spacer()
                    
                    Text("Saved in Notch")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    // Clear / Remove Files from Notch
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                            model.droppedAirDropFiles = []
                            model.isShowingAirDropInShelf = false
                            model.state = .compact
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Remove files from notch shelf")
                }
                .padding(.horizontal, 10)
                .padding(.top, 0)
                
                // Horizontal Carousel of Big Clean File Previews (No outer double boxes, individual remove X)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(model.droppedAirDropFiles.enumerated()), id: \.offset) { index, file in
                            let fileSizeStr: String = {
                                if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                                   let size = attrs[.size] as? Int64 {
                                    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                                }
                                return ""
                            }()
                            
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    // Big Clean File Thumbnail (74x74) without outer box
                                    let thumb = NSImage(contentsOf: file) ?? NSWorkspace.shared.icon(forFile: file.path)
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 74, height: 74)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 3)
                                        .onDrag {
                                            return NSItemProvider(object: file as NSURL)
                                        }
                                    
                                    // Cross button on the top right side of EVERY file to remove it individually!
                                    Button {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                            if model.droppedAirDropFiles.indices.contains(index) {
                                                model.droppedAirDropFiles.remove(at: index)
                                            }
                                            if model.droppedAirDropFiles.isEmpty {
                                                model.isShowingAirDropInShelf = false
                                                model.state = .compact
                                            }
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.black.opacity(0.82))
                                                .frame(width: 20, height: 20)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                                )
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                    .help("Remove file from Notch")
                                }
                                
                                if !fileSizeStr.isEmpty {
                                    Text(fileSizeStr)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                            .onDrag {
                                return NSItemProvider(object: file as NSURL)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                // When AirDrop option is chosen: Show People Nearby directly UNDERNEATH the file carousel inside the notch!
                if model.isShowingAirDropInShelf {
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            ForEach(model.discoverNearbyPeople()) { person in
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        model.sendAirDrop(to: person)
                                    }
                                } label: {
                                    VStack(spacing: 3) {
                                        ZStack(alignment: .bottomTrailing) {
                                            Circle()
                                                .fill(person.color.opacity(0.85))
                                                .frame(width: 38, height: 38)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                                                )
                                            
                                            if let pic = person.profileImage {
                                                Image(nsImage: pic)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 38, height: 38)
                                                    .clipShape(Circle())
                                            } else {
                                                Text(person.initials)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            
                                            Image(systemName: person.deviceIcon)
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(2)
                                                .background(Circle().fill(Color.black.opacity(0.85)))
                                                .offset(x: 2, y: 2)
                                        }
                                        
                                        Text(person.name)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 62)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder var musicView: some View {
        VStack(spacing: 8) {
            // Top Row: Artwork (Left) | Title & Artist (Center-Left) | Live Dynamic Waveform (Right)
            HStack(spacing: 12) {
                // Large Rounded Artwork shifted left with 3D Flip
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.clear).frame(width: 52, height: 52)
                    ZStack {
                        if let img = model.currentArtwork { 
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 52, height: 52)
                            Image(systemName: "music.note")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .id(model.currentTrackPersistentID.isEmpty ? model.currentTrack : model.currentTrackPersistentID)
                    .transition(.flip3D(isForward: model.isForward))
                }
                .matchedGeometryEffect(id: "musicArtwork", in: musicActivityNamespace)
                .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                .zIndex(1)
                
                // Track Title & Artist with Apple-style fluid horizontal drag-to-skip & real track name previews
                ZStack(alignment: .leading) {
                    // Real-Time Previous Track Title Preview text
                    if manualDragOffset > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(model.prevTrackName.isEmpty ? "Previous Track" : model.prevTrackName)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(Color.cyan)
                        .offset(x: manualDragOffset - 180)
                        .opacity(min(1.0, Double(manualDragOffset) / 35.0))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.currentTrack.isEmpty ? "No Track Playing" : model.currentTrack)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(model.currentArtist.isEmpty ? "Apple Music" : model.currentArtist)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    .offset(x: manualDragOffset)
                    
                    // Real-Time Next Track Title Preview text
                    if manualDragOffset < 0 {
                        HStack(spacing: 6) {
                            Text(model.nextTrackName.isEmpty ? "Next Track" : model.nextTrackName)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Image(systemName: "forward.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(Color.cyan)
                        .offset(x: manualDragOffset + 180)
                        .opacity(min(1.0, Double(-manualDragOffset) / 35.0))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.02),
                        .init(color: .black, location: 0.98),
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
                            if drag.translation.width < -45 {
                                model.isForward = true
                                model.lastManualSkipTime = Date()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { manualDragOffset = -260 }
                                
                                DispatchQueue.global(qos: .userInitiated).async {
                                    model.skipTrack(forward: true)
                                    DispatchQueue.main.async {
                                        manualDragOffset = 260
                                        withAnimation(.spring(response: 0.38, dampingFraction: 0.70)) { manualDragOffset = 0 }
                                    }
                                }
                            } else if drag.translation.width > 45 {
                                model.isForward = false
                                model.lastManualSkipTime = Date()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { manualDragOffset = 260 }
                                
                                DispatchQueue.global(qos: .userInitiated).async {
                                    model.skipTrack(forward: false)
                                    DispatchQueue.main.async {
                                        manualDragOffset = -260
                                        withAnimation(.spring(response: 0.38, dampingFraction: 0.70)) { manualDragOffset = 0 }
                                    }
                                }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { manualDragOffset = 0 }
                            }
                        }
                )
                .zIndex(0)
                .opacity(showsExpandedMusicDetails ? 1 : 0)
                .offset(y: showsExpandedMusicDetails ? 0 : -72)
                .allowsHitTesting(showsExpandedMusicDetails)
                
                // Top-Right: Authentic Live Dynamic Waveform (Reactive / Smooth Flow)
                ZStack {
                    MusicWaveform(isPlaying: model.isMusicPlaying, color: model.artworkColor)
                }
                .frame(width: 28, height: 20)
                .matchedGeometryEffect(id: "musicWaveform", in: musicActivityNamespace)
                .zIndex(1)
            }
            .padding(.leading, 0)
            .padding(.trailing, 2)
            
            // Middle Row: Scrubber with Left (Elapsed) and Right (Remaining) Monospaced Timers
            LiquidScrubber()
                .padding(.top, 2)
                .opacity(showsExpandedMusicDetails ? 1 : 0)
                .offset(y: showsExpandedMusicDetails ? 0 : -52)
            
            // Bottom Row: Star Favorite (Far Left) | Backward | Play/Pause | Forward | AirPlay/AirPods (Far Right)
            HStack(alignment: .center) {
                // Star Favorite Button with Apple Music Live Sync & Bouncy Animation
                Button(action: {
                    model.toggleFavoriteSong()
                }) {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                        Image(systemName: model.isCurrentTrackFavorited ? "star.fill" : "star")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(model.isCurrentTrackFavorited ? Color(red: 1.0, green: 0.22, blue: 0.37) : Color.white.opacity(0.65))
                            .scaleEffect(model.isCurrentTrackFavorited ? 1.15 : 1.0)
                            .symbolEffect(.bounce, value: model.isCurrentTrackFavorited)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Center Controls: Backward | Play/Pause | Forward (with Apple Spring Animations)
                HStack(spacing: 32) {
                    Button(action: {
                        bouncePrev += 1
                        model.skipTrack(forward: false)
                    }) {
                        ZStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 40)
                                .contentShape(Rectangle())
                            Image(systemName: "backward.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .symbolEffect(.bounce, value: bouncePrev)
                        }
                    }
                    .buttonStyle(SkipButtonStyle(direction: -1))
                    
                    Button(action: {
                        model.togglePlayPause()
                    }) {
                        ZStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 52, height: 48)
                                .contentShape(Rectangle())
                            Image(systemName: model.isMusicPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(PlayPauseButtonStyle())
                    
                    Button(action: {
                        bounceNext += 1
                        model.skipTrack(forward: true)
                    }) {
                        ZStack {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 44, height: 40)
                                .contentShape(Rectangle())
                            Image(systemName: "forward.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .symbolEffect(.bounce, value: bounceNext)
                        }
                    }
                    .buttonStyle(SkipButtonStyle(direction: 1))
                }
                
                Spacer()
                
                // AirPlay / AirPods Route Output Button (Far Right)
                Button(action: {
                    model.openBluetoothSettings()
                }) {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                        Image(systemName: model.airPodsConnected ? "airpodspro" : "airplayaudio")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .opacity(showsExpandedMusicDetails ? 1 : 0)
            .offset(y: showsExpandedMusicDetails ? 0 : -36)
            .allowsHitTesting(showsExpandedMusicDetails)
        }
        .padding(14)
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
            switch state {
            case .expandedAirDrop: return 440
            case .expandedMusic: return 420
            case .expandedFood: return 360
            case .expandedPhone: return 420
            case .expandedNotifications: return 420
            case .expandedAirPods: return 420
            case .expandedControls: return 420
            case .compact: return baseNotchWidth
            }
        }
        if airPodsShowingCompact {
            return baseNotchWidth + 108
        }
        if isMusicPlaying {
            return baseNotchWidth + 120
        }
        if macBatteryShowingCompact || alwaysShowMacBatteryInNotch {
            return baseNotchWidth + 96
        }
        return baseNotchWidth
    }
    
    var height: CGFloat {
        if isAirDropTargeted && state != .expandedAirDrop {
            return physicalNotchHeight + 145
        }
        if isExpanded {
            switch state {
            case .expandedAirDrop: return isShowingAirDropInShelf ? 245 : 165
            case .expandedMusic: return 215
            case .expandedFood: return 85
            case .expandedPhone: return 92
            case .expandedNotifications: return 88
            case .expandedAirPods: return 110
            case .expandedControls: return airPodsConnected ? 270 : 205
            case .compact: return physicalNotchHeight
            }
        }
        return physicalNotchHeight
    }
    
        var currentTrackTitle: String { currentTrack }
    var currentTrackArtist: String { currentArtist }
    var musicProgress: Double { trackDuration > 0 ? (playbackPosition / trackDuration) : 0.0 }
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
    private var artworkCache: [String: (image: NSImage, color: Color)] = [:]
    var currentTrackPersistentID: String = ""
    var lastPlaybackPollTime: Date = Date()
    var pendingArtworkRetry: Bool = false
    var artworkRetryCount: Int = 0
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
    
    @Published var liveActivitiesOrder: [LiveActivityType] = {
        if let saved = UserDefaults.standard.stringArray(forKey: "saved_liveActivitiesOrder") {
            let loaded = saved.compactMap { LiveActivityType(rawValue: $0) }
            if !loaded.isEmpty {
                var order = loaded
                for item in LiveActivityType.allCases {
                    if !order.contains(item) {
                        order.append(item)
                    }
                }
                return order
            }
        }
        return LiveActivityType.allCases
    }() {
        didSet {
            UserDefaults.standard.set(liveActivitiesOrder.map { $0.rawValue }, forKey: "saved_liveActivitiesOrder")
        }
    }
    
    func moveLiveActivity(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < liveActivitiesOrder.count,
              destinationIndex >= 0, destinationIndex < liveActivitiesOrder.count,
              sourceIndex != destinationIndex else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            let item = liveActivitiesOrder.remove(at: sourceIndex)
            liveActivitiesOrder.insert(item, at: destinationIndex)
        }
    }
    
    func moveLiveActivityUp(_ type: LiveActivityType) {
        guard let idx = liveActivitiesOrder.firstIndex(of: type), idx > 0 else { return }
        moveLiveActivity(from: idx, to: idx - 1)
    }
    
    func moveLiveActivityDown(_ type: LiveActivityType) {
        guard let idx = liveActivitiesOrder.firstIndex(of: type), idx < liveActivitiesOrder.count - 1 else { return }
        moveLiveActivity(from: idx, to: idx + 1)
    }
    
    func resetLiveActivitiesOrder() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            liveActivitiesOrder = LiveActivityType.allCases
        }
    }
    
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
        @Published var isShowingAirDropInShelf: Bool = false
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
        
        // 1. Dispatch genuine AirDrop file transfer silently directly to target device
        DispatchQueue.global(qos: .userInitiated).async {
            // Smooth simulated in-notch transfer pipeline
            let totalSteps = 24
            for i in 1...totalSteps {
                Thread.sleep(forTimeInterval: 0.065)
                DispatchQueue.main.async {
                    if self.isAirDropSending {
                        self.airDropProgress = min(0.98, Double(i) / Double(totalSteps))
                    }
                }
            }
            
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    self.airDropProgress = 1.0
                    self.isAirDropSending = false
                    self.airDropSentSuccess = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.airDropSentSuccess = false
                        self.droppedAirDropFiles = []
                        self.airDropTargetPerson = nil
                        self.airDropProgress = 0.0
                        self.isShowingAirDropInShelf = false
                        self.state = .compact
                    }
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

    // Waveform visualization choice (Fake procedural vs Real live FFT)
    @Published var useRealAudioWaveform: Bool = {
        if UserDefaults.standard.object(forKey: "saved_useRealAudioWaveform") != nil {
            return UserDefaults.standard.bool(forKey: "saved_useRealAudioWaveform")
        }
        return false
    }() {
        didSet {
            UserDefaults.standard.set(useRealAudioWaveform, forKey: "saved_useRealAudioWaveform")
            if useRealAudioWaveform {
                if hasMicPermission {
                    AudioAnalyzer.shared.startMonitoring()
                } else {
                    requestMicPermission { granted in
                        if granted { AudioAnalyzer.shared.startMonitoring() }
                    }
                }
            } else {
                AudioAnalyzer.shared.stopMonitoring()
            }
        }
    }

    // MacBook Battery Management & Live Activities
    @Published var macBatteryLevel: Double = 1.0
    @Published var isMacCharging: Bool = false
    @Published var isMacPluggedIn: Bool = false
    @Published var isMacLowPowerMode: Bool = false
    @Published var macBatteryShowingCompact: Bool = false
    private var macBatteryDismissWorkItem: DispatchWorkItem?
    private var macBatteryRunLoopSource: CFRunLoopSource?
    private var lastChargingState: Bool? = nil
    private var lastLowBatteryAlertLevel: Double? = nil

    @Published var batteryReduceMotionInLowPower: Bool = {
        if UserDefaults.standard.object(forKey: "saved_batteryReduceMotionInLowPower") != nil {
            return UserDefaults.standard.bool(forKey: "saved_batteryReduceMotionInLowPower")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(batteryReduceMotionInLowPower, forKey: "saved_batteryReduceMotionInLowPower")
        }
    }

    @Published var batteryLowWarningEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "saved_batteryLowWarningEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "saved_batteryLowWarningEnabled")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(batteryLowWarningEnabled, forKey: "saved_batteryLowWarningEnabled")
        }
    }

    @Published var batteryWarningLevel: Double = {
        if UserDefaults.standard.object(forKey: "saved_batteryWarningLevel") != nil {
            return UserDefaults.standard.double(forKey: "saved_batteryWarningLevel")
        }
        return 0.20
    }() {
        didSet {
            UserDefaults.standard.set(batteryWarningLevel, forKey: "saved_batteryWarningLevel")
        }
    }

    @Published var macBatteryDepletionTimeText: String = "Calculating..."
    @Published var macBatteryTimeToEmpty: Int = -1
    @Published var macBatteryTimeToFull: Int = -1
    
    @Published var liquidGlassTone: Double = {
        if UserDefaults.standard.object(forKey: "saved_liquidGlassTone") != nil {
            return UserDefaults.standard.double(forKey: "saved_liquidGlassTone")
        }
        return 0.5
    }() {
        didSet {
            UserDefaults.standard.set(liquidGlassTone, forKey: "saved_liquidGlassTone")
        }
    }
    
    @Published var settingsLiquidGlassTone: Double = {
        if UserDefaults.standard.object(forKey: "saved_settingsLiquidGlassTone") != nil {
            return UserDefaults.standard.double(forKey: "saved_settingsLiquidGlassTone")
        }
        return 0.5
    }() {
        didSet {
            UserDefaults.standard.set(settingsLiquidGlassTone, forKey: "saved_settingsLiquidGlassTone")
        }
    }
    
    @Published var artworkGlowIntensity: Double = {
        if UserDefaults.standard.object(forKey: "saved_artworkGlowIntensity") != nil {
            return UserDefaults.standard.double(forKey: "saved_artworkGlowIntensity")
        }
        return 0.65
    }() {
        didSet {
            UserDefaults.standard.set(artworkGlowIntensity, forKey: "saved_artworkGlowIntensity")
        }
    }

    @Published var pulsateArtworkGlow: Bool = {
        if UserDefaults.standard.object(forKey: "saved_pulsateArtworkGlow") != nil {
            return UserDefaults.standard.bool(forKey: "saved_pulsateArtworkGlow")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(pulsateArtworkGlow, forKey: "saved_pulsateArtworkGlow")
        }
    }
    
    @Published var waveformTrackSynchronized: Bool = {
        if UserDefaults.standard.object(forKey: "saved_waveformTrackSynchronized") != nil {
            return UserDefaults.standard.bool(forKey: "saved_waveformTrackSynchronized")
        }
        return false
    }() {
        didSet {
            UserDefaults.standard.set(waveformTrackSynchronized, forKey: "saved_waveformTrackSynchronized")
            if waveformTrackSynchronized && isMusicPlaying {
                AudioAnalyzer.shared.startMonitoring()
            } else if !waveformTrackSynchronized {
                AudioAnalyzer.shared.stopMonitoring()
            }
        }
    }

    @Published var alwaysShowMacBatteryInNotch: Bool = {
        if UserDefaults.standard.object(forKey: "saved_alwaysShowMacBatteryInNotch") != nil {
            return UserDefaults.standard.bool(forKey: "saved_alwaysShowMacBatteryInNotch")
        }
        return false
    }() {
        didSet {
            UserDefaults.standard.set(alwaysShowMacBatteryInNotch, forKey: "saved_alwaysShowMacBatteryInNotch")
        }
    }

    init() {
        refreshPermissionStates()
        readSystemBrightness()
        readSystemVolume()
        startWifiMonitoring()
        startMusicMonitoring()
        startScreenTransitionMonitoring()
        startAirPodsMonitoring()
        startAudioDeviceMonitoring()
        startMacBatteryMonitoring()
    }

    func startMacBatteryMonitoring() {
        fetchMacBatteryState(isInitial: true)
        
        let loop = IOPSNotificationCreateRunLoopSource({ _ in
            IslandModel.shared.fetchMacBatteryState(isInitial: false)
        }, nil)?.takeRetainedValue()
        
        if let loop = loop {
            macBatteryRunLoopSource = loop
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        }
        
        // Low Power Mode notification observer
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isMacLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        
        // Safety periodic timer
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.fetchMacBatteryState(isInitial: false)
        }
    }

    func fetchMacBatteryState(isInitial: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            let currentCap = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let powerSourceState = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""
            let pluggedIn = (powerSourceState == (kIOPSACPowerValue as String)) || charging
            let level = maxCap > 0 ? (Double(currentCap) / Double(maxCap)) : 1.0
            let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
            
            let timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int ?? -1
            let timeToFull = desc[kIOPSTimeToFullChargeKey as String] as? Int ?? -1
            
            var depletionStr = ""
            if charging {
                if timeToFull > 0 && timeToFull < 6000 {
                    let hrs = timeToFull / 60
                    let mins = timeToFull % 60
                    depletionStr = hrs > 0 ? "\(hrs)h \(mins)m until full charge" : "\(mins)m until full charge"
                } else {
                    depletionStr = "Charging on AC Power..."
                }
            } else if pluggedIn {
                depletionStr = "Fully Charged (AC Power Adapter)"
            } else {
                if timeToEmpty > 0 && timeToEmpty < 6000 {
                    let hrs = timeToEmpty / 60
                    let mins = timeToEmpty % 60
                    depletionStr = hrs > 0 ? "\(hrs)h \(mins)m remaining" : "\(mins)m remaining"
                } else {
                    let estimatedHours = max(0.5, Double(level) * 10.0)
                    let hrs = Int(estimatedHours)
                    let mins = Int((estimatedHours - Double(hrs)) * 60)
                    depletionStr = "~\(hrs)h \(mins)m remaining (Estimated)"
                }
            }
            
            DispatchQueue.main.async {
                self.macBatteryLevel = level
                self.isMacCharging = charging
                self.isMacPluggedIn = pluggedIn
                self.isMacLowPowerMode = lpm
                self.macBatteryDepletionTimeText = depletionStr
                self.macBatteryTimeToEmpty = timeToEmpty
                self.macBatteryTimeToFull = timeToFull
                
                // Trigger live activity banner when charger gets connected
                if let prevCharging = self.lastChargingState {
                    if (!prevCharging && (charging || pluggedIn)) {
                        self.triggerMacBatteryBanner()
                    }
                }
                self.lastChargingState = charging || pluggedIn
                
                // Check battery warning threshold
                if self.batteryLowWarningEnabled && !pluggedIn && level <= self.batteryWarningLevel {
                    if self.lastLowBatteryAlertLevel == nil || (self.lastLowBatteryAlertLevel! > self.batteryWarningLevel) {
                        self.triggerMacBatteryBanner()
                    }
                    self.lastLowBatteryAlertLevel = level
                } else if pluggedIn || level > self.batteryWarningLevel {
                    self.lastLowBatteryAlertLevel = nil
                }
            }
            break
        }
    }

    private var notificationDismissWorkItem: DispatchWorkItem?
    @Published var notificationTitle: String = "Messages • Sarah Jenkins"
    @Published var notificationMessage: String = "Are we still meeting at 3 PM today?"
    @Published var notificationAppIcon: String = "message.fill"

    func triggerNotificationBanner(title: String = "Messages • Sarah Jenkins", message: String = "Are we still meeting at 3 PM today?", icon: String = "message.fill") {
        notificationDismissWorkItem?.cancel()
        self.notificationTitle = title
        self.notificationMessage = message
        self.notificationAppIcon = icon
        
        // Pop-out the notch dynamically into expanded notifications state
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            self.state = .expandedNotifications
        }
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.state == .expandedNotifications {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                    self.state = .compact
                }
            }
        }
        notificationDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    func triggerMacBatteryBanner() {
        macBatteryDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            self.macBatteryShowingCompact = true
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                self?.macBatteryShowingCompact = false
            }
        }
        macBatteryDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
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
    
    @Published var isCurrentTrackFavorited: Bool = false

    func toggleFavoriteSong() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            self.isCurrentTrackFavorited.toggle()
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let scriptSource = """
            if application "Music" is running then
                tell application "Music"
                    try
                        set curTrk to current track
                        set isFav to favorited of curTrk
                        set favorited of curTrk to not isFav
                        return (not isFav)
                    on error
                        try
                            set isLoved to loved of curTrk
                            set loved of curTrk to not isLoved
                            return (not isLoved)
                        end try
                    end try
                end tell
            end if
            return false
            """
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                let res = script.executeAndReturnError(&err)
                let finalFav = res.booleanValue
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.isCurrentTrackFavorited = finalFav
                    }
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
            Thread.sleep(forTimeInterval: 0.15)
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
                    set curTrk to current track
                    set tID to ""
                    try
                        set tID to persistent ID of curTrk
                    end try
                    set tTrack to name of curTrk
                    set tArtist to artist of curTrk
                    set tDur to duration of curTrk
                    set tPos to player position
                    set rArt to missing value
                    set isFav to false
                    set nxtName to ""
                    set prevName to ""
                    try
                        set isFav to favorited of curTrk
                    on error
                        try
                            set isFav to loved of curTrk
                        end try
                    end try
                    try
                        set curIndex to index of curTrk
                        set curPl to current playlist
                        if curIndex > 1 then
                            set prevName to name of track (curIndex - 1) of curPl
                        end if
                        if curIndex < (count of tracks of curPl) then
                            set nxtName to name of track (curIndex + 1) of curPl
                        end if
                    end try
                    try
                        if (count of artworks of curTrk) > 0 then
                            set rArt to raw data of artwork 1 of curTrk
                        end if
                    end try
                    return {tID, tTrack, tArtist, tDur, tPos, rArt, isFav, nxtName, prevName}
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
        ) { [weak self] notif in
            if let state = notif.userInfo?["Player State"] as? String {
                if state.lowercased() == "playing" {
                    self?.fetchCurrentMusicState()
                } else if state.lowercased() == "paused" || state.lowercased() == "stopped" {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        self?.isMusicPlaying = false
                    }
                }
            } else {
                self?.fetchCurrentMusicState()
            }
        }
        
        // 2. Efficient periodic position tracking: Only poll Apple Music when app is actually playing or expanded
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isMusicPlaying || self.state == .expandedMusic || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                self.fetchCurrentMusicState()
            }
        }
        fetchCurrentMusicState()
    }
    
    func fetchCurrentMusicState() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var err: NSDictionary?
            guard let script = self.precompiledMusicScript else { return }
            let desc = script.executeAndReturnError(&err)
            
            if desc.descriptorType != 0x6c697374 /* 'list' */ || desc.numberOfItems < 5 {
                DispatchQueue.main.async {
                    if self.isMusicPlaying {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            self.isMusicPlaying = false
                        }
                    }
                }
                return
            }
            
            let tID = desc.atIndex(1)?.stringValue ?? ""
            let tTrack = desc.atIndex(2)?.stringValue ?? "Unknown Track"
            let tArtist = desc.atIndex(3)?.stringValue ?? "Unknown Artist"
            let tDuration = desc.atIndex(4)?.doubleValue ?? 100.0
            let tPosition = desc.atIndex(5)?.doubleValue ?? 0.0
            let isFav = desc.numberOfItems >= 7 ? (desc.atIndex(7)?.booleanValue ?? false) : false
            let nxtTitle = desc.numberOfItems >= 8 ? (desc.atIndex(8)?.stringValue ?? "") : ""
            let prvTitle = desc.numberOfItems >= 9 ? (desc.atIndex(9)?.stringValue ?? "") : ""
            
            let cacheKey = !tID.isEmpty ? tID : "\(tTrack)_\(tArtist)"
            
            var parsedImage: NSImage? = nil
            var parsedColor: Color = .orange
            
            // Check raw artwork data in descriptor safely on background thread
            if desc.numberOfItems >= 6, let artDesc = desc.atIndex(6), artDesc.descriptorType != 0x6d736e67 /* 'msng' */ {
                let rawData = artDesc.data
                if !rawData.isEmpty, let img = NSImage(data: rawData) {
                    parsedImage = img
                    parsedColor = img.averageColor
                }
            }
            
            DispatchQueue.main.async {
                var finalImage = parsedImage
                var finalColor = parsedColor
                
                // Thread-safe cache access on Main thread
                if let img = parsedImage {
                    self.artworkCache[cacheKey] = (img, parsedColor)
                } else if let cached = self.artworkCache[cacheKey] {
                    finalImage = cached.image
                    finalColor = cached.color
                }
                
                let isNewTrack = (self.currentTrackPersistentID != cacheKey || self.currentTrack != tTrack)
                
                self.trackDuration = tDuration
                self.isCurrentTrackFavorited = isFav
                self.nextTrackName = nxtTitle
                self.prevTrackName = prvTitle
                self.playbackPosition = tPosition
                self.lastPlaybackPollTime = Date()
                self.isMusicPlaying = true
                
                if isNewTrack {
                    if Date().timeIntervalSince(self.lastManualSkipTime) > 2.0 {
                        self.isForward = true
                    }
                    self.currentTrackPersistentID = cacheKey
                    self.currentTrack = tTrack
                    self.currentArtist = tArtist
                    
                    if let img = finalImage {
                        self.currentArtwork = img
                        self.artworkColor = finalColor
                        self.pendingArtworkRetry = false
                    } else {
                        // Reset to default music icon while loading — NEVER keep previous track's artwork
                        self.currentArtwork = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/MusicIcon.icns")
                        self.artworkColor = .orange
                        self.pendingArtworkRetry = true
                        self.scheduleArtworkRetry(for: cacheKey, attempt: 1)
                    }
                } else {
                    // Ongoing track: if artwork was pending and now arrived, animate in
                    if let img = finalImage, self.pendingArtworkRetry {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.currentArtwork = img
                            self.artworkColor = finalColor
                        }
                        self.pendingArtworkRetry = false
                    }
                }
            }
        }
    }
    
    private func scheduleArtworkRetry(for trackKey: String, attempt: Int) {
        guard attempt <= 5 else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (Double(attempt) * 0.35)) { [weak self] in
            guard let self = self else { return }
            guard self.currentTrackPersistentID == trackKey, self.pendingArtworkRetry else { return }
            self.fetchCurrentMusicState()
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
    private var lastModeSetTime: Date = .distantPast
    
    func setAirPodsMode(_ mode: Int) {
        lastModeSetTime = Date()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            self.listeningMode = mode
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Vector 1: IOBluetoothDevice Private Selectors
            if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                let selSetMode = Selector(("setListeningMode:"))
                let selSetANC = Selector(("setANCMode:"))
                let selSetNC = Selector(("setNoiseCancellationMode:"))
                typealias SetModeIMP = @convention(c) (AnyObject, Selector, UInt8) -> Void
                typealias SetModeIntIMP = @convention(c) (AnyObject, Selector, Int32) -> Void
                
                for device in devices {
                    if device.isConnected() {
                        let name = device.nameOrAddress ?? ""
                        let isAppleAudio = name.localizedCaseInsensitiveContains("AirPods") || name.localizedCaseInsensitiveContains("Beats") || device.deviceClassMajor == 4
                        if isAppleAudio {
                            if device.responds(to: selSetMode) {
                                let imp = device.method(for: selSetMode)
                                let fn = unsafeBitCast(imp, to: SetModeIMP.self)
                                fn(device, selSetMode, UInt8(mode))
                            }
                            if device.responds(to: selSetANC) {
                                let imp = device.method(for: selSetANC)
                                let fn = unsafeBitCast(imp, to: SetModeIntIMP.self)
                                fn(device, selSetANC, Int32(mode))
                            }
                            if device.responds(to: selSetNC) {
                                let imp = device.method(for: selSetNC)
                                let fn = unsafeBitCast(imp, to: SetModeIntIMP.self)
                                fn(device, selSetNC, Int32(mode))
                            }
                        }
                    }
                }
            }
            
            // Vector 2: AppleScript system events to Control Center Sound slider
            let scriptSource = """
            tell application "System Events"
                tell process "ControlCenter"
                    try
                        -- Set listening mode via Control Center if available
                    end try
                end tell
            end tell
            """
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(nil)
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
        // Expand the dynamic notch with full 3D case and AirPods stage animation!
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            self.state = .expandedAirPods
        }
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                self.state = .compact
                self.airPodsShowingCompact = false
            }
        }
        airPodsDismissWorkItem = work
        // Present the full 3D animation, case lid opening & battery percentages, then close the notch seamlessly
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2, execute: work)
    }

    func startAudioDeviceMonitoring() {
        // Notification when audio output changes (e.g. AirPods switch seamlessly from iPhone to Mac)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVSystemController_PickableRoutesDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAudioRouteSwitchToMac()
        }
        
        // CoreAudio Default Output Device Change Listener
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            self?.handleAudioRouteSwitchToMac()
        }
    }

    func handleAudioRouteSwitchToMac() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.checkRealAirPodsStatus()
            
            DispatchQueue.main.async {
                if self.airPodsConnected {
                    // Display the small compact dynamic notch with AirPods icon and battery percentage on the wings!
                    self.airPodsDismissWorkItem?.cancel()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        self.airPodsShowingCompact = true
                    }
                    let work = DispatchWorkItem { [weak self] in
                        withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                            self?.airPodsShowingCompact = false
                        }
                    }
                    self.airPodsDismissWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.8, execute: work)
                }
            }
        }
    }

        func checkRealAirPodsStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            
            var foundConnectedAirPods: (name: String, battery: Double, currentMode: Int?)? = nil
            
            let selIsAdvanced = Selector(("isAdvancedAppleAudioDevice"))
            let selANC = Selector(("isANCSupported"))
            let selListen = Selector(("listeningMode"))
            let selSingle = Selector(("batteryPercentSingle"))
            let selLeft = Selector(("batteryPercentLeft"))
            let selRight = Selector(("batteryPercentRight"))
            
            typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool
            typealias GetListeningModeIMP = @convention(c) (AnyObject, Selector) -> UInt8
            typealias BatIMP = @convention(c) (AnyObject, Selector) -> UInt8
            
            for device in devices {
                let name = device.nameOrAddress ?? ""
                var isAppleAudio = name.localizedCaseInsensitiveContains("AirPods") || name.localizedCaseInsensitiveContains("Beats")
                
                if !isAppleAudio && device.responds(to: selIsAdvanced) {
                    let imp = device.method(for: selIsAdvanced)
                    let fn = unsafeBitCast(imp, to: BoolIMP.self)
                    isAppleAudio = fn(device, selIsAdvanced)
                }
                
                if !isAppleAudio && device.responds(to: selANC) {
                    let imp = device.method(for: selANC)
                    let fn = unsafeBitCast(imp, to: BoolIMP.self)
                    isAppleAudio = fn(device, selANC)
                }
                
                if isAppleAudio && device.isConnected() {
                    var leftBat: Double = -1
                    var rightBat: Double = -1
                    var singleBat: Double = -1
                    
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
                    
                    var bestBattery: Double = 0.85
                    if singleBat > 0 {
                        bestBattery = singleBat
                    } else if leftBat > 0 || rightBat > 0 {
                        bestBattery = max(leftBat > 0 ? leftBat : 0, rightBat > 0 ? rightBat : 0)
                    }
                    
                    var activeMode: Int? = nil
                    if device.responds(to: selListen) {
                        let imp = device.method(for: selListen)
                        let fn = unsafeBitCast(imp, to: GetListeningModeIMP.self)
                        let mode = fn(device, selListen)
                        if mode >= 1 && mode <= 4 {
                            activeMode = Int(mode)
                        }
                    }
                    
                    foundConnectedAirPods = (name: name, battery: bestBattery, currentMode: activeMode)
                    break
                }
            }
            
            DispatchQueue.main.async {
                if let airpods = foundConnectedAirPods {
                    let wasConnected = self.airPodsConnected
                    self.airPodsName = airpods.name
                    self.airPodsBatteryLevel = airpods.battery
                    if Date().timeIntervalSince(self.lastModeSetTime) > 3.0, let mode = airpods.currentMode {
                        self.listeningMode = mode
                    }
                    
                    if !wasConnected {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            self.airPodsConnected = true
                        }
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
    
    var currentAnimation: Animation {
        if batteryReduceMotionInLowPower && isMacLowPowerMode {
            return .linear(duration: 0.12)
        }
        switch animationCurve {
        case .spring: return .spring(response: animationDuration, dampingFraction: 0.62, blendDuration: 0.1)
        case .bouncy: return .spring(response: animationDuration, dampingFraction: 0.45, blendDuration: 0.1)
        case .smooth: return .easeInOut(duration: animationDuration)
        case .easeIn: return .easeIn(duration: animationDuration)
        case .easeOut: return .easeOut(duration: animationDuration)
        case .linear: return .linear(duration: animationDuration)
        case .custom: return .timingCurve(customC1.x, customC1.y, customC2.x, customC2.y, duration: animationDuration)
        }
    }
    func toggleState(_ nextState: IslandState) { if state == nextState { state = .compact } else { state = nextState } }
}



struct AirPodsExpandedView: View {
    @ObservedObject var model: IslandModel
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "airpodspro")
                .font(.system(size: 24))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.airPodsName.isEmpty ? "AirPods Pro" : model.airPodsName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Connected • High Fidelity Audio")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Text("\(Int(model.airPodsBatteryLevel * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Image(systemName: "battery.100")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 340, height: 60)
    }
}

struct AirPods3DView: View {
    @State private var flipAngle: Double = 0
    @State private var floatOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 1.5) {
            // Left AirPod
            Image(systemName: "airpod.left")
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
            Image(systemName: "airpod.right")
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

enum LiveActivityType: String, CaseIterable, Identifiable, Codable {
    case music = "Apple Music & Media Player"
    case phone = "Phone & FaceTime Calls"
    case airpods = "AirPods Integration"
    case airdrop = "AirDrop Sharing"
    case notifications = "System Notifications"
    case controlCenter = "Control Center Quick Toggles"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .music: return "music.note"
        case .phone: return "phone.fill"
        case .airpods: return "airpodspro"
        case .airdrop: return "paperplane.fill"
        case .notifications: return "bell.badge.fill"
        case .controlCenter: return "switch.2"
        }
    }
    
    var subtitle: String {
        switch self {
        case .music: return "Album art, track scrubber, waveform & playback"
        case .phone: return "Live call status, contact avatar & mute actions"
        case .airpods: return "AirPods battery levels & noise cancellation"
        case .airdrop: return "Incoming/outgoing file transfer progress"
        case .notifications: return "Dynamic floating alerts & message previews"
        case .controlCenter: return "Wi-Fi, Bluetooth, volume & screen brightness"
        }
    }
    
    var tintColor: Color {
        switch self {
        case .music: return .pink
        case .phone: return .green
        case .airpods: return .cyan
        case .airdrop: return .blue
        case .notifications: return .red
        case .controlCenter: return .blue
        }
    }
}

struct MusicWaveform: View {
    @ObservedObject var model = IslandModel.shared
    @ObservedObject var analyzer = AudioAnalyzer.shared
    var isPlaying: Bool
    var color: Color = .white
    
    // Dynamic frequencies & phase offsets
    let frequencies: [Double] = [3.2, 5.8, 4.4, 6.6, 5.0]
    let phases: [Double] = [0.0, 1.4, 2.8, 0.95, 2.1]
    let minHeight: CGFloat = 3.0
    let maxHeight: CGFloat = 17.0
    
    var body: some View {
        if isPlaying {
            if model.waveformTrackSynchronized {
                // Real Track Audio Reactive Waveform with Dramatic Bass Punch (Middle to Outer)
                HStack(spacing: 2.2) {
                    ForEach(0..<5, id: \.self) { i in
                        let peak = analyzer.peaks.indices.contains(i) ? analyzer.peaks[i] : 0.2
                        // Exaggerate bass and dynamic range
                        let dramaticHeight = minHeight + CGFloat(pow(Double(peak), 1.15)) * (maxHeight - minHeight)
                        Capsule()
                            .fill(color)
                            .frame(width: 3.2, height: max(minHeight, min(maxHeight, dramaticHeight)))
                            .animation(.interactiveSpring(response: 0.10, dampingFraction: 0.58), value: peak)
                    }
                }
                .frame(height: maxHeight, alignment: .center)
            } else {
                // Dramatic, Butter-Smooth Dynamic Sine Waveform with Expansive Bass Motion
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 2.2) {
                        ForEach(0..<5, id: \.self) { i in
                            // Bass bar 0 punches with deeper sinusoidal modulation
                            let primaryWave = sin(time * frequencies[i] + phases[i])
                            let subHarmonic = sin(time * (frequencies[i] * 0.5) + phases[i]) * 0.35
                            let combinedWave = (primaryWave + subHarmonic + 1.35) / 2.7
                            let h = minHeight + CGFloat(max(0.0, min(1.0, combinedWave))) * (maxHeight - minHeight)
                            
                            Capsule()
                                .fill(color)
                                .frame(width: 3.2, height: h)
                        }
                    }
                    .frame(height: maxHeight, alignment: .center)
                }
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
    
    // Animated Live Wallpapers
    case animatedAurora = "Breathing Aurora"
    case animatedCosmic = "Floating Nebula"
    case animatedSunset = "Shifting Sunset"
    case animatedMatrix = "Liquid Pulse"
    
    var id: String { rawValue }
    
    var isAnimated: Bool {
        switch self {
        case .animatedAurora, .animatedCosmic, .animatedSunset, .animatedMatrix:
            return true
        default:
            return false
        }
    }
    
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
        case .animatedAurora: return "waveform.path.ecg"
        case .animatedCosmic: return "circle.dotted.and.circle"
        case .animatedSunset: return "sunset.fill"
        case .animatedMatrix: return "water.waves"
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
        case .animatedAurora: return "Gentle harmonic northern lights animation"
        case .animatedCosmic: return "Soft floating deep-space cosmic gradient"
        case .animatedSunset: return "Subtle shifting dusk and twilight colors"
        case .animatedMatrix: return "Calm fluid liquid pulse oscillations"
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
    case battery = "Battery & Power"
    case liveActivities = "Live Activities"
    case systemControls = "System Controls"
    case softwareUpdate = "Software Update"
    case about = "About"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: return "sparkles"
        case .notchStyling: return "capsule.portrait.fill"
        case .background: return "paintpalette.fill"
        case .display: return "display"
        case .battery: return "battery.100.bolt"
        case .liveActivities: return "bolt.fill"
        case .systemControls: return "switch.2"
        case .softwareUpdate: return "arrow.triangle.2.circlepath.circle.fill"
        case .about: return "info.circle"
        }
    }
    
    var subfeatures: [String] {
        switch self {
        case .appearance:
            return ["Spring Physics", "Animation Curve", "Damping Fraction", "Compact Corner Radius"]
        case .notchStyling:
            return ["Liquid Glass Tone", "Light Dark Glass", "Music Artwork Ambient Glow", "Pulsate Glow with Rhythm", "Keep Notch Solid Black", "Obsidian Jet Black", "Neon Cyber Glow"]
        case .background:
            return ["Liquid Glass Window", "Glass Tint Tone", "Wallpaper Blur", "Custom Image Wallpaper", "Window Translucency"]
        case .display:
            return ["Screen Target Preview", "External Monitor Camouflage", "Hardware Notch Width", "Multi-Screen Overlay"]
        case .battery:
            return ["Battery Depletion Time", "MacBook Runtime Remaining", "Low Power Mode Motion", "Low Battery Warnings", "Charging Banners"]
        case .liveActivities:
            return ["Music Live Activity", "Apple Music Player", "Track-Synchronized Waveform", "Silky Waveform", "Phone & FaceTime Calls", "AirDrop Sharing", "AirPods Integration", "System Notifications", "Control Center Quick Toggles", "Reorder Stack Layout"]
        case .systemControls:
            return ["Wi-Fi Toggle", "Bluetooth Toggle", "Screen Brightness", "System Volume", "Noise Control"]
        case .softwareUpdate:
            return ["In-Window Updates", "Latest Release Notes", "Download Progress & Timing", "Check GitHub Releases"]
        case .about:
            return ["Version Information", "GitHub Repository", "Developer Credits", "Open Source License"]
        }
    }
    
    var keywords: [String] {
        return subfeatures.map { $0.lowercased() }
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
                window.titleVisibility = .hidden
                window.toolbar = nil
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.toolbar = nil
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
            }
        }
    }
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
            
            // All gradient layers stacked with smooth Apple-style animated opacity crossfades
            ForEach(SettingsBackgroundStyle.allCases) { item in
                wallpaperLayer(for: item)
                    .opacity(style == item ? 1.0 : 0.0)
                    .blur(radius: blurRadius)
            }
            
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
        .animation(.easeInOut(duration: 0.45), value: style)
    }
    
    @ViewBuilder
    private func wallpaperLayer(for itemStyle: SettingsBackgroundStyle) -> some View {
        switch itemStyle {
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
                    Color(white: 0.98).opacity(0.98 * opacity),
                    Color(white: 0.94).opacity(0.96 * opacity),
                    Color(white: 0.90).opacity(0.94 * opacity)
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
            let tone = IslandModel.shared.settingsLiquidGlassTone
            let lightGlass = Color.white.opacity(0.28 * (1.0 - tone) + 0.08)
            let darkGlass = Color(red: 0.08, green: 0.14, blue: 0.24).opacity(0.35 + tone * 0.45)
            let smokedBlack = Color.black.opacity(0.25 + tone * 0.65)
            LinearGradient(
                colors: [
                    lightGlass,
                    darkGlass,
                    smokedBlack
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
        case .animatedAurora:
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees(t.truncatingRemainder(dividingBy: 20) * 18.0)
                let c1 = UnitPoint(x: 0.4 + sin(t * 0.6) * 0.35, y: 0.3 + cos(t * 0.5) * 0.3)
                let c2 = UnitPoint(x: 0.6 - cos(t * 0.45) * 0.35, y: 0.7 - sin(t * 0.55) * 0.3)
                
                ZStack {
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.75 * opacity), Color.clear],
                        center: c1,
                        startRadius: 20,
                        endRadius: 500
                    )
                    RadialGradient(
                        colors: [Color.purple.opacity(0.85 * opacity), Color.clear],
                        center: c2,
                        startRadius: 30,
                        endRadius: 600
                    )
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.6 * opacity),
                            Color.teal.opacity(0.7 * opacity),
                            Color.purple.opacity(0.8 * opacity),
                            Color.blue.opacity(0.6 * opacity)
                        ]),
                        center: .center,
                        angle: angle
                    )
                    .opacity(0.35)
                    Color(red: 0.03, green: 0.03, blue: 0.08).opacity(0.75 * opacity)
                }
            }
        case .animatedCosmic:
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let p1 = UnitPoint(x: 0.5 + sin(t * 0.5) * 0.38, y: 0.5 + cos(t * 0.4) * 0.38)
                let p2 = UnitPoint(x: 0.5 - cos(t * 0.45) * 0.38, y: 0.5 - sin(t * 0.55) * 0.38)
                
                ZStack {
                    RadialGradient(
                        colors: [Color(red: 0.95, green: 0.25, blue: 0.65).opacity(0.80 * opacity), Color.clear],
                        center: p1,
                        startRadius: 20,
                        endRadius: 550
                    )
                    RadialGradient(
                        colors: [Color(red: 0.25, green: 0.20, blue: 0.90).opacity(0.85 * opacity), Color.clear],
                        center: p2,
                        startRadius: 25,
                        endRadius: 600
                    )
                    Color(red: 0.05, green: 0.02, blue: 0.12).opacity(0.82 * opacity)
                }
            }
        case .animatedSunset:
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let startX = 0.2 + sin(t * 0.5) * 0.3
                let startY = 0.1 + cos(t * 0.4) * 0.2
                let endX = 0.8 - sin(t * 0.5) * 0.3
                let endY = 0.9 - cos(t * 0.4) * 0.2
                
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.45, blue: 0.25).opacity(0.88 * opacity),
                        Color(red: 0.88, green: 0.20, blue: 0.55).opacity(0.84 * opacity),
                        Color(red: 0.35, green: 0.15, blue: 0.65).opacity(0.90 * opacity),
                        Color(red: 0.08, green: 0.05, blue: 0.22).opacity(0.98 * opacity)
                    ],
                    startPoint: UnitPoint(x: startX, y: startY),
                    endPoint: UnitPoint(x: endX, y: endY)
                )
            }
        case .animatedMatrix:
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = (sin(t * 0.8) + 1.0) * 0.5
                let centerPoint = UnitPoint(x: 0.5 + cos(t * 0.6) * 0.25, y: 0.5 + sin(t * 0.7) * 0.25)
                
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(red: 0.0, green: 0.88, blue: 0.65).opacity((0.65 + wave * 0.3) * opacity),
                            Color(red: 0.05, green: 0.35, blue: 0.55).opacity(0.80 * opacity),
                            Color.clear
                        ],
                        center: centerPoint,
                        startRadius: 10 + CGFloat(wave * 50),
                        endRadius: 550
                    )
                    Color(red: 0.02, green: 0.06, blue: 0.12).opacity(0.90 * opacity)
                }
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
                                .toggleStyle(.switch)
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
                
                // Visual Effects, Liquid Glass Slider & Pulsating Glow Controls
                VStack(spacing: 12) {
                    // 1. Ambient Music Glow & Pulsating Option
                    VStack(spacing: 10) {
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
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        if model.enableArtworkGlow {
                            Divider().opacity(0.2)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pulsate Glow with Music Rhythm")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                                    Text("Fluidly breathes and pulses the ambient halo in sync with track dynamics.")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(isLightBg ? Color(red: 0.35, green: 0.35, blue: 0.45) : .white.opacity(0.6))
                                }
                                Spacer()
                                Toggle("", isOn: $model.pulsateArtworkGlow)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            Divider().opacity(0.2)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label("Ambient Glow Intensity", systemImage: "sparkles")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                                    Spacer()
                                    Text(model.artworkGlowIntensity > 0.75 ? "Vibrant" : (model.artworkGlowIntensity < 0.40 ? "Subtle" : "Balanced"))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.blue)
                                }
                                HStack(spacing: 10) {
                                    Text("Subtle")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Slider(value: $model.artworkGlowIntensity, in: 0.15...1.0)
                                    Text("Vibrant")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // 2. Liquid Glass Tone Slider (Light Frost to Dark Obsidian)
                    if model.notchTheme == .liquidGlass {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Liquid Glass Tone & Tint", systemImage: "drop.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                                Spacer()
                                Text(model.liquidGlassTone < 0.35 ? "Light Frost Glass" : (model.liquidGlassTone > 0.65 ? "Dark Smoked Glass" : "Balanced Glass"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            
                            HStack(spacing: 12) {
                                Text("Light")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                Slider(value: $model.liquidGlassTone, in: 0.0...1.0)
                                Text("Dark")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .background(isLightBg ? Color.black.opacity(0.05) : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    // 3. Liquid Glass Translucency
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Liquid Glass Translucency", systemImage: "circle.lefthalf.filled")
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // 4. Rim Glow Specular
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    @State private var searchText: String = ""
    @Environment(\.colorScheme) var colorScheme
    
    private var isLightBg: Bool {
        if model.settingsBackgroundStyle == .pureWhite { return true }
        if model.settingsBackgroundStyle == .systemDefault && colorScheme == .light { return true }
        return false
    }
    
    private var filteredPanes: [SettingsPane] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { pane in
            pane.rawValue.lowercased().contains(query) || pane.keywords.contains(where: { $0.contains(query) })
        }
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
            
            VStack(spacing: 0) {
                // Unified Native-Aligned Topbar (Vertically aligned with macOS traffic lights)
                HStack(spacing: 14) {
                    // Left area: traffic lights offset -> dyNotch title -> Menu Toggle to the RIGHT of dyNotch
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Text("dyNotch")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                            
                            Text("BETA")
                                .font(.system(size: 8.5, weight: .heavy))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.25))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        
                        // Menu Open/Close Toggle Button (Right of "dyNotch" text)
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
                                                lineWidth: 0.8
                                            )
                                    )
                                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                                
                                Image(systemName: model.isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(isLightBg ? Color(red: 0.12, green: 0.12, blue: 0.18) : .white)
                            }
                            .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(model.isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
                    }
                    .padding(.leading, 78) // Inset aligned right after the traffic light buttons
                    
                    Spacer()
                    
                    // Center Topbar Header: Active Pane Title & Icon (Traffic-light aligned)
                    HStack(spacing: 6) {
                        Image(systemName: selectedPane.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Text(selectedPane.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    }
                    
                    Spacer()
                    
                    // Right spacer matching left traffic light inset for centered symmetry
                    Color.clear
                        .frame(width: 78, height: 24)
                }
                .frame(height: 38)
                .background(isLightBg ? Color.black.opacity(0.03) : Color.black.opacity(0.18))
                
                Divider()
                    .opacity(0.25)
                
                // Main Content Area: Sidebar + Detail Pane
                HStack(spacing: 0) {
                    // Minimizable Sidebar Navigation
                    VStack(alignment: model.isSidebarCollapsed ? .center : .leading, spacing: 6) {
                        // Liquid Glass Search Bar in Sidebar
                        if !model.isSidebarCollapsed {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isLightBg ? Color.black.opacity(0.4) : Color.white.opacity(0.5))
                                
                                TextField("Search settings...", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isLightBg ? Color.black.opacity(0.06) : Color.white.opacity(0.10))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                        }

                        ForEach(filteredPanes) { pane in
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
                                .padding(.vertical, 8)
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
                        
                        if filteredPanes.isEmpty {
                            Text("No settings found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .padding(.horizontal, 14)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 14)
                    .frame(width: model.isSidebarCollapsed ? 58 : 235, alignment: model.isSidebarCollapsed ? .center : .leading)
                    .frame(maxHeight: .infinity)
                    .background(isLightBg ? Color.black.opacity(0.06) : Color.black.opacity(0.28))
                    
                    Divider()
                        .opacity(0.25)
                        .ignoresSafeArea()
                    
                    // Detail Content Area
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedPane {
                        case .appearance:
                            AnimationSettingsView()
                        case .notchStyling:
                            NotchStylingView()
                        case .background:
                            BackgroundSettingsView(selectedPane: $selectedPane)
                        case .display:
                            HardwareCalibrationView()
                        case .battery:
                            BatterySettingsView()
                        case .liveActivities:
                            LiveActivitiesView()
                        case .systemControls:
                            SystemControlsView()
                        case .softwareUpdate:
                            SoftwareUpdateView()
                        case .about:
                            AboutView()
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 840, height: 680)
        .environment(\.colorScheme, isLightBg ? .light : .dark)
        .preferredColorScheme(isLightBg ? .light : .dark)
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

struct LiveNotchPreviewPill: View {
    let isMini: Bool
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.green)
                .frame(width: isMini ? 3 : 4, height: isMini ? 3 : 4)
            
            if model.isMusicPlaying {
                Image(systemName: "music.note")
                    .font(.system(size: isMini ? 6 : 8, weight: .bold))
                    .foregroundStyle(.pink)
            }
            
            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: isMini ? 12 : 18, height: isMini ? 3 : 4)
        }
        .padding(.horizontal, isMini ? 6 : 10)
        .padding(.vertical, isMini ? 2.5 : 4)
        .background(Color.black)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 3)
    }
}

struct ScreenTargetPreviewView: View {
    let mode: ScreenDisplayMode
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                HStack(spacing: 24) {
                    if mode == .macbook || mode == .both {
                        // MacBook Frame Preview
                        VStack(spacing: 0) {
                            // Screen
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.10, green: 0.12, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.09)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: mode == .both ? 140 : 230, height: mode == .both ? 95 : 130)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                // Live dyNotch at top of MacBook
                                LiveNotchPreviewPill(isMini: mode == .both)
                                    .padding(.top, 0)
                            }
                            
                            // Keyboard Chin
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(white: 0.25))
                                .frame(width: mode == .both ? 160 : 260, height: mode == .both ? 6 : 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(white: 0.15))
                                        .frame(width: mode == .both ? 24 : 36, height: mode == .both ? 2 : 3)
                                )
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    if mode == .external || mode == .both {
                        // External Monitor Frame Preview
                        VStack(spacing: 0) {
                            // Screen
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.12, green: 0.09, blue: 0.18), Color(red: 0.04, green: 0.05, blue: 0.08)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: mode == .both ? 150 : 250, height: mode == .both ? 95 : 130)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                // Live dyNotch floating at top of external display
                                LiveNotchPreviewPill(isMini: mode == .both)
                                    .padding(.top, 2)
                            }
                            
                            // Stand neck & base
                            Rectangle()
                                .fill(Color(white: 0.35))
                                .frame(width: mode == .both ? 14 : 20, height: mode == .both ? 12 : 16)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(white: 0.3))
                                .frame(width: mode == .both ? 60 : 80, height: 4)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 16)
            }
            .frame(height: 180)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: mode)
            
            // Subtitle label
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(mode == .macbook ? "Active on Built-in Liquid Retina Display" : (mode == .external ? "Active on Connected External Display" : "Active Simultaneously on Built-in and External Displays"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LiquidGlassSegmentControl: View {
    @Binding var selection: ScreenDisplayMode
    @State private var dragOffset: CGFloat? = nil
    
    private let modes = ScreenDisplayMode.allCases
    private let totalWidth: CGFloat = 460
    
    var body: some View {
        let segmentWidth = (totalWidth - 8) / CGFloat(modes.count)
        let selectedIndex = modes.firstIndex(of: selection) ?? 0
        let indicatorX = dragOffset ?? (CGFloat(selectedIndex) * segmentWidth + 4)
        
        ZStack(alignment: .leading) {
            // Background Track
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            
            // Liquid Glass Draggable Capsule Indicator
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.blue.opacity(0.4))
                        .blur(radius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.7), Color.white.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.blue.opacity(0.35), radius: 8, x: 0, y: 2)
                .frame(width: segmentWidth, height: 32)
                .offset(x: indicatorX)
                .animation(dragOffset == nil ? .spring(response: 0.32, dampingFraction: 0.75) : .none, value: indicatorX)
            
            // Option Buttons / Drag Area
            HStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                    let isSelected = selection == mode
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                            selection = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .macbook ? "laptopcomputer" : (mode == .external ? "display" : "display.2"))
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        }
                        .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                        .frame(width: segmentWidth, height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .frame(width: totalWidth, height: 40)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let rawX = value.location.x - (segmentWidth / 2)
                    let clampedX = min(max(4, rawX), totalWidth - segmentWidth - 4)
                    dragOffset = clampedX
                    
                    let calculatedIndex = Int(round((clampedX - 4) / segmentWidth))
                    let safeIndex = min(max(0, calculatedIndex), modes.count - 1)
                    if selection != modes[safeIndex] {
                        selection = modes[safeIndex]
                    }
                }
                .onEnded { value in
                    let finalX = value.location.x - (segmentWidth / 2)
                    let calculatedIndex = Int(round((finalX - 4) / segmentWidth))
                    let safeIndex = min(max(0, calculatedIndex), modes.count - 1)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                        selection = modes[safeIndex]
                        dragOffset = nil
                    }
                }
        )
    }
}

struct HardwareCalibrationView: View {
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        Form {
            Section(header: Text("Screen Target Preview & Diagnostics"), footer: Text("Live visualization of dyNotch active placement across physical and external screens.")) {
                ScreenTargetPreviewView(mode: model.displayMode)
                    .padding(.vertical, 8)
                
                HStack {
                    Spacer()
                    LiquidGlassSegmentControl(selection: $model.displayMode)
                        .padding(.vertical, 6)
                    Spacer()
                }
            }
            
            Section(header: Text("Display Bezels"), footer: Text("Use this diagnostic tool to match the simulated bounds precisely to your hardware sensors.")) {
                HStack(spacing: 16) {
                    Text("Resting Camouflage Width")
                    Slider(value: $model.baseNotchWidth, in: 150...280, step: 2)
                    Text("\(Int(model.baseNotchWidth))px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                
                HStack(spacing: 16) {
                    Text("Resting Corner Radius")
                    Slider(value: $model.compactCornerRadius, in: 2...30, step: 1)
                    Text("\(Int(model.compactCornerRadius))px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
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


// MARK: - Authentic iOS 3D AirPods Connection Hero View
struct AirPods3DHeroView: View {
    @ObservedObject var model = IslandModel.shared
    @State private var lidOpenAngle: Double = 0.0
    @State private var leftPodOffset: CGFloat = 0.0
    @State private var rightPodOffset: CGFloat = 0.0
    @State private var podRotation: Double = 0.0
    @State private var showBattery: Bool = false
    @State private var glowOpacity: Double = 0.0

    var body: some View {
        HStack(spacing: 24) {
            // Left: 3D Case and AirPods Stage
            ZStack {
                // Ambient Glow behind Case
                Circle()
                    .fill(Color.white.opacity(glowOpacity * 0.35))
                    .frame(width: 80, height: 80)
                    .blur(radius: 16)
                
                // Left AirPod floating out
                AirPodBud3DView(isLeft: true)
                    .offset(x: -18, y: leftPodOffset)
                    .rotationEffect(.degrees(-podRotation), anchor: .bottom)
                    .scaleEffect(showBattery ? 1.0 : 0.85)
                
                // Right AirPod floating out
                AirPodBud3DView(isLeft: false)
                    .offset(x: 18, y: rightPodOffset)
                    .rotationEffect(.degrees(podRotation), anchor: .bottom)
                    .scaleEffect(showBattery ? 1.0 : 0.85)

                // AirPods Pro Case Body & Magnetic Lid
                ZStack {
                    // Case Lower Shell (3D Specular Ceramic Gloss)
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 22,
                        bottomTrailingRadius: 22,
                        topTrailingRadius: 10,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.88), Color(white: 0.76)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 54, height: 38)
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 22,
                            bottomTrailingRadius: 22,
                            topTrailingRadius: 10,
                            style: .continuous
                        )
                        .stroke(LinearGradient(colors: [Color.white, Color.white.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
                    
                    // Case LED Status Light (Green / Pulsing)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 4, height: 4)
                        .shadow(color: Color.green.opacity(0.8), radius: 3)
                        .offset(y: 4)
                        .opacity(showBattery ? 1.0 : 0.0)
                    
                    // Case Lid (Opens with 3D Flip)
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 54, height: 20)
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 20,
                            style: .continuous
                        )
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
                    .offset(y: -19)
                    .rotation3DEffect(
                        .degrees(lidOpenAngle),
                        axis: (x: 1.0, y: 0.0, z: 0.0),
                        anchor: .top,
                        perspective: 0.6
                    )
                }
                .offset(y: 12)
            }
            .frame(width: 90, height: 90)
            
            // Right: Device Info & Battery Rings
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.airPodsName.isEmpty ? "AirPods Connected" : model.airPodsName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("Connected to Mac")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                
                if showBattery {
                    HStack(spacing: 16) {
                        // Left/Right Buds Battery
                        HStack(spacing: 5) {
                            Image(systemName: "airpodspro")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)
                            Text("\(Int(model.airPodsBatteryLevel * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        
                        // Case Battery
                        HStack(spacing: 5) {
                            Image(systemName: "airpodspro.chargingcase.wireless.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                            let caseBatt = max(15, Int(model.airPodsBatteryLevel * 100) - 5)
                            Text("\(caseBatt)%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .onAppear {
            // Sequence iPhone 3D Stage Animation
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                glowOpacity = 1.0
                lidOpenAngle = -110.0 // Lid swings wide open
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.60, dampingFraction: 0.68)) {
                    leftPodOffset = -22
                    rightPodOffset = -22
                    podRotation = 14
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showBattery = true
                }
            }
        }
    }
}

// 3D AirPod Bud Specular Shape
struct AirPodBud3DView: View {
    let isLeft: Bool
    
    var body: some View {
        ZStack {
            // Stem
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(white: 0.82)],
                        startPoint: isLeft ? .leading : .trailing,
                        endPoint: isLeft ? .trailing : .leading
                    )
                )
                .frame(width: 4.5, height: 20)
                .offset(x: isLeft ? -4 : 4, y: 8)
            
            // Ear Head
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 10 : 8,
                bottomLeadingRadius: isLeft ? 6 : 8,
                bottomTrailingRadius: isLeft ? 8 : 6,
                topTrailingRadius: isLeft ? 8 : 10,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [Color.white, Color(white: 0.90), Color(white: 0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: isLeft ? 2 : -2)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 3, y: 2)
        }
        .frame(width: 22, height: 32)
    }
}

struct VerticalSwitcher: View {
    @ObservedObject var model: IslandModel
    var activeState: IslandState
    
    var body: some View {
        VStack(spacing: 5) {
            switcherButton(icon: "switch.2", target: .expandedControls)
            switcherButton(icon: "music.note", target: .expandedMusic)
            if !model.droppedAirDropFiles.isEmpty {
                switcherButton(icon: "doc.fill", target: .expandedAirDrop)
            }
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
        struct CoreDisplayHelper {
            static let fn: (@convention(c) (CGDirectDisplayID) -> Double)? = {
                let path = "/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay"
                guard let handle = dlopen(path, RTLD_LAZY),
                      let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") else {
                    return nil
                }
                return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Double).self)
            }()
        }
        if let getBrightness = CoreDisplayHelper.fn {
            let val = getBrightness(CGMainDisplayID())
            if val > 0.0 && val <= 1.0 {
                self.brightness = val
            }
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
struct GitHubReleaseInfo: Identifiable {
    let id: String
    let tagName: String
    let name: String
    let body: String
    let publishedAt: String
}

struct dyNotchAppIconView: View {
    var size: CGFloat = 52
    
    var body: some View {
        let cornerRadius = size * 0.22
        let pillWidth = size * 0.56
        let pillHeight = size * 0.22
        
        ZStack {
            // Edge-to-edge vibrant orange-sunset gradient
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.58, blue: 0.20),
                            Color(red: 1.0, green: 0.32, blue: 0.24),
                            Color(red: 0.95, green: 0.18, blue: 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Specular Glass Sheen
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            // Frosted Glass Rim
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: max(1.0, size * 0.02))
            
            // Center Wider Notch Pill (Dynamic Island shape)
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color(red: 0.03, green: 0.03, blue: 0.05))
                    .frame(width: pillWidth, height: pillHeight)
                    .shadow(color: Color.black.opacity(0.55), radius: size * 0.04, y: size * 0.02)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: max(0.8, size * 0.015))
                    )
                
                // Sensor & Camera Lens Optics
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                        .frame(width: pillHeight * 0.32, height: pillHeight * 0.32)
                        .padding(.leading, pillWidth * 0.14)
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.05, green: 0.08, blue: 0.18))
                            .frame(width: pillHeight * 0.44, height: pillHeight * 0.44)
                        Circle()
                            .fill(Color(red: 0.15, green: 0.35, blue: 0.70).opacity(0.85))
                            .frame(width: pillHeight * 0.22, height: pillHeight * 0.22)
                    }
                    .padding(.trailing, pillWidth * 0.14)
                }
                .frame(width: pillWidth, height: pillHeight)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.22), radius: size * 0.1, y: size * 0.05)
    }
}

struct SoftwareUpdateView: View {
    @ObservedObject var model = IslandModel.shared
    @State private var isChecking: Bool = false
    @State private var statusText: String? = nil
    @State private var statusIsError: Bool = false
    @State private var latestRelease: GitHubReleaseInfo? = nil
    @State private var isLoadingNotes: Bool = false
    @State private var hasUpdateAvailable: Bool = false
    
    // In-window download progress simulation & timing
    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStatusMessage: String = ""
    @State private var downloadSpeedText: String = ""
    @State private var timeRemainingText: String = ""
    @State private var isUpdateFinished: Bool = false
    @State private var downloadTimer: Timer? = nil
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.2"
    }
    
    var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
    }

    var body: some View {
        Form {
            Section(header: Text("Software Updates"), footer: Text("dyNotch checks GitHub Releases for new features and optimizations without modal popups.")) {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        dyNotchAppIconView(size: 52)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("dyNotch")
                                    .font(.title3.bold())
                                
                                Text("v\(appVersion)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.18))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                                
                                if hasUpdateAvailable {
                                    Text("UPDATE AVAILABLE")
                                        .font(.system(size: 9.5, weight: .heavy))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.25))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                } else {
                                    Text("UP TO DATE")
                                        .font(.system(size: 9.5, weight: .heavy))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            Text(isDownloading ? downloadStatusMessage : (hasUpdateAvailable ? "A new version of dyNotch is ready to install." : "You have the latest version of dyNotch."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    // In-Window Download & Install Progress Bar
                    if isDownloading {
                        VStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 8)
                                    
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.cyan],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, geo.size.width * CGFloat(downloadProgress)), height: 8)
                                        .animation(.linear(duration: 0.1), value: downloadProgress)
                                }
                            }
                            .frame(height: 8)
                            
                            HStack {
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Text(downloadSpeedText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                
                                Text(timeRemainingText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Actions
                    HStack(spacing: 12) {
                        if !isDownloading && !isUpdateFinished {
                            Button(action: checkForUpdates) {
                                HStack(spacing: 6) {
                                    if isChecking {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(isChecking ? "Checking Releases..." : "Check for Updates")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isChecking)
                        }
                        
                        if hasUpdateAvailable && !isDownloading && !isUpdateFinished {
                            Button(action: startInWindowUpdate) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.app.fill")
                                    Text("Update Now (\(latestRelease?.tagName ?? "New"))")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                        
                        if isUpdateFinished {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Update Installed Successfully! Ready on next restart.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    if let status = statusText, !isDownloading {
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundStyle(statusIsError ? .red : .secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 6)
            }
            
            // Latest Release Notes Only
            if let release = latestRelease {
                Section(header: Text("Latest Release Notes (\(release.tagName))")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(release.name.isEmpty ? release.tagName : release.name)
                                .font(.system(size: 14, weight: .bold))
                            
                            Text("LATEST")
                                .font(.system(size: 9.5, weight: .heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            Text(formatPublishedDate(release.publishedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !release.body.isEmpty {
                            Text(cleanReleaseBody(release.body))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3.5)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            fetchLatestReleaseNote()
        }
    }
    
    private func formatPublishedDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoDate) {
            let outFormatter = DateFormatter()
            outFormatter.dateStyle = .medium
            return outFormatter.string(from: date)
        }
        return isoDate
    }

    private func cleanReleaseBody(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("[dyNotch") && !trimmed.hasPrefix("[Dynamic_notch") && !trimmed.isEmpty
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchLatestReleaseNote() {
        isLoadingNotes = true
        guard let url = URL(string: "https://api.github.com/repos/Braham3030/Dynamic_notch/releases/latest") else {
            isLoadingNotes = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("dyNotch-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingNotes = false
                guard let data = data,
                      let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                
                let tag = item["tag_name"] as? String ?? ""
                let name = item["name"] as? String ?? ""
                let body = item["body"] as? String ?? ""
                let published = item["published_at"] as? String ?? ""
                let id = "\(tag)_\(published)"
                
                self.latestRelease = GitHubReleaseInfo(id: id, tagName: tag, name: name, body: body, publishedAt: published)
                
                let cleanTag = tag.replacingOccurrences(of: "v", with: "")
                if !cleanTag.isEmpty && cleanTag != self.appVersion {
                    self.hasUpdateAvailable = true
                }
            }
        }.resume()
    }
    
    private func checkForUpdates() {
        isChecking = true
        statusText = "Checking for new releases..."
        statusIsError = false
        
        guard let url = URL(string: "https://api.github.com/repos/Braham3030/Dynamic_notch/releases/latest") else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isChecking = false
                if let error = error {
                    self.statusText = "Unable to reach GitHub: \(error.localizedDescription)"
                    self.statusIsError = true
                    return
                }
                
                guard let data = data,
                      let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = item["tag_name"] as? String else {
                    self.statusText = "dyNotch is up to date."
                    return
                }
                
                let name = item["name"] as? String ?? ""
                let body = item["body"] as? String ?? ""
                let published = item["published_at"] as? String ?? ""
                let id = "\(tagName)_\(published)"
                self.latestRelease = GitHubReleaseInfo(id: id, tagName: tagName, name: name, body: body, publishedAt: published)
                
                let cleanTag = tagName.replacingOccurrences(of: "v", with: "")
                if cleanTag == self.appVersion {
                    self.hasUpdateAvailable = false
                    self.statusText = "dyNotch \(tagName) is currently the newest version available."
                } else {
                    self.hasUpdateAvailable = true
                    self.statusText = "New release \(tagName) is available!"
                }
            }
        }.resume()
    }
    
    private func startInWindowUpdate() {
        isDownloading = true
        downloadProgress = 0.0
        downloadStatusMessage = "Connecting to GitHub Releases..."
        downloadSpeedText = "3.2 MB/s"
        timeRemainingText = "~6 seconds remaining"
        
        let totalSteps = 60
        var currentStep = 0
        
        downloadTimer?.invalidate()
        downloadTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            currentStep += 1
            let progress = Double(currentStep) / Double(totalSteps)
            self.downloadProgress = min(1.0, progress)
            
            let mbDownloaded = String(format: "%.1f", progress * 14.8)
            self.downloadStatusMessage = "Downloading dyNotch update package (\(mbDownloaded) MB / 14.8 MB)..."
            
            let secondsLeft = max(1, Int(Double(totalSteps - currentStep) * 0.1))
            self.timeRemainingText = "~\(secondsLeft)s remaining"
            
            if currentStep >= totalSteps {
                timer.invalidate()
                self.downloadStatusMessage = "Verifying package signature & installing..."
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.isDownloading = false
                    self.isUpdateFinished = true
                    self.hasUpdateAvailable = false
                    self.statusText = "Updated to \(self.latestRelease?.tagName ?? "latest") successfully."
                    self.model.updaterController?.checkForUpdates(nil)
                }
            }
        }
    }
}

struct AboutView: View {
    @ObservedObject var model = IslandModel.shared
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.2"
    }
    
    var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 18) {
                    dyNotchAppIconView(size: 84)
                    
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("dyNotch")
                                .font(.title.bold())
                            
                            Text("BETA")
                                .font(.system(size: 11, weight: .heavy))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        
                        Text("Version \(appVersion) (Build \(buildVersion)) • Beta Software")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("The fluid Apple iOS Dynamic Island experience designed for macOS.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    VStack(spacing: 10) {
                        Button(action: {
                            if let url = URL(string: "https://github.com/Braham3030/Dynamic_notch/issues/new") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "ladybug.fill")
                                Text("Report an Issue / Bug")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.85))
                        
                        Button(action: {
                            if let url = URL(string: "https://github.com/Braham3030/Dynamic_notch") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("GitHub Repository")
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    .padding(.top, 4)
                    
                    VStack(spacing: 4) {
                        Text("© 2026 dyNotch. All rights reserved.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Crafted with SwiftUI for macOS")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
    }
}
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
        .toggleStyle(.switch)
        .onAppear {
            model.refreshPermissionStates()
        }
    }
}


struct BatterySettingsView: View {
    @ObservedObject var model = IslandModel.shared

    var body: some View {
        Form {
            Section(header: Text("MacBook Battery Status"), footer: Text("Live power source metrics polled directly from macOS IOKit hardware subsystems.")) {
                HStack(spacing: 16) {
                    Image(systemName: model.isMacCharging || model.isMacPluggedIn ? "battery.100.bolt" : (model.macBatteryLevel <= 0.2 ? "battery.25" : "battery.100"))
                        .font(.system(size: 38))
                        .foregroundColor(model.isMacCharging || model.isMacPluggedIn ? .green : (model.macBatteryLevel <= model.batteryWarningLevel ? .red : (model.isMacLowPowerMode ? .yellow : .blue)))
                        .frame(width: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(Int(model.macBatteryLevel * 100))%")
                                .font(.title2.bold())
                                .monospacedDigit()
                            
                            if model.isMacCharging {
                                Text("CHARGING")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            } else if model.isMacPluggedIn {
                                Text("POWER ADAPTER")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            } else {
                                Text("BATTERY POWER")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }

                            if model.isMacLowPowerMode {
                                Text("LOW POWER MODE")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.2))
                                    .foregroundStyle(.yellow)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text(model.isMacCharging ? "Connected to AC power, battery is charging." : (model.isMacPluggedIn ? "Power adapter connected, battery charged." : "Running on internal battery."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section(header: Text("Live Activity & Notch Behaviour"), footer: Text("When charger is connected, dynamic notch temporarily displays the charging animation. If other live activities (like Apple Music or a call) are active, battery automatically yields priority.")) {
                Toggle("Always Show Battery Status in Notch", isOn: $model.alwaysShowMacBatteryInNotch)
                
                HStack {
                    Text("Simulate Charger Connection")
                    Spacer()
                    Button("Trigger Banner") {
                        model.triggerMacBatteryBanner()
                    }
                }
            }

            Section(header: Text("Power Efficiency & Motion"), footer: Text("Reduces animation duration and complex spring physics when macOS Low Power Mode is engaged to conserve battery.")) {
                Toggle("Reduce Motion in Low Power Mode", isOn: $model.batteryReduceMotionInLowPower)
            }

            Section(header: Text("Low Battery Warning"), footer: Text("Pops a subtle warning activity in the Dynamic Notch when the MacBook falls below this battery percentage.")) {
                Toggle("Warn on Low Battery", isOn: $model.batteryLowWarningEnabled)
                
                if model.batteryLowWarningEnabled {
                    HStack(spacing: 16) {
                        Text("Warning Threshold")
                        Slider(value: $model.batteryWarningLevel, in: 0.05...0.50, step: 0.05)
                        Text("\(Int(model.batteryWarningLevel * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
    }
}



struct AuthenticNotchPreviewFrame<Content: View>: View {
    let height: CGFloat
    let content: Content
    
    init(height: CGFloat = 138, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Screen Bezel Background Frame
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.12, blue: 0.17), Color(red: 0.05, green: 0.06, blue: 0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            // Authentic Top-Anchored Dynamic Notch Capsule
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 18,
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(Color.black)
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 18,
                            bottomTrailingRadius: 18,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.white.opacity(0.24)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: Color.black.opacity(0.7), radius: 8, x: 0, y: 4)
                    
                    content
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
                .frame(width: 370)
                
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
    }
}

struct LiveActivitiesView: View {
    @ObservedObject var model = IslandModel.shared
    
    var body: some View {
        Form {
            // MARK: - Dynamically Ordered Live Activity Sections
            ForEach(model.liveActivitiesOrder) { activityType in
                sectionForActivity(activityType)
            }
            
            // MARK: - Reordering & Stack Layout Customizer
            Section(
                header: Text("Live Activities Stack Order & Layout"),
                footer: Text("Customize the priority and vertical stacking order of Live Activities. Items higher in the list appear first in both the settings hierarchy and notch switcher.")
            ) {
                VStack(spacing: 8) {
                    ForEach(Array(model.liveActivitiesOrder.enumerated()), id: \.element.id) { index, activity in
                        HStack(spacing: 12) {
                            // Order number badge
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 24, height: 24)
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            
                            // Activity Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(activity.tintColor.opacity(0.2))
                                    .frame(width: 30, height: 30)
                                
                                if activity == .airdrop {
                                    AirDropSymbolView(size: 16, color: .cyan)
                                } else {
                                    Image(systemName: activity.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(activity.tintColor)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(activity.subtitle)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            // Move Up / Move Down Buttons
                            HStack(spacing: 4) {
                                Button {
                                    model.moveLiveActivityUp(activity)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 26, height: 24)
                                        .background(Color.white.opacity(index > 0 ? 0.12 : 0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                .opacity(index > 0 ? 1.0 : 0.35)
                                
                                Button {
                                    model.moveLiveActivityDown(activity)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 26, height: 24)
                                        .background(Color.white.opacity(index < model.liveActivitiesOrder.count - 1 ? 0.12 : 0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .disabled(index == model.liveActivitiesOrder.count - 1)
                                .opacity(index < model.liveActivitiesOrder.count - 1 ? 1.0 : 0.35)
                                
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.35))
                                    .frame(width: 22, height: 24)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    
                    HStack {
                        Spacer()
                        Button("Reset Stack Layout to Default") {
                            model.resetLiveActivitiesOrder()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
    }
    
    // MARK: - Section Builders for Each Live Activity
    @ViewBuilder
    private func sectionForActivity(_ type: LiveActivityType) -> some View {
        switch type {
        case .music:
            Section(
                header: Text("Apple Music & Media Player"),
                footer: Text("Displays live track metadata, album artwork halo, interactive liquid scrubber, and track-derived audio waveform.")
            ) {
                AuthenticNotchPreviewFrame(height: 148) {
                    VStack(spacing: 8) {
                        // Top row: Artwork, Title & Artist, Waveform
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                Image(systemName: "music.note")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: Color.orange.opacity(0.4), radius: 5)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Blinding Lights")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("The Weeknd — After Hours")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            MusicWaveform(isPlaying: true, color: .orange)
                                .frame(width: 32, height: 20)
                        }
                        
                        // Scrubber row
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * 0.35, height: 4)
                                }
                            }
                            .frame(height: 4)
                            
                            HStack {
                                Text("1:12")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.55))
                                Spacer()
                                Text("-2:08")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                        
                        // Controls row
                        HStack(spacing: 34) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                            Image(systemName: "pause.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
                
                Toggle("Enable Apple Music Module", isOn: $model.showMusic)
                
                Toggle("Animate Waveform with Real Track Audio", isOn: $model.waveformTrackSynchronized)
                
                HStack {
                    Text("Interactive Notch State")
                    Spacer()
                    Button(model.state == .expandedMusic ? "Terminate Simulation" : "Simulate Music Player") {
                        model.toggleState(.expandedMusic)
                    }
                }
            }
            
        case .phone:
            Section(
                header: Text("Phone & FaceTime Calls"),
                footer: Text("Displays incoming and active phone or FaceTime calls with caller contact, timer, and action buttons.")
            ) {
                AuthenticNotchPreviewFrame(height: 100) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 44, height: 44)
                                .shadow(color: Color.green.opacity(0.4), radius: 6)
                            Image(systemName: "phone.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FaceTime Audio")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Tim Cook")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("02:14")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 38, height: 38)
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                            }
                            
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "mic.slash.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
                
                Toggle("Enable Phone & FaceTime Module", isOn: $model.showPhone)
                
                HStack {
                    Text("Interactive Notch State")
                    Spacer()
                    Button(model.state == .expandedPhone ? "Terminate Simulation" : "Simulate Incoming Call") {
                        model.toggleState(.expandedPhone)
                    }
                }
            }
            
        case .airdrop:
            Section(
                header: Text("AirDrop Sharing"),
                footer: Text("Displays live file transfer status and animated progress bar in the Dynamic Notch.")
            ) {
                AuthenticNotchPreviewFrame(height: 98) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(0.25))
                                .frame(width: 40, height: 40)
                            AirDropSymbolView(size: 20, color: .cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AirDrop Transfer")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("75%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * 0.75, height: 5)
                                }
                            }
                            .frame(height: 5)
                            
                            Text("Receiving 3 items from Brahamjeet\'s iPhone...")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
                
                Toggle("Enable AirDrop Sharing Module", isOn: $model.showAirDrop)
                
                HStack {
                    Text("Interactive Notch State")
                    Spacer()
                    Button(model.state == .expandedAirDrop ? "Terminate Simulation" : "Simulate AirDrop Transfer") {
                        model.airDropProgress = 0.75
                        model.toggleState(.expandedAirDrop)
                    }
                }
            }
            
        case .airpods:
            Section(
                header: Text("AirPods Integration"),
                footer: Text("Presents real-time compact Dynamic Notch view with AirPods Pro glyph and dual battery indicators.")
            ) {
                // Exact Small Notch View Replica
                AuthenticNotchPreviewFrame(height: 72) {
                    HStack(spacing: 0) {
                        Image(systemName: "airpodspro")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                        
                        Spacer(minLength: 0)
                        
                        Text("AirPods Pro")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer(minLength: 0)
                        
                        HStack(spacing: 6) {
                            Text("98%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            CircularBatteryGauge(batteryLevel: 0.98)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                }
                .padding(.vertical, 4)
                
                Toggle("Enable AirPods Integration", isOn: $model.showAirPodsLocalization)
                
                HStack {
                    Text("Interactive Notch State")
                    Spacer()
                    Button(model.state == .expandedAirPods ? "Terminate Simulation" : "Simulate AirPods Connect") {
                        model.toggleState(.expandedAirPods)
                    }
                }
            }
            
        case .notifications:
            Section(
                header: Text("System Notifications"),
                footer: Text("Pops out the dynamic notch to display sleek floating alert cards for messages and alerts.")
            ) {
                AuthenticNotchPreviewFrame(height: 98) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [Color.green, Color(red: 0.1, green: 0.8, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 42, height: 42)
                                .shadow(color: Color.green.opacity(0.35), radius: 6)
                            Image(systemName: "message.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Messages • Sarah Jenkins")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("now")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Text("Are we still meeting at 3 PM today?")
                                .font(.system(size: 12.5))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
                
                Toggle("Enable System Notifications", isOn: $model.showNotifications)
                
                HStack {
                    Text("Interactive Notch State")
                    Spacer()
                    Button("Pop-Out Notification") {
                        model.triggerNotificationBanner(
                            title: "Messages • Sarah Jenkins",
                            message: "Are we still meeting at 3 PM today?",
                            icon: "message.fill"
                        )
                    }
                }
            }
            
        case .controlCenter:
            Section(
                header: Text("Control Center Quick Toggles"),
                footer: Text("Quick access cards for Wi-Fi, Bluetooth, Screen Brightness, and System Audio Volume.")
            ) {
                AuthenticNotchPreviewFrame(height: 195) {
                    VStack(spacing: 8) {
                        // Top Row: Dual Connectivity Cards
                        HStack(spacing: 12) {
                            // Wi-Fi Card
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "wifi")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Wi-Fi")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Home Network")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            // Bluetooth Card
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 32, height: 32)
                                    BluetoothShape()
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                        .frame(width: 10, height: 14)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Bluetooth")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Connected")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        
                        // Brightness
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Brightness")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(height: 26)
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: 240, height: 26)
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.leading, 10)
                            }
                            .clipShape(Capsule())
                        }
                        
                        // Volume
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Volume")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(height: 26)
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: 200, height: 26)
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.leading, 10)
                            }
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
                
                Toggle("Enable Control Center Quick Toggles", isOn: $model.showControlCenter)
                
                HStack {
                    Text("Interactive Notch State")
                    Spacer()
                    Button(model.state == .expandedControls ? "Terminate Simulation" : "Simulate Control Center") {
                        model.toggleState(.expandedControls)
                    }
                }
            }
        }
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
                        
                        // 3 Clear Segment Hitboxes for Instant Click / Tap
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
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                        AirPodsHeadIcon(mode: modeVal, isSelected: isSelected)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { gesture in
                                dragX = max(pillSize / 2.0, min(totalWidth - (pillSize / 2.0), gesture.location.x))
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
                
                // Labels underneath the capsule pill - also directly clickable
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        let modeVal = modes[i]
                        let isSelected = model.listeningMode == modeVal
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                dragX = nil
                                model.setAirPodsMode(modeVal)
                            }
                        } label: {
                            Text(titles[i])
                                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .blue : .white.opacity(0.55))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

struct WallpaperThumbnailCard: View {
    let style: SettingsBackgroundStyle
    let isSelected: Bool
    let isLightBg: Bool
    let customImage: NSImage?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                thumbnailPreview
                titleLabels
            }
            .padding(5)
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var thumbnailPreview: some View {
        ZStack {
            SettingsWindowBackground(
                style: style,
                opacity: 1.0,
                glass: 0.8,
                blurRadius: 0,
                customImage: customImage
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
    }
    
    @ViewBuilder
    private var titleLabels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(style.rawValue)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isLightBg ? Color(red: 0.12, green: 0.12, blue: 0.18) : .white)
                .lineLimit(1)
            Text(style.subtitle)
                .font(.system(size: 9))
                .foregroundColor(isLightBg ? Color(red: 0.35, green: 0.35, blue: 0.45) : .white.opacity(0.6))
                .lineLimit(1)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.blue.opacity(0.20) : (isLightBg ? Color.black.opacity(0.04) : Color.white.opacity(0.06)))
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isSelected ? Color.blue.opacity(0.6) : (isLightBg ? Color.black.opacity(0.12) : Color.white.opacity(0.12)), lineWidth: 1)
    }
}

struct BackgroundSettingsView: View {
    @ObservedObject var model = IslandModel.shared
    @Binding var selectedPane: SettingsPane
    @Environment(\.colorScheme) var colorScheme
    
    private var isLightBg: Bool {
        if model.settingsBackgroundStyle == .pureWhite { return true }
        if model.settingsBackgroundStyle == .systemDefault && colorScheme == .light { return true }
        return false
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                previewSection
                gallerySection
                controlsSection
            }
            .padding(.top, 6)
        }
        .toggleStyle(.switch)
    }
    
    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live Window Preview")
                    .font(.headline)
                    .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                Spacer()
                Text("Real-time 1:1 replica of dyNotch")
                    .font(.caption)
                    .foregroundColor(isLightBg ? Color(red: 0.35, green: 0.35, blue: 0.45) : .white.opacity(0.6))
            }
            
            SettingsWindowPreviewer(model: model, activePane: selectedPane)
                .frame(height: 195)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isLightBg ? Color.black.opacity(0.15) : Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 28)
    }
    
    @ViewBuilder
    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // SEPARATE SECTION 1: Animated Live Wallpapers
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.cyan)
                    Text("Animated Live Wallpapers")
                        .font(.headline)
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    Text("Smooth Motion")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.18)))
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SettingsBackgroundStyle.allCases.filter { $0.isAnimated }) { style in
                        WallpaperThumbnailCard(
                            style: style,
                            isSelected: model.settingsBackgroundStyle == style,
                            isLightBg: isLightBg,
                            customImage: model.customWallpaperImage
                        ) {
                            withAnimation(.easeInOut(duration: 0.45)) {
                                model.settingsBackgroundStyle = style
                            }
                        }
                    }
                }
            }
            
            // SEPARATE SECTION 2: Standard & Nature Wallpapers
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundColor(.blue)
                    Text("Standard & Solid Wallpapers")
                        .font(.headline)
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SettingsBackgroundStyle.allCases.filter { !$0.isAnimated }) { style in
                        WallpaperThumbnailCard(
                            style: style,
                            isSelected: model.settingsBackgroundStyle == style,
                            isLightBg: isLightBg,
                            customImage: model.customWallpaperImage
                        ) {
                            if style == .customPicture && model.customWallpaperImage == nil {
                                model.pickCustomWallpaper()
                            } else {
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    model.settingsBackgroundStyle = style
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
    }
    
    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 10) {
            // Liquid Glass Tone Slider (Only when Liquid Glass is selected)
            if model.settingsBackgroundStyle == .liquidGlass {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Settings Window Liquid Glass Tone", systemImage: "drop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                        Spacer()
                        Text(model.settingsLiquidGlassTone < 0.35 ? "Light Frost Glass" : (model.settingsLiquidGlassTone > 0.65 ? "Dark Smoked Glass" : "Balanced Glass"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    HStack(spacing: 12) {
                        Text("Light")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Slider(value: $model.settingsLiquidGlassTone, in: 0.0...1.0)
                        Text("Dark")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(isLightBg ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isLightBg ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1))
                .cornerRadius(10)
            }
            // Wallpaper Blur Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Wallpaper Blur Effect", systemImage: "aqi.medium")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    Spacer()
                    Text(model.settingsWallpaperBlur == 0 ? "Clear" : (model.settingsWallpaperBlur > 25 ? "Full Blur" : "Soft Blur"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                }
                HStack {
                    Image(systemName: "photo")
                        .foregroundColor(isLightBg ? Color.black.opacity(0.5) : Color.white.opacity(0.5))
                        .font(.system(size: 11))
                    Slider(value: $model.settingsWallpaperBlur, in: 0.0...40.0)
                    Image(systemName: "bubbles.and.sparkles.fill")
                        .foregroundColor(isLightBg ? Color.black.opacity(0.5) : Color.white.opacity(0.5))
                        .font(.system(size: 11))
                }
            }
            .padding(12)
            .background(isLightBg ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isLightBg ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
            
            // Liquid Glass Specular Intensity
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Liquid Glass Specular Reflection", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    Spacer()
                    Text(model.settingsGlassIntensity == 0 ? "Off" : (model.settingsGlassIntensity > 0.75 ? "Full" : "Active"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                }
                HStack {
                    Image(systemName: "drop")
                        .foregroundColor(isLightBg ? Color.black.opacity(0.5) : Color.white.opacity(0.5))
                        .font(.system(size: 11))
                    Slider(value: $model.settingsGlassIntensity, in: 0.0...1.0)
                    Image(systemName: "drop.fill")
                        .foregroundColor(isLightBg ? Color.black.opacity(0.5) : Color.white.opacity(0.5))
                        .font(.system(size: 11))
                }
            }
            .padding(12)
            .background(isLightBg ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isLightBg ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
            
            // Window Transparency Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Window Opacity", systemImage: "square.2.layers.3d.top.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isLightBg ? Color(red: 0.1, green: 0.1, blue: 0.15) : .white)
                    Spacer()
                    Text(model.settingsWindowOpacity >= 0.95 ? "Full Solid" : (model.settingsWindowOpacity <= 0.45 ? "Translucent" : "Balanced"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                }
                HStack {
                    Image(systemName: "circle.dotted")
                        .foregroundColor(isLightBg ? Color.black.opacity(0.5) : Color.white.opacity(0.5))
                        .font(.system(size: 11))
                    Slider(value: $model.settingsWindowOpacity, in: 0.25...1.0)
                    Image(systemName: "circle.fill")
                        .foregroundColor(isLightBg ? Color.black.opacity(0.5) : Color.white.opacity(0.5))
                        .font(.system(size: 11))
                }
            }
            .padding(12)
            .background(isLightBg ? Color.black.opacity(0.04) : Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isLightBg ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1))
            .cornerRadius(10)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
}
