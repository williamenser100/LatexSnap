import Cocoa
import CoreGraphics
import SwiftUI
import ScreenCaptureKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var captureWindow: CaptureWindow?
    private var settingsWindowController: NSWindowController?
    private var logWindowController: NSWindowController?
    /// True while the region-selection overlay is open (blocks starting another capture until dismissed).
    private var isCaptureOverlayActive = false
    /// In-flight Claude API calls (menu bar icon stays busy until all finish).
    private var pendingAPIRequests = 0

    private var log: LogManager { LogManager.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        hotkeyManager = HotkeyManager { [weak self] in
            DispatchQueue.main.async { self?.startCapture() }
        }
        hotkeyManager.register()
        log.log("LatexSnap started. Hotkey: ⌘⇧⌃L")
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                await MainActor.run { log.log("Screen Recording permission: granted ✓", level: .success) }
            } catch {
                await MainActor.run {
                    let preflight = CGPreflightScreenCaptureAccess()
                    log.log("Screen Recording check failed (\(error.localizedDescription), preflight: \(preflight ? "true" : "false"))", level: .error)
                    log.log("If permission is already enabled, ensure it is enabled for this exact app copy (/Applications) and relaunch app.", level: .info)
                }
            }
        }
        if KeychainHelper.apiKey == nil {
            log.log("No API key found — opening Settings", level: .error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openSettings() }
        } else {
            log.log("API key loaded from Keychain ✓", level: .success)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = xiMenuBarImage()
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "LatexSnap — ⌘⇧⌃L to capture"
            button.setAccessibilityLabel("LatexSnap")
        }
        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture LaTeX  ⌘⇧⌃L", action: #selector(startCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem.separator())
        let logItem = NSMenuItem(title: "Show Log…", action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LatexSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func startCapture() {
        // Trigger system prompt when needed before starting capture.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            if !CGPreflightScreenCaptureAccess() {
                log.log("Screen Recording not granted for this app copy. Open System Settings → Privacy & Security → Screen & System Audio Recording.", level: .error)
                return
            }
        }
        guard !isCaptureOverlayActive else {
            log.log("Capture overlay already open — finish or cancel (Esc) first")
            return
        }
        guard KeychainHelper.apiKey != nil else {
            log.log("No API key — cannot capture", level: .error)
            openSettings()
            return
        }
        log.log("Hotkey triggered — opening capture overlay")
        isCaptureOverlayActive = true
        captureWindow = CaptureWindow(
            onCapture: { [weak self] imageData in self?.processCapture(imageData) },
            onError:   { [weak self] msg in
                self?.log.log("Capture error: \(msg)", level: .error)
                self?.syncMenuBarIconWithAPIActivity()
            },
            onEnded: { [weak self] in
                self?.isCaptureOverlayActive = false
                self?.captureWindow = nil
            }
        )
        NSApp.activate(ignoringOtherApps: true)
        captureWindow?.makeKeyAndOrderFront(nil)
    }

    private func processCapture(_ imageData: Data) {
        pendingAPIRequests += 1
        if pendingAPIRequests == 1 {
            setMenuBarIcon("ellipsis.circle")
        }
        log.log("Screenshot captured (\(imageData.count / 1024) KB) — calling Claude API…")
        Task {
            defer {
                DispatchQueue.main.async {
                    self.pendingAPIRequests -= 1
                    if self.pendingAPIRequests < 0 { self.pendingAPIRequests = 0 }
                    self.syncMenuBarIconWithAPIActivity()
                }
            }
            do {
                let latex = try await ClaudeAPIClient.convertToLatex(imageData: imageData)
                await MainActor.run {
                    if latex.isEmpty {
                        log.log("No math expression detected — clipboard unchanged", level: .error)
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(latex, forType: .string)
                        log.log("LaTeX copied to clipboard ✓", level: .success)
                        log.log("  → \(latex.prefix(120))", level: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    log.log("API error: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func syncMenuBarIconWithAPIActivity() {
        if pendingAPIRequests > 0 {
            setMenuBarIcon("ellipsis.circle")
        } else {
            setMenuBarIcon("function")
        }
    }

    /// Drawn as a template image so layout matches SF Symbol items (size + vertical alignment in the status bar).
    private func xiMenuBarImage() -> NSImage {
        let canvas: CGFloat = 28
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()
        defer { image.unlockFocus() }

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        func font(at size: CGFloat) -> NSFont {
            NSFont(name: "TimesNewRomanPS-BoldMT", size: size)
                ?? NSFont(name: "Times New Roman Bold", size: size)
                ?? NSFont(name: "Times-Bold", size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .bold)
        }

        let inner = canvas * 0.9
        var lo: CGFloat = 10
        var hi: CGFloat = 28
        var best: CGFloat = lo
        while hi - lo > 0.15 {
            let mid = (lo + hi) * 0.5
            let f = font(at: mid)
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .paragraphStyle: paragraph]
            let b = ("Ξ" as NSString).boundingRect(
                with: NSSize(width: inner, height: inner),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            if b.width <= inner && b.height <= inner {
                best = mid
                lo = mid
            } else {
                hi = mid
            }
        }

        let f = font(at: best)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: f,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let drawRect = NSRect(
            x: (canvas - inner) * 0.5,
            y: (canvas - inner) * 0.5,
            width: inner,
            height: inner
        )
        ("Ξ" as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)

        image.isTemplate = true
        return image
    }

    private func statusBarSymbolConfiguration() -> NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
    }

    private func setMenuBarIcon(_ symbolName: String) {
        guard let button = statusItem.button else { return }
        let symConfig = statusBarSymbolConfiguration()
        if symbolName == "function" {
            button.image = xiMenuBarImage()
        } else {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LatexSnap")?
                .withSymbolConfiguration(symConfig)
        }
        button.attributedTitle = NSAttributedString(string: "")
    }

    @objc func openLog() {
        if logWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "LatexSnap Log"
            window.contentView = NSHostingView(rootView: LogWindowView())
            window.center()
            window.isReleasedWhenClosed = false
            logWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        logWindowController?.showWindow(nil)
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 170),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "LatexSnap Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }
}
