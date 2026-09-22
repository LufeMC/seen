import XCTest
@testable import RewindCore

final class JevClientTests: XCTestCase {
    private let memories = [
        Memory(id: "private-id-a", app: "Notes", title: "Plan", text: "The launch date is Friday.", imagePath: "/private/a.jpg", sourceURL: "https://private.example"),
        Memory(id: "private-id-b", app: "Safari", title: "Bread", text: "A sourdough recipe.", imagePath: "/private/b.jpg")
    ]

    func testProviderRequestsAndDataMinimization() throws {
        for provider in JevProvider.allCases {
            let request = try JevClient.request(query: "launch", memories: memories, provider: provider, key: "test-key")
            XCTAssertEqual(request.url, provider.endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let data = try XCTUnwrap(request.httpBody)
            let text = String(decoding: data, as: UTF8.self)
            for excluded in ["private-id", "private.example", "/private/", "test-key", "imagePath", "sourceURL"] {
                XCTAssertFalse(text.contains(excluded))
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, provider.model)
            let questions = try XCTUnwrap(body["questions"] as? [String: [String: Any]])
            XCTAssertEqual(Set(questions.keys), ["r0", "r1"])
            XCTAssertEqual(questions["r0"]?["type"] as? String, provider == .typesafe ? "noul" : "boolean")
        }
    }

    func testPayloadLimits() throws {
        let long = String(repeating: "界", count: 10000)
        let items = (0..<100).map { _ in Memory(app: long, title: long, text: long, imagePath: "") }
        let request = try JevClient.request(query: long, memories: items, provider: .typesafe, key: "test")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let state = try XCTUnwrap(body["state"] as? [String: Any])
        let records = try XCTUnwrap(state["captures"] as? [[String: String]])
        XCTAssertEqual(records.count, 32)
        XCTAssertEqual((state["query"] as? String)?.count, 500)
        XCTAssertEqual(records[0]["app"]?.count, 100)
        XCTAssertEqual(records[0]["title"]?.count, 200)
        XCTAssertEqual(records[0]["text"]?.count, 1600)
    }

    func testRanksBothProviderResponsesAndPreservesTies() throws {
        for provider in JevProvider.allCases {
            let field = provider == .typesafe ? "noul" : "probability"
            let type = provider == .typesafe ? "noul" : "boolean"
            func response(_ first: Double, _ second: Double) throws -> Data {
                try JSONSerialization.data(withJSONObject: ["answers": ["r0": ["type": type, field: first], "r1": ["type": type, field: second]]])
            }
            XCTAssertEqual(try JevClient.ranked(memories: memories, data: response(0.1, 0.9), provider: provider), memories.reversed())
            XCTAssertEqual(try JevClient.ranked(memories: memories, data: response(0.5, 0.5), provider: provider), memories)
        }
    }

    func testRejectsMissingOutOfRangeBooleanAndMalformedScores() {
        let invalid = ["{}", "not json", "{\"answers\":{}}",
            "{\"answers\":{\"r0\":{\"type\":\"noul\",\"noul\":2}}}",
            "{\"answers\":{\"r0\":{\"type\":\"noul\",\"noul\":true}}}",
            "{\"answers\":{\"r0\":{\"type\":\"boolean\",\"noul\":0.5}}}"]
        for value in invalid {
            XCTAssertThrowsError(try JevClient.ranked(memories: [memories[0]], data: Data(value.utf8), provider: .typesafe))
        }
        XCTAssertThrowsError(try JevClient.request(query: "a", memories: memories, provider: .typesafe, key: " "))
        XCTAssertThrowsError(try JevClient.request(query: " ", memories: memories, provider: .typesafe, key: "test"))
    }

    func testHTTPResponseAndSafeError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JevMockProtocol.self]
        let client = JevClient(session: URLSession(configuration: configuration))
        let ranked = try await client.rank(query: "launch", memories: [memories[0]], provider: .typesafe, key: "test-key")
        XCTAssertEqual(ranked.count, 1)
        let gateway = try await client.rank(query: "launch", memories: [memories[0]], provider: .vercel, key: "test-key")
        XCTAssertEqual(gateway.count, 1)
        do {
            _ = try await client.rank(query: "launch", memories: memories, provider: .vercel, key: "invalid-test-key")
            XCTFail("An HTTP error must fail.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API key"))
            XCTAssertFalse(error.localizedDescription.contains("secret-response-body"))
        }
    }
}

private final class JevMockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let direct = request.url?.host == "api.typesafe.ai"
        let valid = request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key"
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let answer = direct ? "{\"answers\":{\"r0\":{\"type\":\"noul\",\"noul\":0.9}}}" : "{\"answers\":{\"r0\":{\"type\":\"boolean\",\"probability\":0.9}}}"
        let body = valid ? answer : "secret-response-body"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
