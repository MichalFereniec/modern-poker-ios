import Foundation
import Synchronization
import Testing
@testable import ModernPokerCore

struct TutorBackendTests {
    @Test("Action waits for explicit continuation; uncertain commits are recovered without double betting")
    func recoverCommittedActionAndContinuation() async throws {
        let examples = try TutorExamples()
        let state = TutorFixture(examples: examples)
        let id = UUID().uuidString
        TutorProtocol.fixtures.withLock { $0[id] = state }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TutorProtocol.self]
        config.httpAdditionalHeaders = ["X-Tutor-Fixture": id]
        let session = URLSession(configuration: config)
        defer {
            session.invalidateAndCancel()
            TutorProtocol.fixtures.withLock { $0[id] = nil }
        }
        let service = TutorBackendService(baseURL: URL(string: "https://poker.test")!, session: session)
        let hand = try await service.startHand(requestId: UUID().uuidString)
        #expect(hand.backend?.stacks.count == 4)
        let request = HandActionRequest(requestId: UUID().uuidString, expectedRevision: hand.revision, action: .bet, amount: 10)
        let action = try await service.act(on: hand, request: request)
        #expect(action.hand.board == hand.board)
        #expect(action.hand.backend?.needsContinuation == true)
        #expect(action.analysis.teaching?.recommendation == "bet")
        #expect(action.analysis.street == .flop)
        #expect(try await service.act(on: hand, request: request) == action)
        let turn = try await service.advance(action.hand)
        #expect(turn.street == .turn && turn.board.count == 4)
        #expect(turn.heroCards == hand.heroCards)
        #expect(Array(turn.board.prefix(3)) == hand.board)
        #expect(turn.backend?.needsContinuation == false)
        let counts = state.state.withLock { ($0.actionPosts, $0.continuePosts, $0.headersValid) }
        #expect(counts.0 == 1 && counts.1 == 1 && counts.2)
    }

    @Test("Restored feedback keeps the original decision board and pot")
    func restoredDecisionSnapshot() throws {
        let examples = try TutorExamples()
        let pending = try examples.decode(TutorHand.self, data: examples.bet)
        let restored = try pending.decisionSnapshot()
        let snapshot = try #require(restored)
        #expect(snapshot.board.map(\.id) == pending.feedback?.decisionBoard)
        #expect(snapshot.pot == pending.feedback?.potBeforeAction)
        #expect(snapshot.backend?.stacks == pending.feedback?.stacksBeforeAction)
        #expect(snapshot.backend?.privateCards.isEmpty == true)
        #expect(snapshot.result == nil)
    }

    @Test("Fractional payouts and fold's hypothetical winners remain separate")
    func payoutsAndFoldReview() throws {
        let examples = try TutorExamples()
        var object = try #require(JSONSerialization.jsonObject(with: examples.showdown) as? [String: Any])
        var showdown = try #require(object["showdown"] as? [String: Any])
        showdown["winners"] = [0, 1, 2]
        showdown["payouts"] = [40.0 / 3, 40.0 / 3, 40.0 / 3, 0]
        object["showdown"] = showdown
        let hand = try examples.decode(TutorHand.self, data: JSONSerialization.data(withJSONObject: object)).mapped()
        #expect(hand.backend?.payouts.first == 40.0 / 3)
        #expect(hand.result?.winner == .tie)
        let folded = try examples.decode(TutorHand.self, data: examples.fold).mapped()
        #expect(folded.result?.reason == .fold)
        #expect(folded.backend?.isFoldReview == true)
        #expect(folded.backend?.payouts.first == 0)
        #expect(folded.backend?.winners.contains(0) == false)
        #expect(folded.backend?.privateCards.count == 4)
    }

    @Test("Backend continuation counts the hand only after showdown")
    @MainActor
    func storeContinuation() async throws {
        let examples = try TutorExamples()
        let initial = try examples.decode(TutorHand.self, data: examples.flop).mapped()
        let pendingDTO = try examples.decode(TutorHand.self, data: examples.bet)
        let pending = try pendingDTO.mapped()
        let analysis = try #require(pendingDTO.feedback).mapped()
        let finished = try examples.decode(TutorHand.self, data: examples.showdown).mapped()
        let service = TutorStoreService(initial: initial, pending: pending, analysis: analysis, finished: finished)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrainingStore(service: service, defaults: defaults)
        await store.start()
        await store.choose(HandActionOption(action: .bet, amount: 10))
        #expect(store.results.isEmpty)
        #expect(store.analysis != nil && store.hand?.backend?.needsContinuation == true)
        await store.advanceHand()
        #expect(store.results.count == 1)
        #expect(store.analysis == nil && store.hand?.status == .completed)
        await store.advanceHand()
        #expect(store.results.count == 1)
    }
}

private actor TutorStoreService: HandServing {
    let initial: PokerHand
    let pending: PokerHand
    let analysis: HandAnalysis
    let finished: PokerHand
    init(initial: PokerHand, pending: PokerHand, analysis: HandAnalysis, finished: PokerHand) {
        self.initial = initial; self.pending = pending; self.analysis = analysis; self.finished = finished
    }
    func startHand(requestId: String) async throws -> PokerHand { initial }
    func act(on hand: PokerHand, request: HandActionRequest) async throws -> HandActionResponse { HandActionResponse(hand: pending, analysis: analysis) }
    func advance(_ hand: PokerHand) async throws -> PokerHand { finished }
}

private struct TutorExamples: Sendable {
    let session: Data
    let flop: Data
    let bet: Data
    let turn: Data
    let showdown: Data
    let fold: Data
    init() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tutor.json")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        func data(_ name: String) throws -> Data { try JSONSerialization.data(withJSONObject: #require(object[name])) }
        session = try data("session"); flop = try data("flop"); bet = try data("bet")
        turn = try data("turn"); showdown = try data("showdown"); fold = try data("fold")
    }
    func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
private final class TutorFixture: Sendable {
    struct State { var stage = 0; var actionPosts = 0; var continuePosts = 0; var headersValid = true }
    let state = Mutex(State())
    let examples: TutorExamples
    init(examples: TutorExamples) { self.examples = examples }
    func response(_ request: URLRequest) -> (Int, Data) {
        state.withLock { state in
            state.headersValid = state.headersValid && request.value(forHTTPHeaderField: "Accept") == "application/json"
            let path = request.url!.path
            if path == "/api/v1/sessions" { return (200, Data("[".utf8) + examples.session + Data("]".utf8)) }
            if request.httpMethod == "GET", path.hasSuffix("/hands") == false { return (200, state.stage == 0 ? examples.flop : state.stage == 1 ? examples.bet : examples.turn) }
            if path.hasSuffix("/hands") {
                state.headersValid = state.headersValid && UUID(uuidString: request.value(forHTTPHeaderField: "Idempotency-Key") ?? "") != nil
                return (201, examples.flop)
            }
            if path.hasSuffix("/actions") { state.actionPosts += 1; state.stage = 1 }
            if path.hasSuffix("/continue") { state.continuePosts += 1; state.stage = 2 }
            // Simulate an action/continuation committed successfully, but whose reply was lost.
            return (503, Data("{\"code\":\"simulation_unavailable\",\"message\":\"lost reply\"}".utf8))
        }
    }
}
private final class TutorProtocol: URLProtocol {
    static let fixtures = Mutex<[String: TutorFixture]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Tutor-Fixture"), let fixture = Self.fixtures.withLock({ $0[id] }), let url = request.url else { return }
        let (status, data) = fixture.response(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
