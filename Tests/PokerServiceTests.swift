import Foundation
import Synchronization
import Testing
@testable import ModernPokerCore

struct PokerServiceTests {
    @Test func request_shouldSendJSONAndKeepBasePath() async throws {
        let exercise = Self.exercise
        let exerciseData = try JSONEncoder().encode(exercise)
        let connection = TestConnection { request in
            if request.url.path.hasSuffix("/decisions") {
                let body = try! JSONDecoder().decode(DecisionBody.self, from: request.body)
                let analysis = PokerEngine.analyze(exercise, action: body.action, estimate: PokerEngine.EquityEstimate(equity: 1, sampleCount: 0))
                return Stub(status: 200, data: try! JSONEncoder().encode(analysis))
            }
            return Stub(status: 201, data: exerciseData)
        }
        defer { connection.close() }
        let service = connection.service(base: "https://poker.test/backend/api")

        let received = try await service.nextExercise()
        let call = try await service.evaluate(received, action: .call)
        let fold = try await service.evaluate(received, action: .fold)

        #expect(received == exercise)
        #expect(call.isCorrect && !fold.isCorrect)
        let requests = connection.fixture.requests.withLock { $0 }
        #expect(requests.map(\.url.path) == [
            "/backend/api/v1/exercises",
            "/backend/api/v1/exercises/test_remote/decisions",
            "/backend/api/v1/exercises/test_remote/decisions"
        ])
        #expect(requests.allSatisfy { $0.method == "POST" && $0.contentType == "application/json" && $0.accept == "application/json" })
        #expect(try JSONSerialization.jsonObject(with: #require(requests.first).body) as? [String: String] == [:])
        #expect(try JSONDecoder().decode(DecisionBody.self, from: requests[1].body).action == .call)
        #expect(try JSONDecoder().decode(DecisionBody.self, from: requests[2].body).action == .fold)
    }

    @Test(arguments: [
        (404, "exercise_not_found", true),
        (410, "exercise_expired", true),
        (404, "exercise_expired", false),
        (410, "exercise_not_found", false),
        (422, "validation_error", false),
        (503, "simulation_unavailable", false)
    ])
    func decision_shouldPreserveDocumentedErrors(_ status: Int, _ code: String, _ unavailable: Bool) async throws {
        let message = "Rozdanie jest niedostępne. Wylosuj kolejne."
        let data = try JSONEncoder().encode(ErrorBody(code: code, message: message))
        let connection = TestConnection { _ in Stub(status: status, data: data) }
        defer { connection.close() }
        do {
            _ = try await connection.service().evaluate(Self.exercise, action: .call)
            Issue.record("The server error was accepted")
        } catch let error as PokerError {
            guard case let .api(receivedStatus, receivedCode, receivedMessage, isDecision) = error else {
                Issue.record("Expected a documented API error: \(error)")
                return
            }
            #expect(receivedStatus == status)
            #expect(receivedCode == code)
            #expect(receivedMessage == message)
            #expect(isDecision)
            #expect(error.isExerciseUnavailable == unavailable)
            #expect(error.localizedDescription == message)
        }
    }

    @Test func create_shouldNotTreat404AsExpiredExercise() async throws {
        let data = try JSONEncoder().encode(ErrorBody(code: "exercise_not_found", message: "Nie znaleziono endpointu."))
        let connection = TestConnection { _ in Stub(status: 404, data: data) }
        defer { connection.close() }
        do {
            _ = try await connection.service().nextExercise()
            Issue.record("The server error was accepted")
        } catch let error as PokerError {
            #expect(!error.isExerciseUnavailable)
            guard case .api(status: 404, code: "exercise_not_found", message: _, isDecision: false) = error else {
                Issue.record("Expected a create API error")
                return
            }
        }
    }

    @Test(arguments: ["malformed", "unknown-code", "long-message", "blank-message", "wrong-mime"])
    func failure_shouldFallBackToStatus_whenErrorBodyIsUntrusted(_ variant: String) async throws {
        let data: Data
        switch variant {
        case "malformed": data = Data("{broken".utf8)
        case "unknown-code": data = try JSONEncoder().encode(ErrorBody(code: "unexpected_internal_error", message: "Test"))
        case "long-message": data = try JSONEncoder().encode(ErrorBody(code: "validation_error", message: String(repeating: "a", count: 1_001)))
        case "blank-message": data = try JSONEncoder().encode(ErrorBody(code: "validation_error", message: " \n\t"))
        default: data = Data("<html>Error</html>".utf8)
        }
        let connection = TestConnection { _ in
            Stub(status: 404, data: data, mime: variant == "wrong-mime" ? "text/html" : "application/json")
        }
        defer { connection.close() }
        do {
            _ = try await connection.service().evaluate(Self.exercise, action: .call)
            Issue.record("The malformed server error was accepted")
        } catch let error as PokerError {
            guard case .server(status: 404) = error else {
                Issue.record("Expected status-only fallback: \(error)")
                return
            }
            #expect(!error.isExerciseUnavailable)
        }
    }

    @Test(arguments: [201, 503], [true, false])
    func response_shouldRejectOversizedBody_withOrWithoutLength(_ status: Int, _ declaresLength: Bool) async throws {
        let data = Data(repeating: 32, count: 65_537)
        let connection = TestConnection { _ in Stub(status: status, data: data, declaresLength: declaresLength) }
        defer { connection.close() }
        do {
            _ = try await connection.service().nextExercise()
            Issue.record("Oversized response was accepted")
        } catch let error as PokerError {
            switch (status, error) {
            case (201, .invalidResponse), (503, .server(status: 503)): break
            default: Issue.record("Unexpected size limit error: \(error)")
            }
        }
    }

    @Test(arguments: ["malformed", "wrong-mime", "wrong-status"])
    func response_shouldRejectInvalidSuccess(_ variant: String) async throws {
        let data = variant == "malformed" ? Data("{broken".utf8) : try JSONEncoder().encode(Self.exercise)
        let connection = TestConnection { _ in
            Stub(status: variant == "wrong-status" ? 200 : 201, data: data, mime: variant == "wrong-mime" ? "text/plain" : "application/json")
        }
        defer { connection.close() }
        do {
            _ = try await connection.service().nextExercise()
            Issue.record("Invalid success was accepted")
        } catch let error as PokerError {
            switch (variant, error) {
            case ("wrong-status", .server(status: 200)), ("malformed", .invalidResponse), ("wrong-mime", .invalidResponse): break
            default: Issue.record("Unexpected validation error: \(error)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func request_shouldCancelUnderlyingStreamingTask() async throws {
        let connection = TestConnection { _ in
            Stub(status: 201, data: Data("{".utf8), declaresLength: false, finishes: false)
        }
        defer { connection.close() }
        let service = connection.service()
        let task = Task { try await service.nextExercise() }
        defer { task.cancel() }
        var started = connection.fixture.startedSignal.stream.makeAsyncIterator()
        _ = try #require(await started.next())
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled request completed")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        var stopped = connection.fixture.stoppedSignal.stream.makeAsyncIterator()
        _ = try #require(await stopped.next())
    }

    @Test(arguments: [
        "ftp://localhost:8080", "http://", "http://localhost:0", "http://localhost:65536",
        "https://user:password@poker.test", "https://poker.test?token=x", "https://poker.test/#fragment", "poker.test"
    ])
    func backendAddress_shouldRejectInvalidAddress(_ address: String) {
        #expect(throws: PokerError.self) { try BackendAddress.parse(address) }
    }

    @Test(arguments: [
        "http://localhost:8080", "http://127.0.0.1:1", "http://[::1]:65535",
        "http://192.168.1.20:8080/api", "http://macbook.local:8080", "https://poker.test/api/v2"
    ])
    func backendAddress_shouldAcceptValidBaseAddress(_ address: String) throws {
        #expect(try BackendAddress.parse(" \(address)\n").absoluteString == address)
    }

    private struct DecisionBody: Codable {
        let action: PokerAction
    }

    private struct ErrorBody: Encodable {
        let code: String
        let message: String
    }

    private static let exercise = PokerExercise(
        id: "test_remote", heroCards: [PokerCard(rank: 14, suit: .spades), PokerCard(rank: 13, suit: .spades)],
        board: [PokerCard(rank: 12, suit: .spades), PokerCard(rank: 11, suit: .spades), PokerCard(rank: 10, suit: .spades)],
        pot: 150, callAmount: 50,
        opponentRange: OpponentRange(id: "pairs", name: "Pary", description: "Mocne pary", hands: ["AA", "KK"])
    )
}

private struct RequestRecord: Sendable {
    let url: URL
    let method: String?
    let body: Data
    let contentType: String?
    let accept: String?
}

private struct Stub: Sendable {
    let status: Int
    let data: Data
    var mime = "application/json"
    var declaresLength = true
    var finishes = true
}

private final class Fixture: Sendable {
    let handler: @Sendable (RequestRecord) -> Stub
    let requests = Mutex<[RequestRecord]>([])
    let startedSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let stoppedSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    init(handler: @escaping @Sendable (RequestRecord) -> Stub) {
        self.handler = handler
    }
}

private struct TestConnection {
    let id: String
    let fixture: Fixture
    let session: URLSession

    init(handler: @escaping @Sendable (RequestRecord) -> Stub) {
        let id = UUID().uuidString
        let fixture = Fixture(handler: handler)
        self.id = id
        self.fixture = fixture
        FixtureProtocol.fixtures.withLock { $0[id] = fixture }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Fixture-ID": id]
        session = URLSession(configuration: configuration)
    }

    func service(base: String = "https://poker.test") -> PokerService {
        PokerService(baseURL: URL(string: base)!, session: session)
    }

    func close() {
        session.invalidateAndCancel()
        FixtureProtocol.fixtures.withLock { $0[id] = nil }
    }
}

private final class FixtureProtocol: URLProtocol {
    // Each test owns a UUID-scoped immutable handler; the registry and observations are locked.
    static let fixtures = Mutex<[String: Fixture]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Fixture-ID"),
              let fixture = Self.fixtures.withLock({ $0[id] }), let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let record = RequestRecord(
            url: url, method: request.httpMethod, body: bodyData(),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            accept: request.value(forHTTPHeaderField: "Accept")
        )
        fixture.requests.withLock { $0.append(record) }
        let stub = fixture.handler(record)
        var headers = ["Content-Type": stub.mime]
        if stub.declaresLength { headers["Content-Length"] = String(stub.data.count) }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        fixture.startedSignal.continuation.yield(())
        if stub.finishes { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Fixture-ID"),
              let fixture = Self.fixtures.withLock({ $0[id] }) else { return }
        fixture.stoppedSignal.continuation.yield(())
    }

    private func bodyData() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
