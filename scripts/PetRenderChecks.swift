import AppKit
import SwiftUI
import PetCore

@main
struct PetRenderChecks {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        Theme.registerFont()
        var count = 0
        for (species, suffix) in [("cat", "00"), ("dinosaur", "01"), ("dog", "02"), ("daruma", "03"), ("goblin", "04")] {
            for rests in [3, 12] {
                var pet = try Pet(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000" + suffix)!, name: "QA")
                try pet.applyNeed(id: UUID(), food: true, steps: 0, responding: true, now: Date(timeIntervalSince1970: 0))
                for n in 0..<rests { try pet.completeRest(id: "qa-\(n)", food: true, now: Date(timeIntervalSince1970: 0)) }
                precondition(pet.growth.species.rawValue == species)
                for scale in [1, 2] {
                    for (logicalWidth, logicalHeight) in [(320, 144), (200, 112)] {
                        let width = logicalWidth * scale
                        let height = logicalHeight * scale
                        func render(_ blink: Bool, reduced: Bool = false, visible: Bool = true) throws -> NSBitmapImageRep {
                            let view = PetStage(pet: pet, height: CGFloat(logicalHeight), reduceMotion: reduced, blinking: blink)
                                .environment(\.petMotionVisible, visible)
                                .frame(width: CGFloat(logicalWidth), height: CGFloat(logicalHeight))
                            let renderer = ImageRenderer(content: view)
                            renderer.scale = CGFloat(scale)
                            guard let image = renderer.cgImage else { throw Failure.render }
                            return NSBitmapImageRep(cgImage: image)
                        }
                        let idle = try render(false)
                        let blink = try render(true)
                        let reduced = try render(true, reduced: true)
                        let hidden = try render(true, visible: false)
                        func png(_ bitmap: NSBitmapImageRep) throws -> Data {
                            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
                            return data
                        }
                        let idlePNG = try png(idle)
                        let blinkPNG = try png(blink)
                        let reducedPNG = try png(reduced)
                        let hiddenPNG = try png(hidden)
                        precondition(idlePNG != blinkPNG, "Blink must be visibly different")
                        precondition(idlePNG == reducedPNG, "Reduce Motion must render exact idle")
                        precondition(idlePNG == hiddenPNG, "Hidden rendering must ignore a stale blink")
                        try idlePNG.write(to: output.appendingPathComponent("latest-idle.png"))
                        let size = (rests == 3 ? 72 : 96) * scale
                        // The animal must fit its centered integer-scaled area with margin.
                        for frame in [idle, blink] {
                            // Compare encoded PNG samples without NSColor's display-profile conversion.
                            guard let bitmap = NSBitmapImageRep(data: try png(frame)) else { throw Failure.render }
                            precondition(bitmap.bitsPerSample == 8 && bitmap.samplesPerPixel == 4)
                            precondition(bitmap.pixelsWide == width && bitmap.pixelsHigh == height)
                            var dark = 0
                            for y in 10..<(height - 10) {
                                for x in 10..<(width - 10) {
                                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { throw Failure.render }
                                    if color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5 {
                                        dark += 1
                                        precondition(x >= (width-size)/2 && x < (width+size)/2 && y >= (height-size)/2 && y < (height+size)/2,
                                                     "Character exceeds its intended frame")
                                    }
                                }
                            }
                            precondition(dark > 40, "Missing character or fallback text")
                            for y in (height-size)/2..<(height+size)/2 {
                                for x in (width-size)/2..<(width+size)/2 {
                                    var values = [Int](repeating: 0, count: 4)
                                    bitmap.getPixel(&values, atX: x, y: y)
                                    let palette = [[41, 45, 43, 255], [241, 241, 239, 255]]
                                    precondition(palette.contains(values),
                                                 "Unexpected pixel \(values) at \(x),\(y): nearest-neighbor rendering required")
                                }
                            }
                        }
                        let label = "\(species)-\(rests)-\(logicalWidth)-\(scale)x"
                        for (name, bitmap) in [("idle", idle), ("blink", blink), ("reduced", reduced), ("hidden", hidden)] {
                            try png(bitmap).write(to: output.appendingPathComponent("\(label)-\(name).png"))
                            count += 1
                        }
                    }
                }
            }
        }
        // Every production sprite is rendered by the actual view, including the short LCD.
        for suffix in ["00", "01", "02", "03", "04"] {
            for rests in [3, 12] {
                var pet = try Pet(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000" + suffix)!, name: "QA")
                try pet.applyNeed(id: UUID(), food: true, steps: 0, responding: true, now: Date(timeIntervalSince1970: 0))
                for n in 0..<rests { try pet.completeRest(id: "motion-\(n)", food: true, now: Date(timeIntervalSince1970: 0)) }
                for height in [78, 112] {
                    for scale in [1, 2] {
                        for action in PetAction.allCases {
                            for expression in PetExpression.allCases {
                                let plan = PetAnimationPlan(action: action, expression: expression)
                                var frames: [Data] = []
                                for blink in [false, true] {
                                    let view = PetStage(pet: pet, height: CGFloat(height), framed: false, blinking: blink, plan: plan)
                                        .environment(\.petMotionVisible, true).frame(width: 112, height: CGFloat(height))
                                    let renderer = ImageRenderer(content: view); renderer.scale = CGFloat(scale)
                                    guard let cg = renderer.cgImage,
                                          let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]),
                                          let bitmap = NSBitmapImageRep(data: data),
                                          let url = AppResources.bundle.url(forResource: plan.asset(species: pet.growth.species, secondFrame: blink), withExtension: "png"),
                                          let source = NSBitmapImageRep(data: try Data(contentsOf: url)) else { throw Failure.render }
                                    precondition(source.pixelsWide == 24 && source.pixelsHigh == 24)
                                    let factor = rests == 3 ? 3 : 4
                                    let originX = (112 - 24*factor)/2
                                    let originY = (height - 24*factor)/2
                                    var visiblePixels = 0
                                    for y in 0..<24 {
                                        for x in 0..<24 {
                                            var expected = [Int](repeating: 0, count: 4)
                                            source.getPixel(&expected, atX: x, y: y)
                                            guard expected[3] != 0 else { continue }
                                            visiblePixels += 1
                                            let px = (originX+x*factor)*scale, py = (originY+y*factor)*scale
                                            precondition(px >= 0 && py >= 0 && px+factor*scale <= bitmap.pixelsWide && py+factor*scale <= bitmap.pixelsHigh, "Sprite clipped in LCD")
                                            var actual = [Int](repeating: 0, count: 4)
                                            bitmap.getPixel(&actual, atX: px, y: py)
                                            precondition(actual == expected, "Nearest-neighbor pixel differs for \(plan.asset(species: pet.growth.species, secondFrame: blink))")
                                        }
                                    }
                                    precondition(visiblePixels > 40, "Sprite missing")
                                    frames.append(data)
                                    try data.write(to: output.appendingPathComponent("motion-\(pet.growth.species.rawValue)-\(rests)-\(height)-\(scale)-\(action.rawValue)-\(expression.rawValue)-\(blink).png"))
                                    count += 1
                                }
                                precondition(frames[0] != frames[1], "Every action must animate")
                            }
                        }
                    }
                }
            }
        }
        // Death takes precedence over egg/species and any stale animation state.
        for rests in [0, 3, 12] {
            for scale in [1, 2] {
                var reference: Data?
                for suffix in ["00", "01", "02", "03", "04"] {
                    var pet = try Pet(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000" + suffix)!, name: "QA")
                    for n in 0..<rests { try pet.completeRest(id: "grave-\(n)", food: true, now: Date(timeIntervalSince1970: 0)) }
                    try pet.applyNeed(id: UUID(), food: true, steps: 5, responding: false, now: Date(timeIntervalSince1970: 0))
                    precondition(pet.growth.stage == .departed)
                    let renderer = ImageRenderer(content: PetStage(pet: pet, height: 112, framed: false, blinking: true)
                        .environment(\.petMotionVisible, true).frame(width: 112, height: 112))
                    renderer.scale = CGFloat(scale)
                    guard let image = renderer.cgImage,
                          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure.render }
                    if let reference { precondition(reference == data, "Species must not leak into the grave") }
                    reference = data
                    try data.write(to: output.appendingPathComponent("grave-\(rests)-\(suffix)-\(scale)x.png"))
                    count += 1
                }
            }
        }
        print("PASS PetRenderChecks: \(count) actual PetStage renders; all five species, two sizes, full/compact at 1×/2×; distinct blink, exact static idle for Reduce Motion/hidden, character bounds")
        print("Offscreen fixed-frame checks do not verify task timing, real OS settings, or real window lifecycle.")
    }
    enum Failure: Error { case render }
}
