import Cocoa

class SelectionView: NSView {
    var onSelect: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var selectionRect: NSRect = .zero

    private func log(_ msg: String, level: LogLevel = .info) {
        Task { await MainActor.run { LogManager.shared.log(msg, level: level) } }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)

        // Tell AppKit to use our cursor rects (calls resetCursorRects)
        window.invalidateCursorRects(for: self)
        // Force crosshair immediately — cursor rects only refresh on mouse move
        NSCursor.crosshair.set()

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        log("Capture overlay visible — waiting for mouse drag")
        needsDisplay = true
    }

    // Canonical AppKit hook — called by invalidateCursorRects
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // Called by the .cursorUpdate tracking area option on mouse enter
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Mouse events

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        needsDisplay = true
        log("Mouse down at (\(Int(startPoint!.x)), \(Int(startPoint!.y)))")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let w = Int(selectionRect.width)
        let h = Int(selectionRect.height)
        log("Mouse up — selection \(w)×\(h)")
        guard selectionRect.width > 5 && selectionRect.height > 5 else {
            log("Selection too small (\(w)×\(h)), cancelled", level: .error)
            onCancel?()
            return
        }
        onSelect?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            log("Capture cancelled (Escape)")
            onCancel?()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dim overlay
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)

        // Selection rect — clear the selected area so content shows through
        guard selectionRect.width > 0 && selectionRect.height > 0 else { return }
        ctx.clear(selectionRect)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(selectionRect.insetBy(dx: -0.75, dy: -0.75))

        let label = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        var labelY = selectionRect.minY - labelSize.height - 6
        if labelY < 4 { labelY = selectionRect.maxY + 6 }
        let labelX = max(4, min(selectionRect.midX - labelSize.width / 2,
                                bounds.maxX - labelSize.width - 4))
        (label as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }
}
