import Cocoa
import ScreenCaptureKit

class CaptureWindow: NSWindow {
    private var onCapture: ((Data) -> Void)?
    private var onError: ((String) -> Void)?
    private let captureScreen: NSScreen  // screen this window lives on

    init(onCapture: @escaping (Data) -> Void, onError: @escaping (String) -> Void) {
        self.onCapture = onCapture
        self.onError = onError
        // Snapshot the screen at init time — don't re-query later
        self.captureScreen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = captureScreen.frame
        super.init(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        isReleasedWhenClosed = false

        let selectionView = SelectionView(frame: CGRect(origin: .zero, size: screenFrame.size))
        // onSelect receives view-local coords (bottom-left origin, points, relative to window)
        selectionView.onSelect = { [self] viewRect in captureAfterClose(viewRect) }
        selectionView.onCancel = { [weak self] in self?.close() }
        contentView = selectionView
    }

    private func captureAfterClose(_ viewRect: NSRect) {
        Task { await log("Overlay closed — capturing region") }
        close()
        Task { await captureRegion(viewRect) }
    }

    private func captureRegion(_ viewRect: NSRect) async {
        let w = Int(viewRect.width)
        let h = Int(viewRect.height)
        guard w > 5 && h > 5 else {
            await log("Selection too small (\(w)×\(h))", level: .error)
            return
        }

        await log("Requesting screen content via ScreenCaptureKit…")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Match the SCDisplay to the screen this window was on
            let screenID = captureScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let display = content.displays.first(where: { $0.displayID == screenID })
                       ?? content.displays.first!

            let filter = SCContentFilter(display: display, excludingWindows: [])

            // Capture full display at native resolution
            let config = SCStreamConfiguration()
            config.width  = display.width
            config.height = display.height

            await log("Capturing full display (\(display.width)×\(display.height)px), cropping to \(w)×\(h) pts")

            let fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // viewRect is in view-local AppKit points (bottom-left origin, 0,0 = bottom-left of screen)
            // fullImage is in pixels, top-left origin, covering the same screen
            let screenH = captureScreen.frame.height          // points
            let scaleX  = CGFloat(fullImage.width)  / captureScreen.frame.width
            let scaleY  = CGFloat(fullImage.height) / screenH

            let cropRect = CGRect(
                x:      viewRect.minX               * scaleX,
                y:     (screenH - viewRect.maxY)    * scaleY,
                width:  viewRect.width              * scaleX,
                height: viewRect.height             * scaleY
            )

            await log("Crop rect: (\(Int(cropRect.minX)), \(Int(cropRect.minY))) \(Int(cropRect.width))×\(Int(cropRect.height))px")

            guard cropRect.minX >= 0, cropRect.minY >= 0,
                  cropRect.maxX <= CGFloat(fullImage.width),
                  cropRect.maxY <= CGFloat(fullImage.height) else {
                await log("Crop rect out of bounds — image: \(fullImage.width)×\(fullImage.height)", level: .error)
                return
            }

            guard let croppedImage = fullImage.cropping(to: cropRect) else {
                await log("CGImage.cropping returned nil", level: .error)
                return
            }

            let rep = NSBitmapImageRep(cgImage: croppedImage)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                await log("Failed to encode PNG", level: .error)
                return
            }

            await log("Capture succeeded (\(croppedImage.width)×\(croppedImage.height)px, \(data.count / 1024) KB)", level: .success)
            await MainActor.run {
                onCapture?(data)
                onCapture = nil
            }

        } catch {
            await log("ScreenCaptureKit error: \(error.localizedDescription)", level: .error)
            await MainActor.run {
                onError?("Screen capture failed: \(error.localizedDescription)")
            }
        }
    }

    private func log(_ message: String, level: LogLevel = .info) async {
        await MainActor.run { LogManager.shared.log(message, level: level) }
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}
