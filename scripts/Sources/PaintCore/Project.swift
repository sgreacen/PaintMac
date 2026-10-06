import AppKit

public enum Blend: String, CaseIterable, Codable {
    case normal = "Normal", multiply = "Multiply", screen = "Screen", overlay = "Overlay"
    case darken = "Darken", lighten = "Lighten", difference = "Difference"

    public var cg: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .difference: return .difference
        }
    }
}

public struct Layer {
    public var id = UUID()
    public var name: String
    public var visible = true
    public var opacity: CGFloat = 1
    public var blend = Blend.normal
    public var raster: Raster
    public init(name: String, raster: Raster) { self.name = name; self.raster = raster }
}

public struct Project {
    public var width: Int
    public var height: Int
    /// Ordered bottom to top.
    public var layers: [Layer]
    public var selected: Int
    public var selection: CGRect?
    public var memoryCost: Int { width * height * 4 * layers.count }
    public var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    public init(width: Int = 1000, height: Int = 700, transparent: Bool = false) {
        self.width = width; self.height = height
        layers = [Layer(name: "Background", raster: Raster(width: width, height: height, color: transparent ? nil : .white))]
        selected = 0
    }

    public init(raster: Raster, name: String) {
        width = raster.width; height = raster.height
        layers = [Layer(name: name, raster: raster)]
        selected = 0
    }

    public func composite(whiteBackground: Bool = false) -> Raster {
        var result = Raster(width: width, height: height, color: whiteBackground ? .white : nil)
        let bounds = self.bounds
        for layer in layers where layer.visible && layer.opacity > 0 {
            let image = layer.raster.image
            result.paint { context in
                context.setAlpha(layer.opacity)
                context.setBlendMode(layer.blend.cg)
                Raster.draw(image, in: bounds, context: context)
            }
        }
        return result
    }

    public mutating func addLayer(name: String = "New layer", raster: Raster? = nil) throws {
        guard layers.count < 32, memoryCost + width * height * 4 <= 512 * 1024 * 1024 else {
            throw PaintError.message("This document has reached its layer memory limit (32 layers or 512 MB).")
        }
        layers.insert(Layer(name: name, raster: raster ?? Raster(width: width, height: height)), at: selected + 1)
        selected += 1
    }

    public mutating func resize(width: Int, height: Int) throws {
        try Raster.validateSize(width: width, height: height)
        guard width * height * 4 * layers.count <= 512 * 1024 * 1024 else {
            throw PaintError.message("The resized layers would exceed the 512 MB document limit.")
        }
        layers = layers.map { layer in
            var layer = layer
            layer.raster = layer.raster.resized(width: width, height: height)
            return layer
        }
        self.width = width; self.height = height; selection = nil
    }

    public mutating func crop() {
        guard let area = selection?.intersection(bounds).integral, area.width >= 1, area.height >= 1 else { return }
        for i in layers.indices { layers[i].raster = layers[i].raster.cropped(to: area) }
        width = Int(area.width); height = Int(area.height); selection = nil
    }

    public mutating func rotate() {
        for i in layers.indices { layers[i].raster = layers[i].raster.rotatedClockwise() }
        swap(&width, &height); selection = nil
    }

    public mutating func flip(horizontal: Bool) {
        for i in layers.indices { layers[i].raster = layers[i].raster.flipped(horizontal: horizontal) }
        selection = nil
    }

    private struct Archive: Codable {
        var formatVersion: Int
        var width: Int
        var height: Int
        var selected: Int
        var layers: [ArchivedLayer]
    }

    private struct ArchivedLayer: Codable {
        var id: UUID
        var name: String
        var visible: Bool
        var opacity: Double
        var blend: Blend
        var png: Data
    }

    public func encoded() throws -> Data {
        let archive = Archive(formatVersion: 1, width: width, height: height, selected: selected,
                              layers: try layers.map {
            ArchivedLayer(id: $0.id, name: $0.name, visible: $0.visible, opacity: Double($0.opacity),
                          blend: $0.blend, png: try $0.raster.encoded())
        })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(archive)
    }

    public static func decode(_ data: Data) throws -> Project {
        guard data.count <= 600 * 1024 * 1024 else { throw PaintError.message("The project file is too large.") }
        let archive = try PropertyListDecoder().decode(Archive.self, from: data)
        guard archive.formatVersion == 1 else { throw PaintError.message("This project format is not supported.") }
        try Raster.validateSize(width: archive.width, height: archive.height)
        guard !archive.layers.isEmpty, archive.layers.count <= 32,
              archive.width * archive.height * 4 * archive.layers.count <= 512 * 1024 * 1024,
              archive.layers.indices.contains(archive.selected),
              Set(archive.layers.map(\.id)).count == archive.layers.count else {
            throw PaintError.message("The project's layer information is invalid.")
        }
        let layers = try archive.layers.map { item -> Layer in
            let raster = try Raster.load(data: item.png)
            guard raster.width == archive.width, raster.height == archive.height,
                  item.opacity.isFinite, (0...1).contains(item.opacity) else {
                throw PaintError.message("A layer has invalid dimensions or opacity.")
            }
            var layer = Layer(name: item.name, raster: raster)
            layer.id = item.id; layer.visible = item.visible
            layer.opacity = CGFloat(item.opacity); layer.blend = item.blend
            return layer
        }
        var project = Project(raster: layers[0].raster, name: layers[0].name)
        project.layers = layers; project.selected = archive.selected
        return project
    }
}

public final class History {
    public struct Entry {
        public var project: Project
        public var name: String
        public var revision: UUID
    }
    public private(set) var past: [Entry] = []
    public private(set) var future: [Entry] = []
    public private(set) var revision = UUID()
    public var savedRevision: UUID?
    public var isDirty: Bool { savedRevision != revision }

    public init(saved: Bool = true) { if saved { savedRevision = revision } }

    public func record(_ project: Project, name: String) {
        past.append(Entry(project: project, name: name, revision: revision))
        future.removeAll()
        revision = UUID()
        // Conservative estimate; Swift's copy-on-write also shares untouched layers.
        while past.count > 1 && (past.count > 40 || past.reduce(0, { $0 + $1.project.memoryCost }) > 192 * 1024 * 1024) {
            past.removeFirst()
        }
    }

    public func undo(_ current: Project) -> Project? {
        guard let entry = past.popLast() else { return nil }
        future.append(Entry(project: current, name: entry.name, revision: revision))
        revision = entry.revision
        return entry.project
    }

    public func redo(_ current: Project) -> Project? {
        guard let entry = future.popLast() else { return nil }
        past.append(Entry(project: current, name: entry.name, revision: revision))
        revision = entry.revision
        return entry.project
    }

    public func markSaved() { savedRevision = revision }
}
