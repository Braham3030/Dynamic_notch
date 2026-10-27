import SwiftUI
import AppKit
import Combine
import Sparkle

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("dyNotch") {
            ContentView()
                .frame(minWidth: 520, idealWidth: 860, maxWidth: .infinity, minHeight: 460, idealHeight: 680, maxHeight: .infinity)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    } 
}

class IslandOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

class IslandDropTargetHostingView<Content: View>: NSHostingView<Content> {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let types = pboard.types ?? []
        let hasFiles = types.contains(.fileURL) || types.contains(.URL) || types.contains(NSPasteboard.PasteboardType("public.file-url")) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        if hasFiles {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    IslandModel.shared.isAirDropTargeted = true
                }
            }
            return .copy
        }
        return []
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let types = pboard.types ?? []
        let hasFiles = types.contains(.fileURL) || types.contains(.URL) || types.contains(NSPasteboard.PasteboardType("public.file-url")) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        return hasFiles ? .copy : []
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                IslandModel.shared.isAirDropTargeted = false
            }
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let directURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !directURLs.isEmpty {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    IslandModel.shared.isAirDropTargeted = false
                    for u in directURLs {
                        if !IslandModel.shared.droppedAirDropFiles.contains(u) {
                            IslandModel.shared.droppedAirDropFiles.append(u)
                        }
                    }
                    IslandModel.shared.state = .expandedAirDrop
                }
            }
            return true
        }
        return false
    }
}


struct FullScreenGlowView: View {
    @ObservedObject var model = IslandModel.shared
    @ObservedObject var analyzer = AudioAnalyzer.shared
    
    var body: some View {
        GeometryReader { geo in
            if model.enableFullWindowGlow && model.isMusicPlaying {
                // Calculate dynamic audio pulse factor directly from real-time FFT bass & midrange harmonics!
                // Band 0 = Sub-bass/Kick, Band 1 = Bassline, Band 2 = Vocals/Midrange
                let bassEnergy = analyzer.peaks.indices.contains(0) ? Double(analyzer.peaks[0]) : 0.25
                let midEnergy = analyzer.peaks.indices.contains(2) ? Double(analyzer.peaks[2]) : 0.25
                let audioFactor = min(1.0, max(0.0, (bassEnergy * 0.65 + midEnergy * 0.35)))
                
                // Dynamic breathing parameters driven by live track sound:
                let currentIntensity = model.fullWindowGlowIntensity * (0.50 + audioFactor * 0.85)
                let dynamicBorderWidth: CGFloat = 32.0 + CGFloat(audioFactor * 28.0)
                let dynamicBlur: CGFloat = 24.0 + CGFloat(audioFactor * 22.0)
                let dynamicFloodHeight: CGFloat = 260.0 + CGFloat(audioFactor * 120.0)
                
                ZStack {
                    // 1. Outer peripheral display border glow that dynamically pulses with the real track audio!
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    model.artworkColor.opacity(min(1.0, currentIntensity * 0.95)),
                                    model.artworkColor.opacity(min(1.0, currentIntensity * 0.55)),
                                    model.artworkColor.opacity(min(1.0, currentIntensity * 0.25)),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: dynamicBorderWidth
                        )
                        .blur(radius: dynamicBlur)
                        .blendMode(.plusLighter)
                    
                    // 2. Top ambient floodlight glow directly below display notch reacting dynamically to track transients!
                    VStack {
                        RadialGradient(
                            colors: [
                                model.artworkColor.opacity(min(1.0, currentIntensity * 0.75)),
                                model.artworkColor.opacity(min(1.0, currentIntensity * 0.25)),
                                Color.clear
                            ],
                            center: .top,
                            startRadius: 20,
                            endRadius: min(geo.size.width, geo.size.height) * (0.55 + CGFloat(audioFactor * 0.25))
                        )
                        .frame(height: dynamicFloodHeight)
                        .blur(radius: dynamicBlur + 10)
                        .blendMode(.plusLighter)
                        
                        Spacer()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
                .animation(.spring(response: 0.16, dampingFraction: 0.72), value: audioFactor)
                .animation(.easeInOut(duration: 0.5), value: model.artworkColor)
            }
        }
        .ignoresSafeArea()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindows: [(window: NSWindow, screen: NSScreen)] = []
    var glowWindows: [NSWindow] = []
    var updaterController: SPUStandardUpdaterController!
    var cancellables = Set<AnyCancellable>()
    private var mouseMonitorLocal: Any?
    private var mouseMonitorGlobal: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") {
            NSApplication.shared.applicationIconImage = icon
        }
        // Initialize Sparkle OTA updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        IslandModel.shared.updaterController = updaterController
        
        IslandModel.shared.$displayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.updateWindows(for: mode)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateWindows(for: IslandModel.shared.displayMode)
        }
        
        // Continuous mouse tracking for dynamic WindowServer passthrough
        setupMouseTracking()
            
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            if IslandModel.shared.autoCloseBehavior == .clickOutside && IslandModel.shared.isHoverExpanded {
                DispatchQueue.main.async {
                    IslandModel.shared.isHoverExpanded = false
                }
            }
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .swipe) { event in
            if event.deltaX != 0 {
                DispatchQueue.main.async {
                    IslandModel.shared.beginSwipeCollapse()
                }
            }
        }
    }
    
    private var dragCheckTimer: Timer?
    private var dragStartTime: Date?

    private func setupMouseTracking() {
        // Track mouse globally across all apps for smooth notch hover interactions
        mouseMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation)
            self?.checkImageDragState()
        }
        // Track mouse locally within our application
        mouseMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation)
            self?.checkImageDragState()
            return event
        }
        
        // Fast periodic checker to detect drag time progression & release across the entire OS
        dragCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.checkImageDragState()
        }
    }
    
    private func checkImageDragState() {
        let mouseButtons = NSEvent.pressedMouseButtons
        let isLeftDown = (mouseButtons & 1) != 0
        let model = IslandModel.shared
        
        // If left mouse button is NOT pressed, user is not dragging anything -> reset timer and collapse
        guard isLeftDown else {
            dragStartTime = nil
            if model.isAirDropTargeted && model.state != .expandedAirDrop {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        model.isAirDropTargeted = false
                    }
                }
            }
            return
        }
        
        let pboard = NSPasteboard(name: .drag)
        let count = pboard.changeCount
        
        // If pasteboard has never had a drag, or count is 0
        guard count > 0 else {
            dragStartTime = nil
            return
        }
        
        // Check if drag pasteboard contains an image (URL with image extension or raw image data)
        let isPicture = isDragPasteboardAnImage(pboard)
        
        if isPicture {
            if dragStartTime == nil {
                dragStartTime = Date()
            }
            
            let elapsed = Date().timeIntervalSince(dragStartTime ?? Date())
            let threshold = model.fileDragOpenDelay
            
            if elapsed >= threshold {
                if !model.isAirDropTargeted && model.state != .expandedAirDrop {
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            model.isAirDropTargeted = true
                        }
                    }
                }
            }
        } else {
            dragStartTime = nil
            if model.isAirDropTargeted && model.state != .expandedAirDrop {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        model.isAirDropTargeted = false
                    }
                }
            }
        }
    }
    
    private func isDragPasteboardAnImage(_ pboard: NSPasteboard) -> Bool {
        let types = pboard.types ?? []
        
        // 1. Check for raw image pasteboard types
        let imageTypeIdentifiers = [
            NSPasteboard.PasteboardType.tiff,
            NSPasteboard.PasteboardType.png,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.tiff")
        ]
        
        for t in imageTypeIdentifiers {
            if types.contains(t) { return true }
        }
        
        // 2. Check for URLs with picture extensions (.png, .jpg, .jpeg, .heic, .webp, .gif, .tiff, .svg, .bmp, .icns)
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "tif", "svg", "bmp", "icns", "raw", "cr2", "nef", "arw", "dng"]
            for url in urls {
                if imageExts.contains(url.pathExtension.lowercased()) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func handleMouseLocation(_ location: NSPoint) {
        let model = IslandModel.shared
        let width = model.width
        let height = model.height
        
        for item in islandWindows {
            let screen = item.screen
            let win = item.window
            
            // Calculate strict active notch rect on this screen in macOS screen coordinates
            let extraRight: CGFloat = model.isExpanded ? 90 : 0
            let notchX = screen.frame.midX - (width / 2.0)
            let notchY = screen.frame.maxY - height
            // When compact: strictly match notch boundary with 0 vertical overhang below the notch
            let activeRect: NSRect
            if model.isExpanded {
                activeRect = NSRect(x: notchX - 6, y: notchY - 6, width: width + 12 + extraRight, height: height + 6)
            } else {
                activeRect = NSRect(x: notchX, y: notchY, width: width, height: height)
            }
            
            let isInside = activeRect.contains(location)
            
            if isInside {
                // Inside notch: Enable mouse events so buttons, sliders, and clicks on the notch work
                if win.ignoresMouseEvents {
                    win.ignoresMouseEvents = false
                }
            } else {
                // Outside notch: Set ignoresMouseEvents = true so WindowServer passes 100% of clicks straight to Apple Music, Settings, Finder, etc.!
                if !win.ignoresMouseEvents {
                    win.ignoresMouseEvents = true
                }
            }
        }
    }
    
    func updateWindows(for mode: ScreenDisplayMode) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.islandWindows.forEach { $0.window.orderOut(nil) }
            self.islandWindows.removeAll()
            self.glowWindows.forEach { $0.orderOut(nil) }
            self.glowWindows.removeAll()

            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }

            var targetScreens: [NSScreen] = []
            
            switch mode {
            case .macbook:
                targetScreens = [screens[0]] 
            case .external:
                if screens.count > 1 {
                    targetScreens = Array(screens.dropFirst())
                } else {
                    targetScreens = [screens[0]]
                }
            case .both:
                targetScreens = screens
            }
            
            for screen in targetScreens {
                let win = self.createIslandWindow(for: screen)
                self.islandWindows.append((window: win, screen: screen))
                
                let glowWin = self.createScreenGlowWindow(for: screen)
                self.glowWindows.append(glowWin)
            }
        }
    }
    
    func createIslandWindow(for screen: NSScreen) -> NSWindow {
        let islandView = IslandView(model: IslandModel.shared)
        let hostingView = IslandDropTargetHostingView(rootView: islandView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        hostingView.registerForDraggedTypes([.fileURL, .URL])
        
        let width: CGFloat = 680
        let height: CGFloat = 620
        
        let originX = screen.frame.midX - (width / 2.0)
        let originY = screen.frame.maxY - height
        
        let win = IslandOverlayWindow(
            contentRect: NSRect(x: originX, y: originY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.isRestorable = false 
        // Default to ignoring mouse events so underlying apps (Apple Music, Settings, Finder) are NEVER blocked!
        win.ignoresMouseEvents = true
        win.registerForDraggedTypes([.fileURL, .URL])
        
        win.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        win.orderFrontRegardless()
        return win
    }

    func createScreenGlowWindow(for screen: NSScreen) -> NSWindow {
        let glowView = FullScreenGlowView()
        let hostingView = NSHostingView(rootView: glowView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.isRestorable = false
        win.ignoresMouseEvents = true
        win.setFrame(screen.frame, display: true)
        win.orderFrontRegardless()
        return win
    }
}
