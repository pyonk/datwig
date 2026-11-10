import XCTest
@testable import Datwig

final class DuplicateResolverTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("datwig_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    func testNoCollisionReturnsCopy() {
        let resolver = DuplicateResolver()
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        let targetURL = tempDirectory.appendingPathComponent("destination.jpg")

        let resolution = resolver.resolve(sourceURL: sourceURL, targetURL: targetURL, policy: .skipIdentical)
        XCTAssertEqual(resolution, .copy(destination: targetURL))
    }

    func testIdenticalFileSkipsWhenPolicyIsSkipIdentical() throws {
        let resolver = DuplicateResolver()
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        let targetURL = tempDirectory.appendingPathComponent("target.jpg")

        let content = "Sample JPEG Byte Stream 1234567890".data(using: .utf8)!
        try content.write(to: sourceURL)
        try content.write(to: targetURL)

        let resolution = resolver.resolve(sourceURL: sourceURL, targetURL: targetURL, policy: .skipIdentical)
        XCTAssertEqual(resolution, .skip(existing: targetURL))
    }

    func testDifferentFileRenamesWhenPolicyIsSkipIdentical() throws {
        let resolver = DuplicateResolver()
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        let targetURL = tempDirectory.appendingPathComponent("target.jpg")

        let contentA = "Image A".data(using: .utf8)!
        let contentB = "Different Image B with different size".data(using: .utf8)!
        try contentA.write(to: sourceURL)
        try contentB.write(to: targetURL)

        let resolution = resolver.resolve(sourceURL: sourceURL, targetURL: targetURL, policy: .skipIdentical)
        let expectedURL = tempDirectory.appendingPathComponent("target_1.jpg")
        XCTAssertEqual(resolution, .rename(destination: expectedURL))
    }

    func testRenameAlwaysGeneratesSequentialSuffixes() throws {
        let resolver = DuplicateResolver()
        let targetURL = tempDirectory.appendingPathComponent("photo.jpg")

        // Create photo.jpg and photo_1.jpg
        try "Content 0".data(using: .utf8)!.write(to: targetURL)
        let firstCollision = tempDirectory.appendingPathComponent("photo_1.jpg")
        try "Content 1".data(using: .utf8)!.write(to: firstCollision)

        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try "New Content".data(using: .utf8)!.write(to: sourceURL)

        let resolution = resolver.resolve(sourceURL: sourceURL, targetURL: targetURL, policy: .renameWithSuffix)
        let expectedThirdURL = tempDirectory.appendingPathComponent("photo_2.jpg")
        XCTAssertEqual(resolution, .rename(destination: expectedThirdURL))
    }

    func testOverwritePolicyReturnsOverwrite() throws {
        let resolver = DuplicateResolver()
        let targetURL = tempDirectory.appendingPathComponent("target.jpg")
        try "Existing".data(using: .utf8)!.write(to: targetURL)

        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try "New".data(using: .utf8)!.write(to: sourceURL)

        let resolution = resolver.resolve(sourceURL: sourceURL, targetURL: targetURL, policy: .overwrite)
        XCTAssertEqual(resolution, .overwrite(destination: targetURL))
    }
}
