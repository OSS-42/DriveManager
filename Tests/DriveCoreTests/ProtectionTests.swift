import XCTest
@testable import DriveCore

final class ProtectionTests: XCTestCase {
    private let home = "/Users/someone"

    func testSystemFoldersAreProtected() {
        for path in ["/System", "/System/Library/Fonts/x.ttf", "/usr/bin/ls", "/private/var/vm/sleepimage"] {
            XCTAssertEqual(Protection.reason(forPath: path, home: home), "Part of macOS", path)
        }
    }

    func testContainerFoldersCannotGoWhole() {
        for path in ["/", "/Applications", home, home + "/Library", home + "/Documents/"] {
            XCTAssertNotNil(Protection.reason(forPath: path, home: home), path)
        }
    }

    func testItemsInsideContainersMayGo() {
        for path in ["/Applications/Old.app", home + "/Library/Caches/com.example", home + "/Downloads/big.dmg", "/usrlocal"] {
            XCTAssertNil(Protection.reason(forPath: path, home: home), path)
        }
    }
}
