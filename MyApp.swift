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
                .frame(width: 840, height: 680)
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindows: [(window: NSWindow, screen: NSScreen)] = []
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
    
    private var lastDragPasteboardCount: Int = -1
    private var dragWatchTimer: Timer?

    private func setupMouseTracking() {
        // Track mouse globally across all apps for smooth notch hover interactions & drag detection
        mouseMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation, eventType: event.type)
        }
        // Track mouse locally within our application
        mouseMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation, eventType: event.type)
            return event
        }
        
        // Fast periodic check on the drag pasteboard to detect drag start anywhere on macOS instantly!
        dragWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.checkActiveFileDrag()
        }
    }
    
    private func checkActiveFileDrag() {
        let pboard = NSPasteboard(name: .drag)
        let count = pboard.changeCount
        let types = pboard.types ?? []
        let hasFiles = types.contains(.fileURL) || types.contains(.URL) || types.contains(NSPasteboard.PasteboardType("public.file-url")) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        let mouseButtons = NSEvent.pressedMouseButtons
        let isDragging = (mouseButtons & 1) != 0 // Left mouse button currently held down
        
        let model = IslandModel.shared
        if isDragging && hasFiles && count != 0 {
            if !model.isAirDropTargeted && model.state != .expandedAirDrop {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        model.isAirDropTargeted = true
                    }
                }
            }
        } else if !isDragging {
            if model.isAirDropTargeted && model.state != .expandedAirDrop {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        model.isAirDropTargeted = false
                    }
                }
            }
        }
    }
    
    private func handleMouseLocation(_ location: NSPoint, eventType: NSEvent.EventType? = nil) {
        let model = IslandModel.shared
        let width = model.width
        let height = model.height
        
        if eventType == .leftMouseDragged {
            checkActiveFileDrag()
        }
        
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
        win.registerForDraggedTypes([.fileURL, .URL])
                }
            }
        }
    }
    
    func updateWindows(for mode: ScreenDisplayMode) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.islandWindows.forEach { $0.window.orderOut(nil) }
            self.islandWindows.removeAll()

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
            }
        }
    }
    
    func createIslandWindow(for screen: NSScreen) -> NSWindow {
        let islandView = IslandView(model: IslandModel.shared)
        let hostingView = NSHostingView(rootView: islandView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        
        let width: CGFloat = 680
        let height: CGFloat = 500
        
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
        
        win.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        win.orderFrontRegardless()
        return win
    }
}
