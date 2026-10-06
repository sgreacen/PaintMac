import AppKit
import PaintCore

extension EditorController {
    static let palette: [NSColor] = [
        .black, .white, NSColor(white: 0.5, alpha: 1), .systemRed,
        .systemOrange, .systemYellow, .systemGreen, .systemTeal,
        .systemCyan, .systemBlue, .systemIndigo, .systemPurple,
        .systemPink, NSColor(srgbRed: 0.52, green: 0.30, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 1, green: 0.77, blue: 0.66, alpha: 1),
        NSColor(srgbRed: 0.65, green: 0.86, blue: 1, alpha: 1)
    ]

    func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    func button(_ title: String, symbol: String? = nil, action: Selector, help: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        button.toolTip = help ?? title
        return button
    }

    func slider(value: Double, min: Double, max: Double, action: Selector) -> NSSlider {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: action)
        slider.controlSize = .small
        return slider
    }

    func heading(_ title: String) -> NSTextField {
        let view = label(title.uppercased(), size: 10, weight: .semibold)
        view.textColor = .secondaryLabelColor
        return view
    }

    func vertical(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }

    func divider() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

    func buildInterface() {
        guard let window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1).cgColor
        window.contentView = root

        let top = NSStackView()
        top.orientation = .horizontal; top.spacing = 10
        top.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        let logo = NSImageView(image: NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: "Scottware PaintMac")!)
        logo.contentTintColor = .systemBlue
        logo.widthAnchor.constraint(equalToConstant: 28).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let branding = vertical([label("Scottware PaintMac", size: 19, weight: .bold), label("A Scottware utility · Create. Edit. Make it yours.", size: 10)], spacing: 2)
        top.addArrangedSubview(logo); top.addArrangedSubview(branding)
        top.addArrangedSubview(NSView())
        top.addArrangedSubview(MakerBranding.creditView())
        top.addArrangedSubview(button("New", symbol: "plus", action: #selector(newDocument)))
        top.addArrangedSubview(button("Open", symbol: "folder", action: #selector(openDocument)))
        top.addArrangedSubview(button("Save", symbol: "square.and.arrow.down", action: #selector(save)))
        let export = button("Export PNG", symbol: "square.and.arrow.up", action: #selector(exportPNG))
        export.bezelColor = .systemBlue
        top.addArrangedSubview(export)

        let options = NSStackView()
        options.orientation = .horizontal; options.spacing = 14
        options.edgeInsets = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        brushLabel = label("Size  12 px", size: 11, weight: .medium)
        brushLabel.widthAnchor.constraint(equalToConstant: 82).isActive = true
        brushSlider = slider(value: 12, min: 1, max: 200, action: #selector(brushChanged))
        brushSlider.widthAnchor.constraint(equalToConstant: 115).isActive = true
        toolOpacitySlider = slider(value: 100, min: 1, max: 100, action: #selector(opacityChanged))
        toolOpacitySlider.widthAnchor.constraint(equalToConstant: 85).isActive = true
        toolOpacitySlider.toolTip = "Tool opacity, 1–100%"
        toleranceSlider = slider(value: 24, min: 0, max: 255, action: #selector(toleranceChanged))
        toleranceSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        toleranceSlider.toolTip = "Paint bucket tolerance, 0–255"
        shapeCheck = NSButton(checkboxWithTitle: "Fill shapes", target: self, action: #selector(shapeChanged))
        shapeCheck.font = .systemFont(ofSize: 11)
        fontSlider = slider(value: 36, min: 8, max: 180, action: #selector(fontChanged))
        fontSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        fontSlider.toolTip = "Text size, 8–180 points"
        for view in [brushLabel!, brushSlider!, label("Opacity", size: 11), toolOpacitySlider!, label("Tolerance", size: 11),
                     toleranceSlider!, shapeCheck!, label("Text size", size: 11), fontSlider!, NSView()] {
            options.addArrangedSubview(view)
        }
        undoButton = button("", symbol: "arrow.uturn.backward", action: #selector(undoAction), help: "Undo (⌘Z)")
        redoButton = button("", symbol: "arrow.uturn.forward", action: #selector(redoAction), help: "Redo (⇧⌘Z)")
        options.addArrangedSubview(undoButton); options.addArrangedSubview(redoButton)

        let tools = buildTools()
        let inspector = buildInspector()
        let center = NSView()
        center.wantsLayer = true
        center.layer?.backgroundColor = NSColor(white: 0.1, alpha: 1).cgColor
        let documentBar = NSStackView()
        documentBar.spacing = 8
        documentBar.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        let icon = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!)
        icon.contentTintColor = .systemBlue
        titleLabel = label("Untitled", size: 12, weight: .medium)
        documentBar.addArrangedSubview(icon); documentBar.addArrangedSubview(titleLabel)
        documentBar.addArrangedSubview(NSView())
        documentBar.addArrangedSubview(label("RGB / 8-bit", size: 10))
        scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true; scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        canvas = CanvasView(editor: self)
        scrollView.documentView = canvas
        center.addSubview(documentBar); center.addSubview(scrollView)
        documentBar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            documentBar.topAnchor.constraint(equalTo: center.topAnchor),
            documentBar.leadingAnchor.constraint(equalTo: center.leadingAnchor),
            documentBar.trailingAnchor.constraint(equalTo: center.trailingAnchor),
            documentBar.heightAnchor.constraint(equalToConstant: 36),
            scrollView.topAnchor.constraint(equalTo: documentBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: center.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: center.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: center.bottomAnchor)
        ])

        let bottom = NSStackView()
        bottom.spacing = 8
        bottom.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        sizeLabel = label("", size: 10)
        sizeLabel.textColor = .secondaryLabelColor
        statusLabel = label("", size: 10)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zoomLabel = label("100%", size: 11, weight: .medium)
        zoomLabel.alignment = .center
        zoomLabel.widthAnchor.constraint(equalToConstant: 45).isActive = true
        bottom.addArrangedSubview(sizeLabel)
        bottom.addArrangedSubview(NSView())
        bottom.addArrangedSubview(statusLabel)
        bottom.addArrangedSubview(NSView())
        bottom.addArrangedSubview(button("", symbol: "minus.magnifyingglass", action: #selector(zoomOut), help: "Zoom out"))
        bottom.addArrangedSubview(zoomLabel)
        bottom.addArrangedSubview(button("", symbol: "plus.magnifyingglass", action: #selector(zoomIn), help: "Zoom in"))
        bottom.addArrangedSubview(button("Fit", action: #selector(fitCanvas)))

        for view in [top, options, tools, center, inspector, bottom] {
            root.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor), top.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 70),
            options.topAnchor.constraint(equalTo: top.bottomAnchor), options.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            options.trailingAnchor.constraint(equalTo: root.trailingAnchor), options.heightAnchor.constraint(equalToConstant: 43),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor), bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor), bottom.heightAnchor.constraint(equalToConstant: 38),
            tools.topAnchor.constraint(equalTo: options.bottomAnchor), tools.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tools.bottomAnchor.constraint(equalTo: bottom.topAnchor), tools.widthAnchor.constraint(equalToConstant: 66),
            inspector.topAnchor.constraint(equalTo: options.bottomAnchor), inspector.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            inspector.bottomAnchor.constraint(equalTo: bottom.topAnchor), inspector.widthAnchor.constraint(equalToConstant: 246),
            center.topAnchor.constraint(equalTo: options.bottomAnchor), center.leadingAnchor.constraint(equalTo: tools.trailingAnchor),
            center.trailingAnchor.constraint(equalTo: inspector.leadingAnchor), center.bottomAnchor.constraint(equalTo: bottom.topAnchor)
        ])
        window.makeFirstResponder(canvas)
    }

    func buildTools() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.spacing = 6; stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
        for (index, tool) in Tool.allCases.enumerated() {
            let item = button("", symbol: tool.symbol, action: #selector(toolPressed), help: "\(tool.rawValue) (\(tool.shortcut.uppercased()))")
            item.setButtonType(.pushOnPushOff)
            item.bezelStyle = .regularSquare
            item.isBordered = false
            item.wantsLayer = true
            item.layer?.cornerRadius = 7
            item.contentTintColor = .labelColor
            item.tag = index
            item.widthAnchor.constraint(equalToConstant: 38).isActive = true
            item.heightAnchor.constraint(equalToConstant: 34).isActive = true
            toolButtons[tool] = item
            stack.addArrangedSubview(item)
        }
        stack.addArrangedSubview(NSView())
        return stack
    }

    func buildInspector() -> NSView {
        let sidebar = NSView()
        let content = NSStackView()
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 11
        content.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12)
        ])
        content.addArrangedSubview(heading("Colors"))
        primaryWell = NSColorWell(); secondaryWell = NSColorWell()
        for well in [primaryWell!, secondaryWell!] {
            well.target = self; well.action = #selector(colorChanged)
            well.widthAnchor.constraint(equalToConstant: 50).isActive = true
            well.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        primaryWell.toolTip = "Primary color"; secondaryWell.toolTip = "Secondary color"
        let colors = NSStackView(views: [primaryWell, secondaryWell, button("", symbol: "arrow.left.arrow.right", action: #selector(swapColors), help: "Swap colors (X)")])
        colors.spacing = 10
        content.addArrangedSubview(colors)
        let palette = NSGridView()
        palette.rowSpacing = 5; palette.columnSpacing = 5
        for row in 0..<2 {
            var swatches: [NSView] = []
            for column in 0..<8 {
                let index = row * 8 + column
                let swatch = NSButton(title: "", target: self, action: #selector(swatchPressed))
                swatch.tag = index; swatch.isBordered = false; swatch.wantsLayer = true
                swatch.layer?.backgroundColor = Self.palette[index].cgColor
                swatch.layer?.cornerRadius = 4
                swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
                swatch.layer?.borderWidth = 1
                swatch.widthAnchor.constraint(equalToConstant: 22).isActive = true
                swatch.heightAnchor.constraint(equalToConstant: 22).isActive = true
                swatches.append(swatch)
            }
            palette.addRow(with: swatches)
        }
        content.addArrangedSubview(palette)
        content.addArrangedSubview(divider())

        let layerHeader = NSStackView(views: [heading("Layers"), NSView(), button("", symbol: "plus", action: #selector(addLayer), help: "Add layer")])
        content.addArrangedSubview(layerHeader)
        layersTable = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Layer"))
        column.width = 205
        layersTable.addTableColumn(column)
        layersTable.headerView = nil
        layersTable.rowHeight = 50
        layersTable.backgroundColor = .clear
        layersTable.style = .sourceList
        layersTable.dataSource = self; layersTable.delegate = self
        layersTable.allowsEmptySelection = false
        let layerScroll = NSScrollView()
        layerScroll.documentView = layersTable; layerScroll.hasVerticalScroller = true
        layerScroll.drawsBackground = false
        layerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        content.addArrangedSubview(layerScroll)

        let operations = NSStackView(views: [
            button("", symbol: "square.on.square", action: #selector(duplicateLayer), help: "Duplicate layer"),
            button("", symbol: "arrow.up", action: #selector(layerUp), help: "Move layer up"),
            button("", symbol: "arrow.down", action: #selector(layerDown), help: "Move layer down"),
            NSView(), button("", symbol: "trash", action: #selector(deleteLayer), help: "Delete layer")
        ])
        operations.spacing = 6
        content.addArrangedSubview(operations)
        layerName = NSTextField(string: "Background")
        layerName.font = .systemFont(ofSize: 12)
        layerName.target = self; layerName.action = #selector(renameLayer)
        layerName.placeholderString = "Layer name (Return to rename)"
        layerName.toolTip = "Layer name — press Return to rename"
        content.addArrangedSubview(layerName)
        blendPopup = NSPopUpButton()
        blendPopup.addItems(withTitles: Blend.allCases.map(\.rawValue))
        blendPopup.target = self; blendPopup.action = #selector(blendChanged)
        content.addArrangedSubview(blendPopup)
        layerOpacity = slider(value: 100, min: 0, max: 100, action: #selector(layerOpacityChanged))
        layerOpacity.isContinuous = false
        content.addArrangedSubview(NSStackView(views: [label("Opacity", size: 11), layerOpacity]))
        content.addArrangedSubview(divider())
        content.addArrangedSubview(heading("Recent edits"))
        historyLabel = label("Your next idea starts here.", size: 11)
        historyLabel.maximumNumberOfLines = 5
        historyLabel.textColor = .secondaryLabelColor
        historyLabel.heightAnchor.constraint(equalToConstant: 76).isActive = true
        content.addArrangedSubview(historyLabel)
        for view in content.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        return sidebar
    }
}
