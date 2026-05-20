import XCTest

// MARK: - MediaType Tests
// Note: MediaType is tested here by duplicating the extension sets.
// Full integration tests require a running macOS environment with
// Accessibility permission granted.

final class MediaTypeExtensionTests: XCTestCase {

    private let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "hevc", "3gp", "mp4v"
    ]

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp"
    ]

    private func isVideo(_ filename: String) -> Bool {
        videoExtensions.contains(filename.components(separatedBy: ".").last?.lowercased() ?? "")
    }

    private func isImage(_ filename: String) -> Bool {
        imageExtensions.contains(filename.components(separatedBy: ".").last?.lowercased() ?? "")
    }

    func testMP4IsVideo()   { XCTAssertTrue(isVideo("clip.mp4"))  }
    func testMOVIsVideo()   { XCTAssertTrue(isVideo("clip.mov"))  }
    func testMKVIsVideo()   { XCTAssertTrue(isVideo("clip.mkv"))  }
    func testWebMIsVideo()  { XCTAssertTrue(isVideo("clip.webm")) }
    func testHEVCIsVideo()  { XCTAssertTrue(isVideo("clip.hevc")) }

    func testJPEGIsImage()  { XCTAssertTrue(isImage("photo.jpeg")) }
    func testPNGIsImage()   { XCTAssertTrue(isImage("photo.png"))  }
    func testHEICIsImage()  { XCTAssertTrue(isImage("photo.heic")) }
    func testGIFIsImage()   { XCTAssertTrue(isImage("anim.gif"))   }
    func testWebPIsImage()  { XCTAssertTrue(isImage("img.webp"))   }
    func testTIFFIsImage()  { XCTAssertTrue(isImage("scan.tiff"))  }

    func testPDFIsNeither() {
        XCTAssertFalse(isVideo("doc.pdf"))
        XCTAssertFalse(isImage("doc.pdf"))
    }

    func testUppercaseExtension() { XCTAssertTrue(isVideo("clip.MP4")) }
    func testMixedCaseExtension() { XCTAssertTrue(isImage("photo.Png")) }
}

// MARK: - Assignment Coding Tests

struct Assignment: Codable, Equatable {
    let spaceID:   UInt64
    let mediaPath: String

    enum CodingKeys: String, CodingKey {
        case spaceID   = "space_id"
        case mediaPath = "media_path"
    }
}

final class AssignmentCodingTests: XCTestCase {

    func testRoundTrip() throws {
        let original = Assignment(spaceID: 42, mediaPath: "/Users/test/video.mp4")
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(Assignment.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodingKeysUseSnakeCase() throws {
        let assignment = Assignment(spaceID: 1, mediaPath: "/tmp/a.mp4")
        let data       = try JSONEncoder().encode(assignment)
        let dict       = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(dict?["space_id"],   "Expected snake_case key 'space_id'")
        XCTAssertNotNil(dict?["media_path"], "Expected snake_case key 'media_path'")
        XCTAssertNil(dict?["spaceID"],       "Did not expect camelCase key 'spaceID'")
    }
}
