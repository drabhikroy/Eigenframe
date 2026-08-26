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
//
// Mirrors ConfigStore.Assignment (v2: keyed by the Space's persistent uuid).
// The app is an executableTarget and cannot be imported, so the shape is
// duplicated here and must be kept in sync with ConfigStore.swift.

struct Assignment: Codable, Equatable {
    let spaceUUID: String
    let mediaPath: String

    enum CodingKeys: String, CodingKey {
        case spaceUUID = "space_uuid"
        case mediaPath = "media_path"
    }
}

final class AssignmentCodingTests: XCTestCase {

    func testRoundTrip() throws {
        let original = Assignment(spaceUUID: "9C469B4E-1234", mediaPath: "/Users/test/video.mp4")
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(Assignment.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodingKeysUseSnakeCase() throws {
        let assignment = Assignment(spaceUUID: "abc", mediaPath: "/tmp/a.mp4")
        let data       = try JSONEncoder().encode(assignment)
        let dict       = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(dict?["space_uuid"], "Expected snake_case key 'space_uuid'")
        XCTAssertNotNil(dict?["media_path"], "Expected snake_case key 'media_path'")
        XCTAssertNil(dict?["spaceUUID"],     "Did not expect camelCase key 'spaceUUID'")
    }
}

// MARK: - Index → UUID Migration Tests
//
// Mirrors ConfigStore.migrateIndexAssignmentsIfNeeded: old 1-based index i maps
// to the uuid of the i-th current Space. This is the core of the fix for
// wallpapers not following their desktop across Mission Control reordering.

private func migrateIndexToUUID(pending: [Int: String], orderedUUIDs: [String]) -> [Assignment] {
    var out: [Assignment] = []
    for (offset, uuid) in orderedUUIDs.enumerated() {
        let index = offset + 1
        if let path = pending[index] {
            out.append(Assignment(spaceUUID: uuid, mediaPath: path))
        }
    }
    return out
}

final class IndexToUUIDMigrationTests: XCTestCase {

    private let pending: [Int: String] = [
        1: "/m/nebula.mp4",
        2: "/m/blackhole.png",
        3: "/m/aurora.mov"
    ]

    func testMigrationMapsIndexToOrderedUUID() {
        let uuids  = ["UUID-A", "UUID-B", "UUID-C"]
        let result = migrateIndexToUUID(pending: pending, orderedUUIDs: uuids)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first { $0.spaceUUID == "UUID-A" }?.mediaPath, "/m/nebula.mp4")
        XCTAssertEqual(result.first { $0.spaceUUID == "UUID-B" }?.mediaPath, "/m/blackhole.png")
        XCTAssertEqual(result.first { $0.spaceUUID == "UUID-C" }?.mediaPath, "/m/aurora.mov")
    }

    /// After migration, reordering Spaces must NOT change which media a given
    /// desktop resolves to — the whole point of the fix.
    func testWallpaperFollowsDesktopAcrossReorder() {
        let migrated = migrateIndexToUUID(pending: pending, orderedUUIDs: ["UUID-A", "UUID-B", "UUID-C"])

        func media(for uuid: String) -> String? {
            migrated.first { $0.spaceUUID == uuid }?.mediaPath
        }

        // Simulate dragging the third desktop to the front in Mission Control.
        let reordered = ["UUID-C", "UUID-A", "UUID-B"]
        XCTAssertEqual(media(for: reordered[0]), "/m/aurora.mov")     // UUID-C keeps its media
        XCTAssertEqual(media(for: reordered[1]), "/m/nebula.mp4")     // UUID-A keeps its media
        XCTAssertEqual(media(for: reordered[2]), "/m/blackhole.png")  // UUID-B keeps its media
    }

    /// Fewer current Spaces than stored indices: extra assignments are dropped.
    func testMigrationDropsAssignmentsBeyondCurrentSpaceCount() {
        let result = migrateIndexToUUID(pending: pending, orderedUUIDs: ["UUID-A", "UUID-B"])
        XCTAssertEqual(result.count, 2)
        XCTAssertNil(result.first { $0.mediaPath == "/m/aurora.mov" })
    }

    func testMigrationWithNoPendingAssignmentsIsEmpty() {
        let result = migrateIndexToUUID(pending: [:], orderedUUIDs: ["UUID-A", "UUID-B"])
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - Space List Change Detection Tests
//
// Mirrors SpaceManager.SpaceInfo and the `fetched != spaces` diff check in
// refresh() that lets the 5Hz full-list poll skip republishing when nothing
// changed, while still catching a Mission Control reorder. Array equality on
// a Swift array is order-sensitive, which is what makes a reorder register as
// "changed" even though the set of uuids is identical — this suite pins that
// behavior down explicitly.

private struct SpaceInfo: Equatable {
    let uuid: String
    let id64: UInt64
}

final class SpaceListChangeDetectionTests: XCTestCase {

    private let base = [
        SpaceInfo(uuid: "UUID-A", id64: 101),
        SpaceInfo(uuid: "UUID-B", id64: 102),
        SpaceInfo(uuid: "UUID-C", id64: 103),
    ]

    func testIdenticalListsInSameOrderAreNotAChange() {
        let fetched = [
            SpaceInfo(uuid: "UUID-A", id64: 101),
            SpaceInfo(uuid: "UUID-B", id64: 102),
            SpaceInfo(uuid: "UUID-C", id64: 103),
        ]
        XCTAssertEqual(fetched, base, "Identical snapshots must compare equal so refresh() skips republishing")
    }

    func testReorderedListRegistersAsAChange() {
        // Same three Spaces, dragged into a new Mission Control order.
        let fetched = [
            SpaceInfo(uuid: "UUID-C", id64: 103),
            SpaceInfo(uuid: "UUID-A", id64: 101),
            SpaceInfo(uuid: "UUID-B", id64: 102),
        ]
        XCTAssertNotEqual(fetched, base, "A reorder must register as a change even though the uuid set is unchanged")
    }

    func testAddedSpaceRegistersAsAChange() {
        let fetched = base + [SpaceInfo(uuid: "UUID-D", id64: 104)]
        XCTAssertNotEqual(fetched, base)
    }

    func testRemovedSpaceRegistersAsAChange() {
        let fetched = Array(base.dropLast())
        XCTAssertNotEqual(fetched, base)
    }
}
