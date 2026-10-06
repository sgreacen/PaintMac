import AppKit

enum MakerBranding {
    static var logo: NSImage? {
        guard let url = Bundle.module.url(forResource: "ScottwareLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func creditView() -> NSView {
        let image = NSImageView()
        image.image = logo
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("Scottware Software logo")
        image.widthAnchor.constraint(equalToConstant: 46).isActive = true
        image.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let caption = NSTextField(labelWithString: "CREATED BY")
        caption.font = .systemFont(ofSize: 8, weight: .medium)
        caption.textColor = .secondaryLabelColor
        let name = NSTextField(labelWithString: "Scottware Software")
        name.font = .systemFont(ofSize: 10, weight: .semibold)
        let text = NSStackView(views: [caption, name])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let credit = NSStackView(views: [image, text])
        credit.spacing = 8
        credit.alignment = .centerY
        credit.toolTip = "Created by Scottware Software — Built clean. Runs smooth."
        return credit
    }

    static func aboutCredits() -> NSAttributedString {
        let credits = NSMutableAttributedString(string: "")
        if let image = logo {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: 0, width: 170, height: 170)
            credits.append(NSAttributedString(attachment: attachment))
            credits.append(NSAttributedString(string: "\n\n"))
        }
        credits.append(NSAttributedString(string: "Created by Scottware Software\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]))
        credits.append(NSAttributedString(string: "Built clean. Runs smooth.\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        credits.append(NSAttributedString(string: "A native macOS raster editor inspired by Paint.NET.\nBuilt with AppKit, Core Graphics, and Core Image.\nAn independent project; not affiliated with Paint.NET.", attributes: [
            .font: NSFont.systemFont(ofSize: 10)
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        return credits
    }
}
