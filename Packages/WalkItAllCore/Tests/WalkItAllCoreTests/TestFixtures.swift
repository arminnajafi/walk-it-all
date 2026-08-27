import Foundation
@testable import WalkItAllCore

extension MapPackMetadata {
    static var fixture: MapPackMetadata {
        MapPackMetadata(
            identifier: "test",
            displayName: "Test",
            version: 1,
            sourceDate: Date(timeIntervalSince1970: 0),
            sourceURL: nil,
            attribution: "Test"
        )
    }
}

