import AppKit
import PaintCore
import UniformTypeIdentifiers

enum Tool: String, CaseIterable {
    case brush = "Brush", pencil = "Pencil", eraser = "Eraser", fill = "Paint Bucket"
    case gradient = "Gradient", eyedropper = "Color Picker", line = "Line"
    case rectangle = "Rectangle", ellipse = "Ellipse", text = "Text"
    case select = "Rectangle Select", move = "Move Layer"

    var symbol: String {
        switch self {
        case .brush: return "paintbrush.pointed.fill"
        case .pencil: return "pencil.tip"
        case .eraser: return "eraser.fill"
        case .fill: return "drop.fill"
        case .gradient: return "square.lefthalf.filled"
        case .eyedropper: return "eyedropper"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .select: return "rectangle.dashed"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    var shortcut: String {
        switch self {
        case .brush: return "b"
        case .pencil: return "p"
        case .eraser: return "e"
        case .fill: return "f"
        case .gradient: return "g"
        case .eyedropper: return "i"
        case .line: return "l"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .text: return "t"
        case .select: return "s"
        case .move: return "m"
        }
    }

    var hint: String {
        switch self {
        case .brush, .pencil: return "Drag to paint · [ / ] brush size · Right-click uses secondary color"
        case .eraser: return "Drag to erase the active layer to transparency"
        case .fill: return "Click to fill connected pixels · Tolerance controls matching"
        case .gradient: return "Drag from primary to secondary color"
        case .eyedropper: return "Click to sample the visible image"
        case .line: return "Drag to draw a line · Shift snaps to 45°"
        case .rectangle, .ellipse: return "Drag to draw · Shift constrains proportions"
        case .text: return "Click to place text on the active layer"
        case .select: return "Drag a selection · Delete clears · ⌘K crops · Esc deselects"
        case .move: return "Drag to move all pixels on the active layer"
        }
    }
}

final class EditorController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var project = Project()
    var history = History()
    var projectURL: URL?
    var documentName = "Untitled"
    var tool = Tool.brush
    var primary = NSColor(srgbRed: 0.22, green: 0.48, blue: 1, alpha: 1)
    var secondary = NSColor.white
    var brushSize: CGFloat = 12
    var toolOpacity: CGFloat = 1
    var tolerance = 24
    var filledShapes = false
    var fontSize: CGFloat = 36
    var zoom: CGFloat = 1
    var refreshing = false
    var canvas: CanvasView!
    var scrollView: NSScrollView!
    var layersTable: NSTableView!
    var primaryWell: NSColorWell!
    var secondaryWell: NSColorWell!
    var brushSlider: NSSlider!
    var brushLabel: NSTextField!
    var toolOpacitySlider: NSSlider!
    var toleranceSlider: NSSlider!
    var fontSlider: NSSlider!
    var shapeCheck: NSButton!
    var layerOpacity: NSSlider!
    var blendPopup: NSPopUpButton!
    var layerName: NSTextField!
    var statusLabel: NSTextField!
    var sizeLabel: NSTextField!
    var zoomLabel: NSTextField!
    var titleLabel: NSTextField!
    var historyLabel: NSTextField!
    var undoButton: NSButton!
    var redoButton: NSButton!
    var toolButtons: [Tool: NSButton] = [:]
    var selectedLayer: Layer { project.layers[project.selected] }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Scottware PaintMac"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 1000, height: 690)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        buildInterface()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsFrameChangedNotifications = true
        DispatchQueue.main.async { self.fitCanvas(nil) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    func performEdit(_ name: String, _ edit: (inout Project) throws -> Void) {
        let before = project
        do {
            try edit(&project)
            history.record(before, name: name)
            refresh()
        } catch {
            project = before
            showError(error)
        }
    }

    func startGesture() {
        history.record(project, name: tool.rawValue)
    }

    func refresh(imageChanged: Bool = true) {
        refreshing = true
        defer { refreshing = false }
        if imageChanged { canvas.invalidateImage() }
        layoutCanvas()
        layersTable.reloadData()
        layersTable.selectRowIndexes(IndexSet(integer: project.layers.count - 1 - project.selected), byExtendingSelection: false)
        layerOpacity.doubleValue = Double(selectedLayer.opacity * 100)
        blendPopup.selectItem(withTitle: selectedLayer.blend.rawValue)
        layerName.stringValue = selectedLayer.name
        primaryWell.color = primary; secondaryWell.color = secondary
        brushSlider.doubleValue = Double(brushSize)
        brushLabel.stringValue = "Size  \(Int(brushSize)) px"
        toolOpacitySlider.doubleValue = Double(toolOpacity * 100)
        toleranceSlider.integerValue = tolerance
        fontSlider.doubleValue = Double(fontSize)
        shapeCheck.state = filledShapes ? .on : .off
        for (value, button) in toolButtons {
            button.state = value == tool ? .on : .off
            button.contentTintColor = value == tool ? .systemBlue : .labelColor
            button.layer?.backgroundColor = value == tool ? NSColor.systemBlue.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
        }
        titleLabel.stringValue = documentName
        window?.title = "\(documentName) — Scottware PaintMac"
        window?.isDocumentEdited = history.isDirty
        window?.representedURL = projectURL
        sizeLabel.stringValue = "\(project.width) × \(project.height) px  ·  \(project.layers.count) layer\(project.layers.count == 1 ? "" : "s")"
        zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
        statusLabel.stringValue = tool.hint
        undoButton.isEnabled = !history.past.isEmpty
        redoButton.isEnabled = !history.future.isEmpty
        historyLabel.stringValue = history.past.suffix(5).reversed().enumerated().map {
            ($0.offset == 0 ? "↳  " : "    ") + $0.element.name
        }.joined(separator: "\n")
        if history.past.isEmpty { historyLabel.stringValue = "Your next idea starts here." }
    }

    func layoutCanvas() {
        guard let canvas, let scrollView else { return }
        let size = scrollView.contentSize
        canvas.frame.size = NSSize(width: max(size.width, CGFloat(project.width) * zoom + 96),
                                   height: max(size.height, CGFloat(project.height) * zoom + 96))
        canvas.needsDisplay = true
    }

    @objc func viewportChanged(_ note: Notification) { layoutCanvas() }

    func setZoom(_ value: CGFloat) {
        let center = CGPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        let imageCenter = canvas.imagePoint(center)
        zoom = max(0.05, min(16, value))
        layoutCanvas()
        let origin = canvas.imageRect.origin
        let visible = scrollView.contentSize
        scrollView.contentView.scroll(to: CGPoint(x: origin.x + imageCenter.x * zoom - visible.width / 2,
                                                   y: origin.y + imageCenter.y * zoom - visible.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(zoom * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom(zoom / 1.25) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }
    @objc func fitCanvas(_ sender: Any?) {
        let size = scrollView.contentSize
        setZoom(min(1, min(max(100, size.width - 96) / CGFloat(project.width),
                           max(100, size.height - 96) / CGFloat(project.height))))
    }

    func chooseTool(_ tool: Tool) {
        self.tool = tool
        refresh(imageChanged: false)
        window?.makeFirstResponder(canvas)
    }

    @objc func toolPressed(_ sender: NSButton) { chooseTool(Tool.allCases[sender.tag]) }
    @objc func colorChanged(_ sender: NSColorWell) {
        if sender === primaryWell { primary = sender.color } else { secondary = sender.color }
    }
    @objc func swapColors(_ sender: Any?) { swap(&primary, &secondary); refresh(imageChanged: false) }
    @objc func resetColors(_ sender: Any?) { primary = .black; secondary = .white; refresh(imageChanged: false) }
    @objc func swatchPressed(_ sender: NSButton) {
        primary = Self.palette[sender.tag]
        refresh(imageChanged: false)
    }
    @objc func brushChanged(_ sender: NSSlider) {
        brushSize = CGFloat(sender.doubleValue.rounded())
        brushLabel.stringValue = "Size  \(Int(brushSize)) px"
    }
    @objc func opacityChanged(_ sender: NSSlider) { toolOpacity = CGFloat(sender.doubleValue / 100) }
    @objc func toleranceChanged(_ sender: NSSlider) { tolerance = sender.integerValue }
    @objc func fontChanged(_ sender: NSSlider) { fontSize = CGFloat(sender.integerValue) }
    @objc func shapeChanged(_ sender: NSButton) { filledShapes = sender.state == .on }

    @objc func undoAction(_ sender: Any?) {
        if let previous = history.undo(project) { project = previous; refresh() }
    }
    @objc func redoAction(_ sender: Any?) {
        if let next = history.redo(project) { project = next; refresh() }
    }

    @objc func addLayer(_ sender: Any?) { performEdit("Add layer") { try $0.addLayer(name: "Layer \($0.layers.count + 1)") } }
    @objc func duplicateLayer(_ sender: Any?) {
        performEdit("Duplicate layer") { project in
            var duplicate = project.layers[project.selected]
            try project.addLayer(name: duplicate.name + " copy", raster: duplicate.raster)
            duplicate.id = UUID(); duplicate.name += " copy"
            project.layers[project.selected] = duplicate
        }
    }
    @objc func deleteLayer(_ sender: Any?) {
        guard project.layers.count > 1 else { NSSound.beep(); return }
        performEdit("Delete layer") { project in
            project.layers.remove(at: project.selected)
            project.selected = min(project.selected, project.layers.count - 1)
        }
    }
    @objc func layerUp(_ sender: Any?) { reorderLayer(delta: 1) }
    @objc func layerDown(_ sender: Any?) { reorderLayer(delta: -1) }
    func reorderLayer(delta: Int) {
        guard project.layers.indices.contains(project.selected + delta) else { return }
        performEdit("Reorder layer") { project in
            project.layers.swapAt(project.selected, project.selected + delta)
            project.selected += delta
        }
    }
    @objc func flattenImage(_ sender: Any?) {
        performEdit("Flatten image") { project in
            project.layers = [Layer(name: "Flattened", raster: project.composite())]
            project.selected = 0
        }
    }
    @objc func visibilityChanged(_ sender: NSButton) {
        let index = sender.tag
        performEdit("Layer visibility") { $0.layers[index].visible = sender.state == .on }
    }
    @objc func layerOpacityChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue / 100)
        guard value != selectedLayer.opacity else { return }
        performEdit("Layer opacity") { $0.layers[$0.selected].opacity = value }
    }
    @objc func blendChanged(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem, let blend = Blend(rawValue: title), blend != selectedLayer.blend else { return }
        performEdit("Layer blend mode") { $0.layers[$0.selected].blend = blend }
    }
    @objc func renameLayer(_ sender: NSTextField) {
        let name = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != selectedLayer.name else { refresh(imageChanged: false); return }
        performEdit("Rename layer") { $0.layers[$0.selected].name = name }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { project.layers.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let index = project.layers.count - row - 1
        let layer = project.layers[index]
        let eye = NSButton(checkboxWithTitle: "", target: self, action: #selector(visibilityChanged))
        eye.state = layer.visible ? .on : .off; eye.tag = index
        eye.toolTip = "Show or hide layer"
        let thumbnail = NSImageView()
        thumbnail.image = NSImage(cgImage: layer.raster.image, size: NSSize(width: project.width, height: project.height))
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.backgroundColor = NSColor(white: 0.35, alpha: 1).cgColor
        thumbnail.layer?.cornerRadius = 4
        thumbnail.widthAnchor.constraint(equalToConstant: 40).isActive = true
        thumbnail.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let title = label(layer.name, size: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let detail = label("\(Int(layer.opacity * 100))% · \(layer.blend.rawValue)", size: 10)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [title, detail]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 3
        let stack = NSStackView(views: [eye, thumbnail, text]); stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 4, bottom: 5, right: 4)
        return stack
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing, layersTable.selectedRow >= 0 else { return }
        project.selected = project.layers.count - 1 - layersTable.selectedRow
        refresh(imageChanged: false)
    }

    @objc override func selectAll(_ sender: Any?) { project.selection = project.bounds; canvas.needsDisplay = true }
    @objc func deselect(_ sender: Any?) { project.selection = nil; canvas.needsDisplay = true }
    @objc func deletePixels(_ sender: Any?) {
        performEdit("Clear pixels") { project in
            let area = project.selection ?? project.bounds
            project.layers[project.selected].raster.paint { $0.clear(area) }
        }
    }
    @objc func crop(_ sender: Any?) {
        guard project.selection != nil else { NSSound.beep(); return }
        performEdit("Crop to selection") { $0.crop() }; fitCanvas(nil)
    }
    @objc func rotate(_ sender: Any?) { performEdit("Rotate 90° clockwise") { $0.rotate() }; fitCanvas(nil) }
    @objc func flipHorizontal(_ sender: Any?) { performEdit("Flip horizontally") { $0.flip(horizontal: true) } }
    @objc func flipVertical(_ sender: Any?) { performEdit("Flip vertically") { $0.flip(horizontal: false) } }
    @objc func applyEffect(_ sender: NSMenuItem) {
        let effect = Effect.allCases[sender.tag]
        performEdit(effect.rawValue) { project in
            let result = try project.layers[project.selected].raster.effect(effect)
            if let selection = project.selection {
                let bounds = project.bounds
                project.layers[project.selected].raster.paint { context in
                    context.clip(to: selection)
                    context.setBlendMode(.copy)
                    Raster.draw(result.image, in: bounds, context: context)
                }
            } else { project.layers[project.selected].raster = result }
        }
    }

    @objc func copyPixels(_ sender: Any?) {
        copyRaster(selectedLayer.raster)
    }
    @objc func copyMerged(_ sender: Any?) { copyRaster(project.composite()) }
    private func copyRaster(_ image: Raster) {
        do {
            var raster = image
            if let area = project.selection { raster = raster.cropped(to: area) }
            let png = try raster.encoded()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
        } catch { showError(error) }
    }
    @objc func cutPixels(_ sender: Any?) { copyPixels(sender); deletePixels(sender) }
    @objc func pastePixels(_ sender: Any?) {
        guard let data = NSPasteboard.general.data(forType: .png) ?? NSPasteboard.general.data(forType: .tiff) else {
            NSSound.beep(); return
        }
        do { try insertImage(Raster.load(data: data), name: "Pasted image") }
        catch { showError(error) }
    }

    func insertImage(_ image: Raster, name: String) throws {
        var raster = Raster(width: project.width, height: project.height)
        let point = project.selection?.origin ?? .zero
        raster.paint { Raster.draw(image.image, in: CGRect(origin: point, size: image.bounds.size), context: $0) }
        let before = project
        try project.addLayer(name: name, raster: raster)
        project.selection = nil
        history.record(before, name: "Import image layer")
        refresh()
    }

    func placeText(at point: CGPoint) {
        guard let text = requestText(title: "Add text", message: "Text is painted onto the active layer. Undo removes it.", initial: "", multiline: true), !text.isEmpty else { return }
        let color = primary.withAlphaComponent(primary.alphaComponent * toolOpacity)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: color]
        performEdit("Text") { project in
            let selection = project.selection
            project.layers[project.selected].raster.paint { context in
                if let selection { context.clip(to: selection) }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                (text as NSString).draw(at: point, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    func confirmDiscard() -> Bool {
        guard history.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(documentName)?"
        alert.informativeText = "Save a Scottware PaintMac project to keep your layers editable."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveProject(forceChoose: false)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmDiscard() }

    @objc func newDocument(_ sender: Any?) {
        guard confirmDiscard(), let dimensions = askDimensions(title: "New image", width: 1000, height: 700, newDocument: true) else { return }
        project = Project(width: dimensions.0, height: dimensions.1, transparent: dimensions.2)
        history = History(); projectURL = nil; documentName = "Untitled"
        refresh(); fitCanvas(nil)
    }

    @objc func resizeImage(_ sender: Any?) {
        guard let dimensions = askDimensions(title: "Resize image", width: project.width, height: project.height, newDocument: false) else { return }
        performEdit("Resize image") { try $0.resize(width: dimensions.0, height: dimensions.1) }
        fitCanvas(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, UTType(filenameExtension: "paintmac") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Open an image or an editable Scottware PaintMac project."
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard confirmDiscard() else { return }
        do {
            let isProject = url.pathExtension.lowercased() == "paintmac"
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let opened = try isProject ? Project.decode(data) : Project(raster: Raster.load(data: data), name: url.deletingPathExtension().lastPathComponent)
            project = opened
            history = History(saved: isProject)
            projectURL = isProject ? url : nil
            documentName = url.deletingPathExtension().lastPathComponent
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            refresh(); fitCanvas(nil)
        } catch { showError(error) }
    }

    @objc func importLayer(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Import an image as a new layer at its original size."
        if panel.runModal() == .OK, let url = panel.url {
            do { try insertImage(Raster.load(data: Data(contentsOf: url)), name: url.deletingPathExtension().lastPathComponent) }
            catch { showError(error) }
        }
    }

    @objc func save(_ sender: Any?) { _ = saveProject(forceChoose: false) }
    @objc func saveAs(_ sender: Any?) { _ = saveProject(forceChoose: true) }
    @discardableResult
    func saveProject(forceChoose: Bool) -> Bool {
        var destination = projectURL
        if forceChoose || destination == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "paintmac") ?? .data]
            panel.nameFieldStringValue = documentName + ".paintmac"
            panel.message = "Save an editable project with all layers."
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        do {
            let url = destination!
            try project.encoded().write(to: url, options: .atomic)
            projectURL = url; documentName = url.deletingPathExtension().lastPathComponent
            history.markSaved(); refresh(imageChanged: false)
            return true
        } catch { showError(error); return false }
    }

    @objc func exportPNG(_ sender: Any?) { export(type: .png) }
    @objc func exportJPEG(_ sender: Any?) { export(type: .jpeg) }
    func export(type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = documentName + (type == .png ? ".png" : ".jpg")
        panel.message = type == .png ? "Export visible layers with transparency." : "Export visible layers on a white background."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try project.composite(whiteBackground: type == .jpeg).encoded(type: type).write(to: url, options: .atomic) }
        catch { showError(error) }
    }

    func askDimensions(title: String, width: Int, height: Int, newDocument: Bool) -> (Int, Int, Bool)? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = newDocument ? "Choose your canvas dimensions in pixels." : "Resamples every layer. Enter both dimensions to control the aspect ratio."
        alert.addButton(withTitle: newDocument ? "Create" : "Resize")
        alert.addButton(withTitle: "Cancel")
        let w = NSTextField(string: "\(width)"), h = NSTextField(string: "\(height)")
        let transparent = NSButton(checkboxWithTitle: "Transparent background", target: nil, action: nil)
        let stack = NSStackView(views: [label("Width", size: 12), w, label("Height", size: 12), h])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        if newDocument { stack.addArrangedSubview(transparent) }
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: newDocument ? 150 : 120)
        w.widthAnchor.constraint(equalToConstant: 280).isActive = true
        h.widthAnchor.constraint(equalToConstant: 280).isActive = true
        alert.accessoryView = stack
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                guard let width = Int(w.stringValue), let height = Int(h.stringValue) else { throw PaintError.message("Enter whole-number pixel dimensions.") }
                try Raster.validateSize(width: width, height: height)
                return (width, height, transparent.state == .on)
            } catch { showError(error) }
        }
        return nil
    }

    func requestText(title: String, message: String, initial: String, multiline: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "Add Text"); alert.addButton(withTitle: "Cancel")
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        text.font = .systemFont(ofSize: 16)
        text.isRichText = false; text.string = initial
        let scroller = NSScrollView(frame: text.frame)
        scroller.documentView = text; scroller.hasVerticalScroller = true
        alert.accessoryView = scroller
        alert.window.initialFirstResponder = text
        return alert.runModal() == .alertFirstButtonReturn ? text.string : nil
    }
}
