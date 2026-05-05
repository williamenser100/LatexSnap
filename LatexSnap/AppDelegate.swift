import Cocoa
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
                    log.log("Screen Recording permission: NOT granted — enable LatexSnap in System Settings → Privacy & Security → Screen & System Audio Recording, then restart.", level: .error)
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
            button.attributedTitle = xiTitle()
            button.toolTip = "LatexSnap — ⌘⇧⌃L to capture"
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

    private func xiTitle() -> NSAttributedString {
        let font = NSFont(name: "TimesNewRomanPS-BoldMT", size: 17)
            ?? NSFont(name: "Times New Roman Bold", size: 17)
            ?? NSFont(name: "Times-Bold", size: 17)
            ?? NSFont.systemFont(ofSize: 17, weight: .bold)
        return NSAttributedString(string: "Ξ", attributes: [
            .font: font,
            .foregroundColor: NSColor.controlTextColor
        ])
    }

    private func setMenuBarIcon(_ symbolName: String) {
        guard let button = statusItem.button else { return }
        if symbolName == "function" {
            button.image = nil
            button.attributedTitle = xiTitle()
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LatexSnap")
        }
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
