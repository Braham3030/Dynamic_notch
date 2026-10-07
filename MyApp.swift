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
        // Initialize Sparkle OTA updater
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
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
    
    private func setupMouseTracking() {
        // Track mouse globally across all apps (Apple Music, Finder, Settings, etc.)
        mouseMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            // ONLY open AirDrop in the notch when the user is actively dragging REAL files or photos!
            if event.type == .leftMouseDragged {
                let pboard = NSPasteboard(name: .drag)
                if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                    let hasRealFilesOrPhotos = urls.contains { url in
                        let ext = url.pathExtension.lowercased()
                        let isPhotoOrFile = url.isFileURL || !ext.isEmpty || FileManager.default.fileExists(atPath: url.path)
                        return isPhotoOrFile
                    }
                    if hasRealFilesOrPhotos {
                        DispatchQueue.main.async {
                            if !IslandModel.shared.isAirDropTargeted && IslandModel.shared.state != .expandedAirDrop {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    IslandModel.shared.isAirDropTargeted = true
                                }
                            }
                        }
                    }
                }
            }
            self?.handleMouseLocation(NSEvent.mouseLocation)
        }
        // Track mouse locally within our application
        mouseMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation)
            return event
        }
        
        // Auto reset targeted state on mouse up only after a safety delay if not in expandedAirDrop
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if IslandModel.shared.isAirDropTargeted && IslandModel.shared.state != .expandedAirDrop {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        IslandModel.shared.isAirDropTargeted = false
                    }
                }
            }
        }
    }
    
    private func handleMouseLocation(_ location: NSPoint) {
        let model = IslandModel.shared
        let width = model.width
        let height = model.height
        
        for item in islandWindows {
            let screen = item.screen
            let win = item.window
            
            // Calculate active notch rect on this screen in macOS screen coordinates
            // Include extra right margin when expanded so the popout switcher is never blocked by ignoresMouseEvents
            let extraRight: CGFloat = model.isExpanded ? 90 : 0
            let notchX = screen.frame.midX - (width / 2.0)
            let notchY = screen.frame.maxY - height
            let activeRect = NSRect(x: notchX - 10, y: notchY - 10, width: width + 20 + extraRight, height: height + 20)
            
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
        let hostingController = NSHostingController(rootView: islandView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let width: CGFloat = 680
        let height: CGFloat = 280
        
        let originX = screen.frame.midX - (width / 2.0)
        let originY = screen.frame.maxY - height
        
        let win = IslandOverlayWindow(
            contentRect: NSRect(x: originX, y: originY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = hostingController
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
