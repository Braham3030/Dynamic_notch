import SwiftUI
import AppKit
import Combine
import Sparkle

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup("Dynamic Island Settings") {
            ContentView()
                .frame(width: 780, height: 640)
        }
        .windowResizability(.contentSize)
    } 
}

class IslandOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    
    override func updateConstraintsIfNeeded() {
        // Safe no-op to eliminate layout constraint update loops
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var islandWindows: [NSWindow] = []
    var updaterController: SPUStandardUpdaterController!
    var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize and boot up Sparkle OTA background updater engine!
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
        
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            if event.phase == .began && abs(event.scrollingDeltaX) > 2.0 && event.hasPreciseScrollingDeltas {
                DispatchQueue.main.async {
                    IslandModel.shared.beginSwipeCollapse()
                }
            }
        }
    }
    
    func updateWindows(for mode: ScreenDisplayMode) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.islandWindows.forEach { $0.orderOut(nil) }
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
                self.islandWindows.append(win)
            }
        }
    }
    
    func createIslandWindow(for screen: NSScreen) -> NSWindow {
        let islandView = IslandView(model: IslandModel.shared)
        let hostingView = NSHostingView(rootView: islandView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        let width: CGFloat = 700
        let height: CGFloat = 350
        
        let win = IslandOverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        
        win.contentView = hostingView
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.isRestorable = false 
        
        let originX = screen.frame.midX - (width / 2)
        let originY = screen.frame.maxY - height
        
        win.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        win.orderFrontRegardless()
        return win
    }
}
