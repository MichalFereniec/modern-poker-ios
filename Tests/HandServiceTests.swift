import Foundation
import Synchronization
import Testing
@testable import ModernPokerCore

struct HandServiceTests {
    @Test func transport_shouldPreserveRequestIdentityAndDecodeAuthoritativeTransition() async throws {
        let examples = try HandAPIExamples()
        let initialData = try JSONEncoder().encode(examples.initial)
        let responseData = try JSONEncoder().encode(examples.transitions[0].response)
        let connection = HandConnection { record in
            record.url.path.hasSuffix("/actions")
                ? HandStub(status: 200, data: responseData)
                : HandStub(status: 201, data: initialData)
        }
        defer { connection.close() }
        let service = connection.service(base: "https://poker.test/backend")
        let hand = try await service.startHand(requestId: "stable_create_id")
        let request = examples.transitions[0].request
        let first = try await service.act(on: hand, request: request)
        // A retry must keep its OLD revision and key after an unknown commit outcome.
        let retry = try await service.act(on: hand, request: request)

        #expect(hand == examples.initial)
        #expect(first == examples.transitions[0].response)
        #expect(retry == first)
        let records = connection.fixture.records.withLock { $0 }
        #expect(records.map(\.url.path) == [
            "/backend/v2/hands",
            "/backend/v2/hands/\(hand.id)/actions",
            "/backend/v2/hands/\(hand.id)/actions"
        ])
        #expect(records.allSatisfy { $0.method == "POST" && $0.contentType == "application/json" && $0.accept == "application/json" })
        #expect(try JSONSerialization.jsonObject(with: records[0].body) as? [String: String] == ["requestId": "stable_create_id"])
        #expect(try JSONDecoder().decode(HandActionRequest.self, from: records[1].body) == request)
        #expect(try JSONDecoder().decode(HandActionRequest.self, from: records[2].body) == request)
    }

    @Test func openAPIExamples_shouldValidateEveryStreetAndFoldTransition() throws {
        let examples = try HandAPIExamples()
        var previous = examples.initial
        try HandValidation.validate(previous)
        for step in examples.transitions {
            try HandValidation.validate(step.response, previous: previous, request: step.request)
            previous = step.response.hand
        }
        #expect(previous.street == .showdown)
        #expect(previous.result?.winner == .hero)
        #expect(previous.heroStack + previous.opponentStack == examples.initial.pot + examples.initial.heroStack + examples.initial.opponentStack)
        try HandValidation.validate(examples.fold.response, previous: examples.facing, request: examples.fold.request)
        #expect(examples.fold.response.hand.result?.opponentCards.isEmpty == true)
    }

    @Test func response_shouldRejectDifferentHandEvenWhenItsStateIsOtherwiseValid() async throws {
        let examples = try HandAPIExamples()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(examples.transitions[0].response)) as? [String: Any])
        var handObject = try #require(object["hand"] as? [String: Any])
        handObject["id"] = "different_hand"
        object["hand"] = handObject
        let body = try JSONSerialization.data(withJSONObject: object)
        let connection = HandConnection { _ in HandStub(status: 200, data: body) }
        defer { connection.close() }
        await #expect(throws: PokerError.self) {
            try await connection.service().act(on: examples.initial, request: examples.transitions[0].request)
        }
    }

    @Test(arguments: [
        (404, "hand_not_found", true), (410, "hand_expired", true), (409, "stale_revision", true),
        (409, "idempotency_conflict", false), (422, "illegal_action", false),
        (404, "hand_expired", false), (410, "hand_not_found", false), (422, "stale_revision", false)
    ])
    func action_shouldScopeReplacementToDocumentedRecoverableErrors(_ status: Int, _ code: String, _ unavailable: Bool) async throws {
        let examples = try HandAPIExamples()
        let data = try JSONSerialization.data(withJSONObject: ["code": code, "message": "Rozdanie jest niedostępne."])
        let connection = HandConnection { _ in HandStub(status: status, data: data) }
        defer { connection.close() }
        do {
            _ = try await connection.service().act(on: examples.initial, request: examples.transitions[0].request)
            Issue.record("Accepted an API failure")
        } catch let error as PokerError {
            #expect(error.isHandUnavailable == unavailable)
            guard case let .api(receivedStatus, receivedCode, message, isDecision) = error else {
                Issue.record("Expected structured hand API failure")
                return
            }
            #expect(receivedStatus == status && receivedCode == code && isDecision)
            #expect(message == "Rozdanie jest niedostępne.")
        }
    }

    @Test func create_shouldNotTreatMissingEndpointAsAnUnavailableHand() async throws {
        let data = try JSONSerialization.data(withJSONObject: ["code": "hand_not_found", "message": "Nie znaleziono endpointu."])
        let connection = HandConnection { _ in HandStub(status: 404, data: data) }
        defer { connection.close() }
        do {
            _ = try await connection.service().startHand(requestId: "create_id")
            Issue.record("Accepted missing create endpoint")
        } catch let error as PokerError {
            #expect(!error.isHandUnavailable)
        }
    }

    @Test func localRetry_shouldReturnIdenticalDealAndNeverChargeActionTwice() async throws {
        let service = PokerService()
        let hand = try await service.startHand(requestId: "create_once")
        #expect(try await service.startHand(requestId: "create_once") == hand)
        let option = try #require(hand.availableActions.first { $0.action == .call })
        let request = HandActionRequest(requestId: "pay_once", expectedRevision: hand.revision, action: option.action, amount: option.amount)
        let first = try await service.act(on: hand, request: request)
        let retry = try await service.act(on: hand, request: request)
        #expect(retry == first)
        #expect(retry.hand.heroStack == hand.heroStack - option.amount)

        let stale = HandActionRequest(requestId: "different_request", expectedRevision: hand.revision, action: option.action, amount: option.amount)
        do {
            _ = try await service.act(on: hand, request: stale)
            Issue.record("Stale revision was charged again")
        } catch let error as PokerError {
            #expect(error.isHandUnavailable)
        }
        let conflicting = HandActionRequest(requestId: "pay_once", expectedRevision: hand.revision, action: .fold, amount: 0)
        do {
            _ = try await service.act(on: hand, request: conflicting)
            Issue.record("Reused request key accepted a different action")
        } catch let error as PokerError {
            guard case .api(status: 409, code: "idempotency_conflict", message: _, isDecision: true) = error else {
                Issue.record("Expected idempotency conflict")
                return
            }
            #expect(!error.isHandUnavailable)
        }
    }

    @Test func localCancelledAction_shouldLeaveOriginalRevisionAvailableForRetry() async throws {
        let service = PokerService()
        let hand = try await service.startHand(requestId: "cancel_create")
        let option = try #require(hand.availableActions.first { $0.action == .call })
        let request = HandActionRequest(requestId: "cancel_action", expectedRevision: hand.revision, action: option.action, amount: option.amount)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.act(on: hand, request: request)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let result = try await service.act(on: hand, request: request)
        #expect(result.hand.revision > hand.revision)
        #expect(result.hand.heroStack == hand.heroStack - option.amount)
    }
}

private struct HandAPIExamples {
    struct Transition {
        let request: HandActionRequest
        let response: HandActionResponse
    }

    let initial: PokerHand
    let transitions: [Transition]
    let facing: PokerHand
    let fold: Transition

    init() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/openapi.json")
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let steps = try #require(document["x-example-sequence"] as? [[String: Any]])
        func body<T: Decodable>(_ index: Int, _ kind: String, as type: T.Type) throws -> T {
            let message = try #require(steps[index][kind] as? [String: Any])
            let value = try #require(message["body"])
            return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
        }
        initial = try body(0, "response", as: PokerHand.self)
        transitions = try (1...3).map {
            Transition(request: try body($0, "request", as: HandActionRequest.self), response: try body($0, "response", as: HandActionResponse.self))
        }
        facing = try body(4, "response", as: PokerHand.self)
        fold = Transition(request: try body(5, "request", as: HandActionRequest.self), response: try body(5, "response", as: HandActionResponse.self))
    }
}

private struct HandRecord: Sendable {
    let url: URL
    let method: String?
    let body: Data
    let contentType: String?
    let accept: String?
}

private struct HandStub: Sendable {
    let status: Int
    let data: Data
}

private final class HandFixture: Sendable {
    let handler: @Sendable (HandRecord) -> HandStub
    let records = Mutex<[HandRecord]>([])
    init(handler: @escaping @Sendable (HandRecord) -> HandStub) { self.handler = handler }
}

private struct HandConnection {
    let id: String
    let fixture: HandFixture
    let session: URLSession

    init(handler: @escaping @Sendable (HandRecord) -> HandStub) {
        let id = UUID().uuidString
        let fixture = HandFixture(handler: handler)
        self.id = id
        self.fixture = fixture
        HandFixtureProtocol.fixtures.withLock { $0[id] = fixture }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HandFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Hand-Fixture-ID": id]
        session = URLSession(configuration: configuration)
    }

    func service(base: String = "https://poker.test") -> PokerService {
        PokerService(baseURL: URL(string: base)!, session: session)
    }

    func close() {
        session.invalidateAndCancel()
        HandFixtureProtocol.fixtures.withLock { $0[id] = nil }
    }
}

private final class HandFixtureProtocol: URLProtocol {
    static let fixtures = Mutex<[String: HandFixture]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Hand-Fixture-ID"),
              let fixture = Self.fixtures.withLock({ $0[id] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let record = HandRecord(url: url, method: request.httpMethod, body: requestBody(), contentType: request.value(forHTTPHeaderField: "Content-Type"), accept: request.value(forHTTPHeaderField: "Accept"))
        fixture.records.withLock { $0.append(record) }
        let stub = fixture.handler(record)
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": String(stub.data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBody() -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
