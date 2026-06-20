import XCTest

extension XCTestCase {
    func makeTempDirectory(named name: String? = nil) throws -> URL {
        let suiteName = name ?? String(describing: type(of: self))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
