import Foundation
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "window-info.txt"
let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

struct Candidate {
    let id: Int
    let owner: String
    let title: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    var area: Int { width * height }
    var score: Int {
        let h = (owner + " " + title).lowercased()
        var s = area
        if h.contains("steam") { s += 10_000_000 }
        if title.lowercased().contains("sign in to steam") { s += 20_000_000 }
        if owner.lowercased().contains("wine") { s += 5_000_000 }
        return s
    }
}

var candidates: [Candidate] = []
for w in windows {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let title = w[kCGWindowName as String] as? String ?? ""
    let h = (owner + " " + title).lowercased()
    guard h.contains("steam") || owner.lowercased().contains("wine") else { continue }
    guard let id = w[kCGWindowNumber as String] as? Int else { continue }
    guard let bounds = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    let x = bounds["X"] as? Int ?? 0
    let y = bounds["Y"] as? Int ?? 0
    let width = bounds["Width"] as? Int ?? 0
    let height = bounds["Height"] as? Int ?? 0
    guard width > 80 && height > 80 else { continue }
    candidates.append(Candidate(id: id, owner: owner, title: title, x: x, y: y, width: width, height: height))
}

for c in candidates.sorted(by: { $0.score > $1.score }) {
    print("candidate id=\(c.id) owner=\(c.owner) title=\(c.title) x=\(c.x) y=\(c.y) width=\(c.width) height=\(c.height) score=\(c.score)")
}
if let best = candidates.sorted(by: { $0.score > $1.score }).first {
    print("SELECTED_WINDOW_ID=\(best.id)")
}
