import AppKit
import PaintCore

final class CanvasView: NSView {
    unowned let editor: EditorController
    private var cachedImage: CGImage?
    private var anchor: CGPoint?
    private var lastPoint: CGPoint?
    private var originalRaster: Raster?
    private var gestureColor = NSColor.black
    private var tracking: NSTrackingArea?
    private var panAnchor: CGPoint?
    private var panOrigin: CGPoint?
    private var spaceHeld = false

    init(editor: EditorController) {
        self.editor = editor
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var imageRect: CGRect {
        let size = CGSize(width: CGFloat(editor.project.width) * editor.zoom, height: CGFloat(editor.project.height) * editor.zoom)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - imageRect.minX) / editor.zoom, y: (point.y - imageRect.minY) / editor.zoom)
    }

    func point(for event: NSEvent) -> CGPoint { imagePoint(convert(event.locationInWindow, from: nil)) }
    func invalidateImage() { cachedImage = nil; needsDisplay = true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    override func resetCursorRects() { addCursorRect(visibleRect, cursor: spaceHeld ? .openHand : .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor(srgbRed: 0.105, green: 0.115, blue: 0.135, alpha: 1).setFill()
        bounds.fill()
        let rect = imageRect
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 3), blur: 18, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setFillColor(NSColor(white: 0.78, alpha: 1).cgColor)
        context.fill(rect)
        context.restoreGState()
        context.saveGState()
        context.clip(to: rect)
        let visible = rect.intersection(dirtyRect)
        let tile: CGFloat = 10
        if !visible.isNull {
            let startX = Int(floor((visible.minX - rect.minX) / tile))
            let endX = Int(ceil((visible.maxX - rect.minX) / tile))
            let startY = Int(floor((visible.minY - rect.minY) / tile))
            let endY = Int(ceil((visible.maxY - rect.minY) / tile))
            context.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
            for y in startY...max(startY, endY) { for x in startX...max(startX, endX) where (x + y) % 2 == 0 {
                context.fill(CGRect(x: rect.minX + CGFloat(x) * tile, y: rect.minY + CGFloat(y) * tile, width: tile, height: tile))
            } }
        }
        if cachedImage == nil { cachedImage = editor.project.composite().image }
        context.interpolationQuality = editor.zoom >= 2 ? .none : .high
        if let image = cachedImage { Raster.draw(image, in: rect, context: context) }
        if editor.zoom >= 8 {
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.15).cgColor)
            context.setLineWidth(0.5)
            let imageVisible = CGRect(x: (visible.minX - rect.minX) / editor.zoom, y: (visible.minY - rect.minY) / editor.zoom,
                                      width: visible.width / editor.zoom, height: visible.height / editor.zoom)
            if !visible.isNull {
                for x in max(0, Int(imageVisible.minX))...min(editor.project.width, Int(imageVisible.maxX) + 1) {
                    let position = rect.minX + CGFloat(x) * editor.zoom
                    context.move(to: CGPoint(x: position, y: visible.minY)); context.addLine(to: CGPoint(x: position, y: visible.maxY))
                }
                for y in max(0, Int(imageVisible.minY))...min(editor.project.height, Int(imageVisible.maxY) + 1) {
                    let position = rect.minY + CGFloat(y) * editor.zoom
                    context.move(to: CGPoint(x: visible.minX, y: position)); context.addLine(to: CGPoint(x: visible.maxX, y: position))
                }
                context.strokePath()
            }
        }
        context.restoreGState()
        if let selection = editor.project.selection {
            let selectedRect = CGRect(x: rect.minX + selection.minX * editor.zoom, y: rect.minY + selection.minY * editor.zoom,
                                      width: selection.width * editor.zoom, height: selection.height * editor.zoom)
            context.setLineWidth(1)
            context.setStrokeColor(NSColor.white.cgColor)
            context.stroke(selectedRect)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.setStrokeColor(NSColor.black.cgColor)
            context.stroke(selectedRect)
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if spaceHeld || event.buttonNumber == 2 {
            panAnchor = event.locationInWindow
            panOrigin = editor.scrollView.contentView.bounds.origin
            NSCursor.closedHand.set()
            return
        }
        let point = point(for: event)
        guard editor.project.bounds.contains(point) else { return }
        let tool = editor.tool
        if tool == .eyedropper || event.modifierFlags.contains(.option) {
            editor.primary = editor.project.composite().color(at: point)
            editor.refresh(imageChanged: false)
            return
        }
        if tool != .select && !editor.selectedLayer.visible {
            editor.statusLabel.stringValue = "This layer is hidden. Enable its checkbox before painting."
            NSSound.beep()
            return
        }
        if tool == .text { editor.placeText(at: point); return }
        anchor = point; lastPoint = point
        let chosen = event.buttonNumber == 1 ? editor.secondary : editor.primary
        gestureColor = chosen.withAlphaComponent(chosen.alphaComponent * editor.toolOpacity)
        if tool == .select {
            editor.project.selection = nil
            needsDisplay = true
            return
        }
        editor.startGesture()
        originalRaster = editor.selectedLayer.raster
        if tool == .fill {
            let clip = editor.project.selection
            editor.project.layers[editor.project.selected].raster.floodFill(at: point, color: gestureColor, tolerance: editor.tolerance, clip: clip)
            finishGesture()
        } else if [.brush, .pencil, .eraser].contains(tool) {
            stroke(from: point, to: point)
        }
    }

    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func otherMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    private func stroke(from: CGPoint, to: CGPoint) {
        let selection = editor.project.selection
        let pencil = editor.tool == .pencil
        let start = pencil ? CGPoint(x: floor(from.x) + 0.5, y: floor(from.y) + 0.5) : from
        let end = pencil ? CGPoint(x: floor(to.x) + 0.5, y: floor(to.y) + 0.5) : to
        editor.project.layers[editor.project.selected].raster.stroke(from: start, to: end, color: gestureColor,
                                                                    size: pencil ? 1 : editor.brushSize,
                                                                    erasing: editor.tool == .eraser,
                                                                    pixelated: pencil, clip: selection)
        invalidateImage()
    }

    override func mouseDragged(with event: NSEvent) {
        if let panAnchor, let panOrigin {
            let delta = CGPoint(x: event.locationInWindow.x - panAnchor.x, y: event.locationInWindow.y - panAnchor.y)
            editor.scrollView.contentView.scroll(to: CGPoint(x: panOrigin.x - delta.x, y: panOrigin.y + delta.y))
            editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
            return
        }
        guard let anchor else { return }
        let point = point(for: event)
        if [.brush, .pencil, .eraser].contains(editor.tool) {
            stroke(from: lastPoint ?? anchor, to: point)
            lastPoint = point
        } else { preview(to: point, constrained: event.modifierFlags.contains(.shift)) }
        mouseMoved(with: event)
    }

    private func preview(to proposed: CGPoint, constrained: Bool) {
        guard let start = anchor else { return }
        var end = proposed
        let dx = end.x - start.x, dy = end.y - start.y
        if constrained {
            if editor.tool == .line {
                let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
                let length = hypot(dx, dy)
                end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            } else if [.rectangle, .ellipse, .select].contains(editor.tool) {
                let side = max(abs(dx), abs(dy))
                end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
            }
        }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        if editor.tool == .select {
            let area = rect.intersection(editor.project.bounds).integral
            editor.project.selection = area.width >= 1 && area.height >= 1 ? area : nil
            needsDisplay = true
            return
        }
        guard let original = originalRaster else { return }
        var raster = original
        let selection = editor.project.selection
        let tool = editor.tool
        if tool == .move {
            raster = Raster(width: original.width, height: original.height)
            let target = CGRect(x: (end.x - start.x).rounded(), y: (end.y - start.y).rounded(), width: CGFloat(original.width), height: CGFloat(original.height))
            raster.paint { Raster.draw(original.image, in: target, context: $0) }
        } else {
            raster.paint { context in
                if let selection { context.clip(to: selection) }
                context.setLineWidth(editor.brushSize)
                context.setLineCap(.round)
                context.setStrokeColor(gestureColor.cgColor)
                context.setFillColor(gestureColor.cgColor)
                switch tool {
                case .line:
                    context.move(to: start); context.addLine(to: end); context.strokePath()
                case .rectangle:
                    if editor.filledShapes { context.fill(rect) } else { context.stroke(rect) }
                case .ellipse:
                    if editor.filledShapes { context.fillEllipse(in: rect) } else { context.strokeEllipse(in: rect) }
                case .gradient:
                    let secondary = editor.secondary.withAlphaComponent(editor.secondary.alphaComponent * editor.toolOpacity)
                    let colors = [gestureColor.cgColor, secondary.cgColor] as CFArray
                    if let gradient = CGGradient(colorsSpace: Raster.colorSpace, colors: colors, locations: [0, 1]) {
                        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    }
                default: break
                }
            }
        }
        editor.project.layers[editor.project.selected].raster = raster
        invalidateImage()
    }

    override func mouseUp(with event: NSEvent) {
        if panAnchor != nil {
            panAnchor = nil; panOrigin = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        guard anchor != nil else { return }
        if ![.brush, .pencil, .eraser, .fill].contains(editor.tool) {
            preview(to: point(for: event), constrained: event.modifierFlags.contains(.shift))
        }
        finishGesture()
    }

    private func finishGesture() {
        anchor = nil; lastPoint = nil; originalRaster = nil
        editor.refresh()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = point(for: event)
        if editor.project.bounds.contains(point) {
            var position = "x: \(Int(point.x))  y: \(Int(point.y))"
            if let area = editor.project.selection { position += "  ·  Selection \(Int(area.width)) × \(Int(area.height))" }
            editor.statusLabel.stringValue = position + "   ·   " + editor.tool.hint
        }
    }

    override func mouseExited(with event: NSEvent) { editor.statusLabel.stringValue = editor.tool.hint }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            editor.setZoom(editor.zoom * pow(1.015, event.scrollingDeltaY))
        } else { super.scrollWheel(with: event) }
    }

    override func magnify(with event: NSEvent) { editor.setZoom(editor.zoom * (1 + event.magnification)) }

    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) else { super.keyDown(with: event); return }
        if event.keyCode == 49 { spaceHeld = true; window?.invalidateCursorRects(for: self); return }
        if event.keyCode == 53 { editor.deselect(nil); return }
        if event.keyCode == 51 || event.keyCode == 117 { editor.deletePixels(nil); return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "[": editor.brushSize = max(1, editor.brushSize - 2); editor.refresh(imageChanged: false)
        case "]": editor.brushSize = min(200, editor.brushSize + 2); editor.refresh(imageChanged: false)
        case "x": editor.swapColors(nil)
        case "d": editor.resetColors(nil)
        default:
            if let tool = Tool.allCases.first(where: { $0.shortcut == event.charactersIgnoringModifiers?.lowercased() }) {
                editor.chooseTool(tool)
            } else { super.keyDown(with: event) }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false; window?.invalidateCursorRects(for: self) }
        else { super.keyUp(with: event) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first else { return false }
        editor.open(url)
        return true
    }
}
