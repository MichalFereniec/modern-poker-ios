import Foundation
import Testing
@testable import ModernPokerCore

@Suite("Multi-street training session")
@MainActor
struct TrainingStoreTests {
    @Test("Five completed hands, not five decisions, finish a session")
    func completeSession() async throws {
        try await withDefaults { defaults in
            let service = SessionService()
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            await store.start()
            await store.next()
            #expect(await service.creationRequests.count == 1)

            for number in 1...5 {
                let first = try #require(store.hand)
                #expect(store.handNumber == number)
                for (index, action) in [HandAction.call, .check, .call].enumerated() {
                    let before = try #require(store.hand)
                    #expect(store.analysis == nil)
                    #expect(store.decisionHand == nil)
                    await store.choose(try option(action, in: before))
                    let after = try #require(store.hand)
                    #expect(after.id == first.id)
                    #expect(after.heroCards == first.heroCards)
                    #expect(Array(after.board.prefix(before.board.count)) == before.board)
                    #expect(after.board.count == min(before.board.count + 1, 5))
                    #expect(after.revision == before.revision + 1)
                    #expect(store.decisionHand == before)
                    #expect(store.analysis?.street == before.street)
                    #expect(store.analysis?.action == action)
                    #expect(store.decisions.count == index + 1)
                    #expect(store.decisionCount == (number - 1) * 3 + index + 1)
                    #expect(store.results.count == number - (index == 2 ? 0 : 1))
                    #expect(store.screen == .training)

                    // Neither another action nor "next" may dismiss the teaching result.
                    await store.choose(HandActionOption(action: .fold, amount: 0))
                    await store.next()
                    #expect(store.analysis != nil)
                    #expect(store.hand == after)
                    #expect(await service.creationRequests.count == number)
                    store.continueHand()
                    store.continueHand()
                    #expect(store.analysis == nil)
                    #expect(store.decisionHand == nil)
                    if index < 2 {
                        await store.next()
                        #expect(store.hand == after)
                        #expect(after.result == nil)
                    }
                }
                #expect(store.hand?.status == .completed)
                #expect(store.hand?.result?.reason == .showdown)
                #expect(store.handNumber == number)
                await store.next()
            }

            #expect(store.screen == .summary)
            #expect(store.results.count == 5)
            #expect(Set(store.results.map(\.id)).count == 5)
            #expect(store.decisionCount == 15)
            #expect(await service.actionRequests.count == 15)
            #expect(await service.creationRequests.count == 5)
            await store.start()
            #expect(store.screen == .training)
            #expect(store.results.isEmpty)
            #expect(store.decisionCount == 0)
            #expect(store.handNumber == 1)
            #expect(await service.creationRequests.count == 6)
        }
    }

    @Test("Folding completes exactly one hand and preserves its analysis until continued")
    func foldEndsHand() async throws {
        try await withDefaults { defaults in
            let service = SessionService()
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            let first = try #require(store.hand)
            await store.choose(try option(.fold, in: first))
            #expect(store.hand?.result?.reason == .fold)
            #expect(store.hand?.result?.opponentCards.isEmpty == true)
            #expect(store.results.count == 1)
            #expect(store.decisionCount == 1)
            #expect(store.decisionHand == first)
            await store.next()
            #expect(store.hand?.id == first.id)
            #expect(store.analysis != nil)
            store.continueHand()
            await store.next()
            let second = try #require(store.hand)
            #expect(second.id != first.id)
            #expect(store.handNumber == 2)
            #expect(store.results.count == 1)
            #expect(store.decisions.isEmpty)
            await store.next()
            #expect(store.hand == second)
            #expect(await service.creationRequests.count == 2)
        }
    }

    @Test("Concurrent action taps submit one request and never score twice")
    func repeatedTapsWhileEvaluating() async throws {
        try await withDefaults { defaults in
            let service = DeferredSessionService(mode: .action)
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            let hand = try #require(store.hand)
            let call = try option(.call, in: hand)
            let task = Task { await store.choose(call) }
            await service.waitUntilPaused()
            #expect(store.isEvaluating)
            await store.choose(try option(.fold, in: hand))
            await store.choose(call)
            await store.retry()
            await store.start()
            await store.next()
            store.continueHand()
            #expect(await service.base.actionRequests.count == 1)
            await service.resume()
            await task.value
            #expect(!store.isBusy)
            #expect(store.decisionCount == 1)
            #expect(store.decisions.count == 1)
            #expect(store.results.isEmpty)
            #expect(store.hand?.street == .turn)
        }
    }

    @Test("A committed action returning 503 is retried with its exact request and counted once")
    func retryCommittedDecision() async throws {
        try await withDefaults { defaults in
            let service = SessionService(actionFailures: [1: .server(status: 503)], commitBeforeFailure: true)
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            let original = try #require(store.hand)
            await store.choose(try option(.raise, in: original))
            #expect(store.errorMessage != nil)
            #expect(store.errorRecovery == .retry)
            #expect(!store.isBusy)
            #expect(store.hand == original)
            #expect(store.decisionCount == 0)
            #expect(store.results.isEmpty)
            let request = try #require(await service.actionRequests.first)
            #expect(UUID(uuidString: request.requestId) != nil)
            #expect(request.expectedRevision == original.revision)
            #expect(request.action == .raise)
            #expect(request.amount == 150)
            await store.choose(try option(.fold, in: original))
            #expect(await service.actionRequests.count == 1)
            await store.retry()
            #expect(store.errorMessage == nil)
            #expect(store.hand?.revision == 1)
            #expect(store.analysis?.action == .raise)
            #expect(store.decisionHand == original)
            #expect(store.decisionCount == 1)
            #expect(store.decisions.count == 1)
            #expect(await service.actionRequests == [request, request])
            #expect(await service.actedHandIDs == [original.id, original.id])
            #expect(await service.committedActions == 1)
            await store.retry()
            #expect(await service.actionRequests.count == 2)
        }
    }

    @Test("Creation retry reuses its UUID after the backend already created a hand")
    func retryCreation() async throws {
        try await withDefaults { defaults in
            let service = SessionService(creationFailures: [1: .server(status: 503)])
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            #expect(store.hand == nil)
            #expect(store.errorMessage != nil)
            #expect(!store.isBusy)
            let requestID = try #require(await service.creationRequests.first)
            #expect(UUID(uuidString: requestID) != nil)
            await store.retry()
            #expect(store.errorMessage == nil)
            #expect(store.hand?.id == "session-hand-1")
            #expect(await service.creationRequests == [requestID, requestID])
            #expect(await service.createdHands == 1)
        }
    }

    @Test("A scoped expired-hand response replaces only the unfinished hand")
    func replaceExpiredHand() async throws {
        try await withDefaults { defaults in
            let expired = PokerError.api(status: 410, code: "hand_expired", message: "Rozdanie wygasło.", isDecision: true)
            let service = SessionService(actionFailures: [2: expired])
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            await store.choose(try option(.fold, in: #require(store.hand)))
            let completed = try #require(store.results.first)
            store.continueHand()
            await store.next()
            let expiredHand = try #require(store.hand)
            await store.choose(try option(.call, in: expiredHand))
            #expect(store.errorRecovery == .replaceHand)
            #expect(store.errorMessage == "Rozdanie wygasło.")
            #expect(store.results == [completed])
            await store.retry()
            #expect(store.errorMessage == nil)
            #expect(store.hand?.id != expiredHand.id)
            #expect(store.handNumber == 2)
            #expect(store.results == [completed])
            #expect(store.decisionCount == 1)
            #expect(await service.actionRequests.count == 2)
            #expect(await service.creationRequests.count == 3)
            await store.choose(try option(.fold, in: #require(store.hand)))
            #expect(store.results.count == 2)
        }
    }

    @Test("A generic endpoint 404 retries the current hand instead of replacing it")
    func missingEndpointIsNotAnExpiredHand() async throws {
        try await withDefaults { defaults in
            let service = SessionService(actionFailures: [1: .server(status: 404)])
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            let original = try #require(store.hand)
            await store.choose(try option(.call, in: original))
            #expect(store.errorRecovery == .retry)
            #expect(store.hand == original)
            await store.retry()
            #expect(store.hand?.id == original.id)
            #expect(store.hand?.street == .turn)
            #expect(await service.creationRequests.count == 1)
            let requests = await service.actionRequests
            #expect(requests.count == 2)
            #expect(requests.first == requests.last)
        }
    }

    @Test("Cancelling a load cancels its request and clears the loading screen")
    func cancelLoading() async throws {
        try await withDefaults { defaults in
            let service = DeferredSessionService(mode: .creation)
            let store = TrainingStore(service: service, defaults: defaults)
            let task = Task { await store.start() }
            await service.waitUntilPaused()
            #expect(store.isLoading)
            task.cancel()
            await task.value
            #expect(await service.wasCancelled)
            #expect(store.screen == .home)
            #expect(store.hand == nil)
            #expect(!store.isBusy)
            #expect(store.errorMessage == nil)
        }
    }

    @Test("Cancelled submission preserves its exact request because the backend may have committed it")
    func cancelActionThenRetry() async throws {
        try await withDefaults { defaults in
            let service = DeferredSessionService(mode: .action)
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            let original = try #require(store.hand)
            let call = try option(.call, in: original)
            let task = Task { await store.choose(call) }
            await service.waitUntilPaused()
            task.cancel()
            await task.value
            #expect(await service.wasCancelled)
            #expect(store.screen == .training)
            #expect(store.hand == original)
            #expect(!store.isBusy)
            #expect(store.errorMessage != nil)
            #expect(store.errorRecovery == .retry)
            #expect(store.results.isEmpty)
            #expect(store.analysis == nil)
            await store.choose(try option(.fold, in: original))
            #expect(await service.base.actionRequests.count == 1)
            await store.retry()
            let requests = await service.base.actionRequests
            #expect(requests.count == 2)
            #expect(requests.first == requests.last)
            #expect(await service.base.committedActions == 1)
            #expect(store.decisionCount == 1)
            #expect(store.hand?.street == .turn)
            #expect(store.errorMessage == nil)
        }
    }

    @Test("Leaving rejects a late action response even when the backend ignores cancellation")
    func lateActionCannotReopenSession() async throws {
        try await withDefaults { defaults in
            let service = DeferredSessionService(mode: .action, honorsCancellation: false)
            let store = TrainingStore(service: service, defaults: defaults)
            await store.start()
            let fold = try option(.fold, in: #require(store.hand))
            let task = Task { await store.choose(fold) }
            await service.waitUntilPaused()
            store.leaveSession()
            await service.resume()
            await task.value
            expectLeftSession(store)
        }
    }

    @Test("Leaving rejects a late creation response even when the backend ignores cancellation")
    func lateCreationCannotReopenSession() async throws {
        try await withDefaults { defaults in
            let service = DeferredSessionService(mode: .creation, honorsCancellation: false)
            let store = TrainingStore(service: service, defaults: defaults)
            let task = Task { await store.start() }
            await service.waitUntilPaused()
            store.leaveSession()
            await service.resume()
            await task.value
            expectLeftSession(store)
        }
    }

    @Test("Invalid persisted backend settings remain visible with no silent local fallback")
    func invalidPersistedSettings() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: "modernPoker.usesBackend")
            defaults.set("not a server address", forKey: "modernPoker.serverAddress")
            let store = TrainingStore(defaults: defaults)
            await store.start()
            #expect(store.usesBackend)
            #expect(store.errorRecovery == .settings)
            #expect(store.hand == nil)
            #expect(!store.isBusy)
            #expect(store.errorMessage != nil)
            await store.retry()
            #expect(store.hand == nil)
            #expect(!store.configure(backend: true, address: "https://user:password@example.com"))
            #expect(store.usesBackend)
            #expect(store.configure(backend: false, address: "http://localhost:8080"))
            await store.start()
            #expect(!store.usesBackend)
            #expect(store.hand != nil)
            #expect(store.errorMessage == nil)
        }
    }

    private func option(_ action: HandAction, in hand: PokerHand) throws -> HandActionOption {
        try #require(hand.availableActions.first { $0.action == action })
    }

    private func expectLeftSession(_ store: TrainingStore) {
        #expect(store.screen == .home)
        #expect(store.results.isEmpty)
        #expect(store.decisions.isEmpty)
        #expect(store.decisionCount == 0)
        #expect(store.analysis == nil)
        #expect(store.decisionHand == nil)
        #expect(store.hand == nil)
        #expect(!store.isBusy)
        #expect(store.errorMessage == nil)
    }

    private func withDefaults(_ operation: @MainActor (UserDefaults) async throws -> Void) async throws {
        let suiteName = "ModernPoker.SessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try await operation(defaults)
    }
}

private actor SessionService: HandServing {
    let creationFailures: [Int: PokerError]
    let actionFailures: [Int: PokerError]
    let commitBeforeFailure: Bool
    private(set) var creationRequests: [String] = []
    private(set) var actionRequests: [HandActionRequest] = []
    private(set) var actedHandIDs: [String] = []
    private(set) var committedActions = 0
    private var creationCache: [String: PokerHand] = [:]
    private var actionCache: [String: HandActionResponse] = [:]
    var createdHands: Int { creationCache.count }

    init(
        creationFailures: [Int: PokerError] = [:],
        actionFailures: [Int: PokerError] = [:],
        commitBeforeFailure: Bool = false
    ) {
        self.creationFailures = creationFailures
        self.actionFailures = actionFailures
        self.commitBeforeFailure = commitBeforeFailure
    }

    func startHand(requestId: String) async throws -> PokerHand {
        creationRequests.append(requestId)
        if let cached = creationCache[requestId] { return cached }
        let hand = sessionHand(id: "session-hand-\(creationCache.count + 1)")
        creationCache[requestId] = hand
        if let failure = creationFailures[creationRequests.count] { throw failure }
        return hand
    }

    func act(on hand: PokerHand, request: HandActionRequest) async throws -> HandActionResponse {
        actionRequests.append(request)
        actedHandIDs.append(hand.id)
        if let cached = actionCache[request.requestId] { return cached }
        let failure = actionFailures[actionRequests.count]
        if let failure, !commitBeforeFailure { throw failure }
        let response = sessionResponse(hand: hand, request: request)
        actionCache[request.requestId] = response
        committedActions += 1
        if let failure { throw failure }
        return response
    }
}

private actor DeferredSessionService: HandServing {
    enum Mode { case creation, action }
    let mode: Mode
    let honorsCancellation: Bool
    let base = SessionService()
    private(set) var wasCancelled = false
    private var started = false
    private var continuation: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(mode: Mode, honorsCancellation: Bool = true) {
        self.mode = mode
        self.honorsCancellation = honorsCancellation
    }

    func startHand(requestId: String) async throws -> PokerHand {
        let hand = try await base.startHand(requestId: requestId)
        if mode == .creation, !started { try await pause() }
        return hand
    }

    func act(on hand: PokerHand, request: HandActionRequest) async throws -> HandActionResponse {
        // Commit before waiting, like a server that completed work before a connection dropped.
        let response = try await base.act(on: hand, request: request)
        if mode == .action, !started { try await pause() }
        return response
    }

    func waitUntilPaused() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    private func pause() async throws {
        let honorsCancellation = honorsCancellation
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started = true
                startWaiters.forEach { $0.resume() }
                startWaiters = []
            }
        } onCancel: {
            if honorsCancellation {
                Task { await self.cancel() }
            }
        }
    }

    private func cancel() {
        wasCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private func sessionHand(id: String) -> PokerHand {
    PokerHand(
        id: id, revision: 0, street: .flop, status: .awaitingAction,
        heroCards: [PokerCard(rank: 14, suit: .spades), PokerCard(rank: 14, suit: .hearts)],
        board: [PokerCard(rank: 2, suit: .clubs), PokerCard(rank: 7, suit: .diamonds), PokerCard(rank: 9, suit: .spades)],
        pot: 150, heroStack: 1_000, opponentStack: 950, toCall: 50,
        opponentRange: OpponentRange(id: "pairs", name: "Pary", description: "Wysokie pary.", hands: ["KK", "QQ"]),
        availableActions: [
            HandActionOption(action: .fold, amount: 0),
            HandActionOption(action: .call, amount: 50),
            HandActionOption(action: .raise, amount: 150)
        ],
        history: [HandHistoryEntry(id: "\(id)-opening", street: .flop, player: .opponent, action: .bet, amount: 50)],
        result: nil
    )
}

private func sessionResponse(hand: PokerHand, request: HandActionRequest) -> HandActionResponse {
    let folds = request.action == .fold
    let completes = folds || hand.street == .river
    let street: HandStreet = folds ? hand.street : (hand.street == .flop ? .turn : (hand.street == .turn ? .river : .showdown))
    let opponentCall = request.action == .raise || request.action == .bet ? max(0, request.amount - hand.toCall) : 0
    let settledPot = hand.pot + request.amount + opponentCall
    let nextBet = street == .river && !folds ? settledPot / 2 : 0
    let pot = settledPot + nextBet
    let board = hand.board + (folds || hand.street == .river ? [] : [
        hand.street == .flop ? PokerCard(rank: 3, suit: .hearts) : PokerCard(rank: 4, suit: .clubs)
    ])
    let result: HandResult? = completes ? HandResult(
        reason: folds ? .fold : .showdown,
        winner: folds ? .opponent : .hero,
        opponentCards: folds ? [] : [PokerCard(rank: 13, suit: .hearts), PokerCard(rank: 13, suit: .clubs)],
        heroPayout: folds ? 0 : pot,
        opponentPayout: folds ? pot : 0,
        summary: folds ? "Pas kończy rozdanie." : "Asy wygrywają z królami."
    ) : nil
    let options: [HandActionOption] = completes ? [] : (nextBet > 0 ? [
        HandActionOption(action: .fold, amount: 0),
        HandActionOption(action: .call, amount: nextBet)
    ] : [
        HandActionOption(action: .check, amount: 0),
        HandActionOption(action: .bet, amount: 100)
    ])
    let history = hand.history + [
        HandHistoryEntry(id: request.requestId, street: hand.street, player: .hero, action: request.action, amount: request.amount)
    ] + (opponentCall > 0 ? [
        HandHistoryEntry(id: "\(request.requestId)-call", street: hand.street, player: .opponent, action: .call, amount: opponentCall)
    ] : []) + (nextBet > 0 ? [
        HandHistoryEntry(id: "\(request.requestId)-bet", street: street, player: .opponent, action: .bet, amount: nextBet)
    ] : [])
    let next = PokerHand(
        id: hand.id, revision: hand.revision + 1, street: street,
        status: completes ? .completed : .awaitingAction,
        heroCards: hand.heroCards, board: board, pot: pot,
        heroStack: hand.heroStack - request.amount + (result?.heroPayout ?? 0),
        opponentStack: hand.opponentStack - opponentCall - nextBet + (result?.opponentPayout ?? 0),
        toCall: nextBet, opponentRange: hand.opponentRange,
        availableActions: options, history: history, result: result
    )
    let equity = 0.8
    let analysis = HandAnalysis(
        street: hand.street, action: request.action, equity: equity,
        requiredEquity: hand.toCall > 0 ? Double(hand.toCall) / Double(hand.pot + hand.toCall) : nil,
        callEV: hand.toCall > 0 ? equity * Double(hand.pot + hand.toCall) - Double(hand.toCall) : nil,
        sampleCount: 1_000, marginOfError: 0.03,
        explanation: "Ocena dotyczy informacji dostępnych przed ruchem."
    )
    return HandActionResponse(hand: next, analysis: analysis)
}
