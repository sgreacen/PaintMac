import AppKit
import PaintCore

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw PaintError.message("FAIL: " + message) }
    checks += 1
    print("PASS: " + message)
}
func rgba(_ raster: Raster, _ x: Int, _ y: Int) -> [UInt8] {
    let offset = (y * raster.width + x) * 4
    return Array(raster.pixels[offset..<(offset + 4)])
}

func run() throws {
    var raster = Raster(width: 8, height: 6)
    raster.paint { context in
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 4, y: 4, width: 4, height: 2))
    }
    try check(rgba(raster, 0, 0) == [255, 0, 0, 255], "drawing uses top-left coordinates")
    try check(rgba(raster, 7, 5) == [0, 0, 255, 255], "bottom-right pixel orientation")
    try check(rgba(raster, 0, 5) == [0, 0, 0, 0], "transparent pixels remain transparent")
    let decoded = try Raster.load(data: raster.encoded())
    try check(decoded.pixels == raster.pixels, "PNG round trip preserves every pixel and orientation")
    let copied = try Raster(image: raster.image)
    try check(copied.pixels == raster.pixels, "CGImage drawing preserves orientation")

    var filled = Raster(width: 10, height: 10, color: .white)
    filled.paint { context in
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 5, y: 0, width: 1, height: 10))
    }
    filled.floodFill(at: CGPoint(x: 0, y: 0), color: .red, tolerance: 0)
    try check(rgba(filled, 0, 0) == [255, 0, 0, 255], "bucket fills connected region")
    try check(rgba(filled, 9, 0) == [255, 255, 255, 255], "bucket respects barriers")
    filled.floodFill(at: CGPoint(x: 8, y: 8), color: .blue, tolerance: 0, clip: CGRect(x: 7, y: 7, width: 2, height: 2))
    try check(rgba(filled, 8, 8) == [0, 0, 255, 255] && rgba(filled, 9, 8) == [255, 255, 255, 255], "bucket respects selection")

    var brush = Raster(width: 20, height: 20)
    brush.stroke(from: CGPoint(x: 2, y: 2), to: CGPoint(x: 15, y: 2), color: .red, size: 3)
    try check(brush.color(at: CGPoint(x: 8, y: 2)).redComponent > 0.99, "brush paints a continuous stroke")
    brush.stroke(from: CGPoint(x: 8, y: 2), to: CGPoint(x: 8, y: 2), color: .black, size: 4, erasing: true)
    try check(brush.color(at: CGPoint(x: 8, y: 2)).alphaComponent == 0, "eraser clears alpha")

    var project = Project(width: 8, height: 6)
    try project.addLayer(name: "Artwork", raster: raster)
    try check(rgba(project.composite(), 0, 0) == [255, 0, 0, 255], "layers composite in bottom-to-top order")
    project.layers[1].visible = false
    try check(rgba(project.composite(), 0, 0) == [255, 255, 255, 255], "hidden layers are excluded")
    project.layers[1].visible = true
    project.layers[1].opacity = 0.5
    let blended = rgba(project.composite(), 0, 0)
    try check(blended[0] == 255 && (126...129).contains(Int(blended[1])), "layer opacity blends correctly")
    project.layers[1].blend = .multiply
    let archive = try project.encoded()
    let restored = try Project.decode(archive)
    try check(restored.layers.count == 2 && restored.selected == 1, "project round trip preserves layer stack")
    try check(restored.layers[1].raster.pixels == raster.pixels, "project round trip preserves pixels")
    try check(restored.layers[1].opacity == 0.5 && restored.layers[1].blend == .multiply, "project round trip preserves layer properties")
    try check(restored.layers[1].id == project.layers[1].id, "project round trip preserves layer identity")

    let flipped = raster.flipped(horizontal: true)
    try check(rgba(flipped, 7, 0) == rgba(raster, 0, 0), "horizontal flip")
    let rotated = raster.rotatedClockwise()
    try check(rotated.width == 6 && rotated.height == 8 && rgba(rotated, 5, 0) == rgba(raster, 0, 0), "clockwise rotation")
    let cropped = raster.cropped(to: CGRect(x: 4, y: 4, width: 4, height: 2))
    try check(cropped.width == 4 && cropped.height == 2 && rgba(cropped, 0, 0) == [0, 0, 255, 255], "crop retains the selected pixels")
    let resized = raster.resized(width: 16, height: 12)
    try check(resized.width == 16 && resized.height == 12 && rgba(resized, 0, 0) == [255, 0, 0, 255], "resize retains top-left orientation")

    let inverted = try raster.effect(.invert)
    try check(rgba(inverted, 0, 0) == [0, 255, 255, 255] && rgba(inverted, 0, 5) == [0, 0, 0, 0], "invert preserves alpha")
    let gray = try raster.effect(.grayscale)
    try check(rgba(gray, 0, 0)[0] == rgba(gray, 0, 0)[1], "grayscale equalizes color channels")
    for effect in Effect.allCases {
        let result = try raster.effect(effect)
        try check(result.width == raster.width && result.height == raster.height, "\(effect.rawValue) renders at canvas dimensions")
    }

    let history = History()
    let original = project
    history.record(project, name: "Paint")
    project.layers[1].raster = inverted
    try check(history.isDirty, "edits mark document dirty")
    project = history.undo(project)!
    try check(project.layers[1].raster.pixels == original.layers[1].raster.pixels && !history.isDirty, "undo restores pixels and saved revision")
    project = history.redo(project)!
    try check(project.layers[1].raster.pixels == inverted.pixels && history.isDirty, "redo restores edit")
    history.markSaved()
    try check(!history.isDirty, "save clears dirty state")
    project = history.undo(project)!
    history.record(project, name: "Different edit")
    try check(history.future.isEmpty && history.isDirty, "new edit clears redo branch")

    do { try Raster.validateSize(width: 0, height: 100); throw PaintError.message("size validation did not reject zero") }
    catch let error as PaintError {
        try check(error.localizedDescription.contains("dimensions"), "invalid canvas dimensions rejected")
    }
    do { _ = try Project.decode(Data("not a project".utf8)); throw PaintError.message("corrupt file accepted") }
    catch { try check(!error.localizedDescription.contains("corrupt file accepted"), "corrupt project rejected") }
    print("\n\(checks) checks passed.")
}

do { try run() }
catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
