import AppKit
import PaintCore

@main
final class PaintMacApp: NSObject, NSApplicationDelegate {
    var editor: EditorController!

    static func main() {
        let app = NSApplication.shared
        let delegate = PaintMacApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--smoke-test") {
            app.finishLaunching()
            delegate.runUISmokeCheck()
            return
        }
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        editor = EditorController()
        installMenus()
        editor.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A closed window has already completed its save prompt.
        guard editor?.window?.isVisible == true else { return .terminateNow }
        return editor.confirmDiscard() ? .terminateNow : .terminateCancel
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let filename = filenames.first else { sender.reply(toOpenOrPrint: .failure); return }
        if editor == nil {
            DispatchQueue.main.async { self.editor.open(URL(fileURLWithPath: filename)) }
        } else { editor.open(URL(fileURLWithPath: filename)) }
        sender.reply(toOpenOrPrint: .success)
    }

    func installMenus() {
        let menu = NSMenu()
        NSApp.mainMenu = menu
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu; menu.addItem(item)
            return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", shift: Bool = false, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target ?? editor
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            menu.addItem(item)
        }
        let app = submenu("Scottware PaintMac")
        item(app, "About Scottware PaintMac", #selector(about), target: self)
        app.addItem(.separator())
        item(app, "Hide Scottware PaintMac", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        app.addItem(.separator())
        item(app, "Quit Scottware PaintMac", #selector(NSApplication.terminate(_:)), "q", target: NSApp)

        let file = submenu("File")
        item(file, "New…", #selector(EditorController.newDocument(_:)), "n")
        item(file, "Open…", #selector(EditorController.openDocument(_:)), "o")
        item(file, "Import as Layer…", #selector(EditorController.importLayer(_:)), "o", shift: true)
        file.addItem(.separator())
        item(file, "Save Project", #selector(EditorController.save(_:)), "s")
        item(file, "Save Project As…", #selector(EditorController.saveAs(_:)), "s", shift: true)
        file.addItem(.separator())
        item(file, "Export PNG…", #selector(EditorController.exportPNG(_:)), "e", shift: true)
        item(file, "Export JPEG…", #selector(EditorController.exportJPEG(_:)))
        file.addItem(.separator())
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w", target: editor.window)

        let edit = submenu("Edit")
        item(edit, "Undo", #selector(undo(_:)), "z", target: self)
        item(edit, "Redo", #selector(redo(_:)), "z", shift: true, target: self)
        edit.addItem(.separator())
        // Route clipboard and selection to text fields when they are first responder.
        for (title, action, key) in [("Cut", #selector(cut(_:)), "x"), ("Copy", #selector(copy(_:)), "c"),
                                    ("Paste", #selector(paste(_:)), "v"), ("Select All", #selector(selectAll(_:)), "a")] {
            item(edit, title, action, key, target: self)
        }
        item(edit, "Copy Merged", #selector(EditorController.copyMerged(_:)), "c", shift: true)
        item(edit, "Deselect", #selector(EditorController.deselect(_:)), "d")
        item(edit, "Clear Pixels", #selector(EditorController.deletePixels(_:)))

        let image = submenu("Image")
        item(image, "Resize Image…", #selector(EditorController.resizeImage(_:)), "r", shift: true)
        item(image, "Crop to Selection", #selector(EditorController.crop(_:)), "k")
        image.addItem(.separator())
        item(image, "Rotate 90° Clockwise", #selector(EditorController.rotate(_:)))
        item(image, "Flip Horizontal", #selector(EditorController.flipHorizontal(_:)))
        item(image, "Flip Vertical", #selector(EditorController.flipVertical(_:)))
        image.addItem(.separator())
        item(image, "Flatten Image", #selector(EditorController.flattenImage(_:)))

        let layers = submenu("Layers")
        item(layers, "Add Layer", #selector(EditorController.addLayer(_:)), "n", shift: true)
        item(layers, "Duplicate Layer", #selector(EditorController.duplicateLayer(_:)), "d", shift: true)
        item(layers, "Delete Layer", #selector(EditorController.deleteLayer(_:)))
        layers.addItem(.separator())
        item(layers, "Move Layer Up", #selector(EditorController.layerUp(_:)))
        item(layers, "Move Layer Down", #selector(EditorController.layerDown(_:)))

        let effects = submenu("Effects")
        for (index, effect) in Effect.allCases.enumerated() {
            let item = NSMenuItem(title: effect.rawValue, action: #selector(EditorController.applyEffect(_:)), keyEquivalent: "")
            item.target = editor; item.tag = index
            effects.addItem(item)
        }
        let view = submenu("View")
        item(view, "Zoom In", #selector(EditorController.zoomIn(_:)), "=")
        item(view, "Zoom Out", #selector(EditorController.zoomOut(_:)), "-")
        item(view, "Actual Pixels", #selector(EditorController.actualSize(_:)), "1")
        item(view, "Fit to Window", #selector(EditorController.fitCanvas(_:)), "0")
        view.addItem(.separator())
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), target: editor.window)

        let help = submenu("Help")
        item(help, "Tools & Shortcuts", #selector(showHelp), target: self)
    }

    @objc func undo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
        else { editor.undoAction(sender) }
    }
    @objc func redo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
        else { editor.redoAction(sender) }
    }
    @objc func cut(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.cut(sender) }
        else { editor.cutPixels(sender) }
    }
    @objc func copy(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.copy(sender) }
        else { editor.copyPixels(sender) }
    }
    @objc func paste(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.paste(sender) }
        else { editor.pastePixels(sender) }
    }
    @objc func selectAll(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.selectAll(sender) }
        else { editor.selectAll(sender) }
    }

    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Scottware PaintMac",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .credits: MakerBranding.aboutCredits()
        ])
    }

    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Create with Scottware PaintMac"
        alert.informativeText = """
        B Brush · P Pencil · E Eraser · F Fill · G Gradient
        I Color Picker · L Line · R Rectangle · O Ellipse
        T Text · S Select · M Move Layer

        [ / ] Brush size · X Swap colors · D Black/white
        Shift constrains shapes and lines. Option-click samples color.
        Right-click paints with the secondary color.
        Space-drag pans. Pinch or ⌘-scroll zooms.

        A selection clips drawing and effects. Delete clears the active layer; ⌘K crops the image. Escape deselects.

        Save a .paintmac project to keep layers editable. Export PNG for transparency or JPEG for sharing. Text is rasterized when placed.
        """
        alert.runModal()
    }

    private func runUISmokeCheck() {
        if editor == nil { applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification)) }
        let canvas = editor.canvas!
        editor.window?.contentView?.layoutSubtreeIfNeeded()
        guard canvas.bounds.width > 0, editor.layersTable.numberOfRows == 1 else { exit(1) }
        editor.addLayer(nil)
        editor.chooseTool(.brush)
        editor.setZoom(1)
        let p = CGPoint(x: canvas.imageRect.minX + 30, y: canvas.imageRect.minY + 30)
        let location = canvas.convert(p, to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                      windowNumber: editor.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: down)
        canvas.mouseUp(with: down)
        guard editor.project.layers.count == 2,
              editor.project.layers[1].raster.color(at: CGPoint(x: 30, y: 30)).alphaComponent > 0.9 else { exit(2) }
        editor.undoAction(nil)
        guard editor.project.layers[1].raster.color(at: CGPoint(x: 30, y: 30)).alphaComponent == 0 else { exit(3) }
        editor.redoAction(nil)
        guard editor.project.layers[1].raster.color(at: CGPoint(x: 30, y: 30)).alphaComponent > 0.9 else { exit(4) }
        func drag(_ tool: Tool, _ start: CGPoint, _ end: CGPoint, shift: Bool = false) {
            editor.chooseTool(tool)
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                let p = CGPoint(x: canvas.imageRect.minX + point.x * editor.zoom, y: canvas.imageRect.minY + point.y * editor.zoom)
                return NSEvent.mouseEvent(with: type, location: canvas.convert(p, to: nil), modifierFlags: shift ? [.shift] : [],
                                         timestamp: 0, windowNumber: editor.window!.windowNumber, context: nil,
                                         eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        editor.filledShapes = true
        drag(.rectangle, CGPoint(x: 70, y: 70), CGPoint(x: 140, y: 130))
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 100, y: 100)).alphaComponent > 0.9 else { exit(5) }
        drag(.select, CGPoint(x: 80, y: 80), CGPoint(x: 100, y: 100))
        guard editor.project.selection == CGRect(x: 80, y: 80, width: 20, height: 20) else { exit(6) }
        editor.deletePixels(nil)
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 90, y: 90)).alphaComponent == 0,
              editor.selectedLayer.raster.color(at: CGPoint(x: 110, y: 110)).alphaComponent > 0.9 else { exit(7) }
        editor.deselect(nil)
        drag(.ellipse, CGPoint(x: 180, y: 80), CGPoint(x: 240, y: 140))
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 210, y: 110)).alphaComponent > 0.9 else { exit(8) }
        drag(.move, CGPoint(x: 210, y: 110), CGPoint(x: 220, y: 110))
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 220, y: 110)).alphaComponent > 0.9 else { exit(9) }
        editor.undoAction(nil)
        editor.project.selection = CGRect(x: 280, y: 80, width: 100, height: 100)
        drag(.gradient, CGPoint(x: 280, y: 80), CGPoint(x: 380, y: 80))
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 320, y: 120)).alphaComponent > 0.9 else { exit(10) }
        editor.deselect(nil)
        drag(.line, CGPoint(x: 70, y: 190), CGPoint(x: 240, y: 220), shift: true)
        drag(.pencil, CGPoint(x: 70, y: 250), CGPoint(x: 240, y: 250))
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 100, y: 250)).alphaComponent > 0 else { exit(11) }
        drag(.eraser, CGPoint(x: 100, y: 250), CGPoint(x: 130, y: 250))
        guard editor.selectedLayer.raster.color(at: CGPoint(x: 110, y: 250)).alphaComponent == 0 else { exit(12) }
        editor.chooseTool(.brush)
        editor.fitCanvas(nil)
        // Exercise view rendering without Screen Recording or Accessibility permissions.
        if let content = editor.window?.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(index + 1),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
        }
        print("PASS: editor layout, layers, brush, pencil, eraser, shapes, line, gradient, selection clipping, layer movement, undo/redo, and view rendering")
        editor.history.markSaved()
        exit(0)
    }
}
