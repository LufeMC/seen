import XCTest
import RewindCore
@testable import RewindButFast

final class APIKeyStoreTests: XCTestCase {
    func testKeychainRoundTripUpdateAndProviderIsolation() throws {
        let store = APIKeyStore(service: "SeenTests.\(UUID().uuidString)")
        defer {
            try? store.remove(.typesafe)
            try? store.remove(.vercel)
        }
        XCTAssertNil(try store.read(.typesafe))
        try store.save("synthetic-typesafe-key", provider: .typesafe)
        try store.save("synthetic-vercel-key", provider: .vercel)
        XCTAssertEqual(try store.read(.typesafe), "synthetic-typesafe-key")
        XCTAssertEqual(try store.read(.vercel), "synthetic-vercel-key")
        try store.save("updated-test-value", provider: .typesafe)
        XCTAssertEqual(try store.read(.typesafe), "updated-test-value")
        try store.remove(.typesafe)
        XCTAssertNil(try store.read(.typesafe))
        XCTAssertEqual(try store.read(.vercel), "synthetic-vercel-key")
    }
}
