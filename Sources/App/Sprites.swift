import AppKit
import Foundation

// Sprite pack: your own pictures as the pets in Puff Battles. Put images and a sprites.json in
// ~/Library/Application Support/HealthWidget/sprites/ (on the host's Mac; the page embeds them, so other players need
// nothing). Without a pack the app draws its own pets. The pack stays on your Mac and is never part of the repository.
//
// sprites.json:
// {"species": [
//   {"id": "octo", "image": "5.jpg", "zh": "小章鱼", "en": "Octo", "rarity": 0},
//   {"id": "girl", "image": "1.jpg", "zh": "小魔女", "en": "Little Witch", "rarity": 1,
//    "evolve": {"image": "2.webp", "level": 10, "zh": "大魔女", "en": "Grand Witch"}}
// ]}
//
// A pet hatches as a species of the highest rarity not above the rarity it rolled (so rare pets above can hatch as a
// rare species); `evolve` swaps the picture and name from that level on.

struct SpriteForm: Codable {
    var image: String
    var level: Int?
    var zh: String
    var en: String
}

struct SpriteSpecies: Codable {
    var id: String
    var image: String
    var zh: String
    var en: String
    var rarity: Int?
    var evolve: SpriteForm?
}

struct SpritePack: Codable {
    var species: [SpriteSpecies]

    static let dir = Paths.base.appendingPathComponent("sprites", isDirectory: true)
    static let manifest = dir.appendingPathComponent("sprites.json")

    static func load() -> SpritePack? {
        guard let d = try? Data(contentsOf: manifest), let p = try? JSONDecoder().decode(SpritePack.self, from: d), !p.species.isEmpty else { return nil }
        return p
    }

    /// Changes whenever the manifest or a picture changes, so the page is rewritten.
    static func fingerprint() -> String {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return "" }
        return items.map { u in "\(u.lastPathComponent):\((try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0)" }
            .sorted().joined(separator: ",")
    }

    /// Species for a pet that rolled `rarity`.
    func pick(rarity: Int, _ r: inout RNG) -> SpriteSpecies {
        let allowed = species.filter { ($0.rarity ?? 0) <= rarity }
        let top = allowed.map { $0.rarity ?? 0 }.max()
        let pool = top.map { t in allowed.filter { ($0.rarity ?? 0) == t } } ?? species
        return r.pick(pool)
    }

    private static var cache: [String: String] = [:]

    /// The picture as a data: URI, scaled to 256 px and saved as JPEG so the page stays small.
    static func dataURI(_ file: String) -> String? {
        if let c = cache[file] { return c }
        guard let img = NSImage(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        let side = 256.0
        let size = img.size
        let k = min(1, side / max(size.width, size.height))
        let w = Int(size.width * k), h = Int(size.height * k)
        guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let uri = "data:image/jpeg;base64," + jpg.base64EncodedString()
        cache[file] = uri
        return uri
    }
}
