import Foundation
import Observation

@MainActor
@Observable
final class TrainingStore {
    enum Screen: Equatable { case home, training, summary }
    enum ErrorRecovery { case retry, replaceHand, settings }

    private(set) var screen: Screen = .home
    private(set) var hand: PokerHand?
    private(set) var decisionHand: PokerHand?
    private(set) var analysis: HandAnalysis?
    private(set) var decisions: [HandAnalysis] = []
    private(set) var results: [PokerHand] = []
    private(set) var decisionCount = 0
    private(set) var isLoading = false
    private(set) var isEvaluating = false
    private(set) var errorMessage: String?
    private(set) var errorRecovery: ErrorRecovery = .retry
    private(set) var usesBackend: Bool
    private(set) var serverAddress: String

    let sessionLength = 5

    @ObservationIgnored private var service: any HandServing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var configurationIsInvalid: Bool
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private var creationRequestID: String?
    @ObservationIgnored private var pendingAction: HandActionRequest?
    @ObservationIgnored private var handTask: Task<PokerHand, Error>?
    @ObservationIgnored private var cleanupTask: Task<Void, Error>?
    @ObservationIgnored private var continuationTask: Task<PokerHand, Error>?
    @ObservationIgnored private var actionTask: Task<HandActionResponse, Error>?

    init(service: (any HandServing)? = nil, defaults: UserDefaults = .standard) {
        let address = defaults.string(forKey: "modernPoker.serverAddress") ?? "http://localhost:8080"
        let enabled = defaults.bool(forKey: "modernPoker.usesBackend")
        let baseURL = try? BackendAddress.parse(address)
        self.defaults = defaults
        serverAddress = address
        usesBackend = enabled
        configurationIsInvalid = service == nil && enabled && baseURL == nil
        self.service = service ?? Self.makeService(enabled: enabled, baseURL: baseURL)
    }

    var handNumber: Int { min(results.count + (hand?.status == .completed ? 0 : 1), sessionLength) }
    var isBusy: Bool { isLoading || isEvaluating }

    func start() async {
        guard !Task.isCancelled, screen == .home || screen == .summary else { return }
        leaveSession()
        screen = .training
        await loadHand()
    }

    private static func makeService(enabled: Bool, baseURL: URL?) -> any HandServing {
        if enabled, let baseURL { return TutorBackendService(baseURL: baseURL) }
        return PokerService()
    }

    func leaveSession() {
        handTask?.cancel()
        actionTask?.cancel()
        continuationTask?.cancel()
        continuationTask = nil
        let service = service
        let previousCleanup = cleanupTask
        cleanupTask = Task {
            _ = try? await previousCleanup?.value
            try await service.endSession()
        }
        handTask = nil
        actionTask = nil
        operationID = UUID()
        screen = .home
        hand = nil
        decisionHand = nil
        analysis = nil
        decisions = []
        results = []
        decisionCount = 0
        errorMessage = nil
        errorRecovery = .retry
        creationRequestID = nil
        pendingAction = nil
        isLoading = false
        isEvaluating = false
    }

    /// A separate action prevents a repeated analysis tap from skipping the hand result.
    func continueHand() {
        guard screen == .training, analysis != nil, !isBusy, hand?.backend?.needsContinuation != true else { return }
        analysis = nil
        decisionHand = nil
    }

    func advanceHand() async {
        guard screen == .training, analysis != nil, let hand, !isBusy else { return }
        guard hand.backend?.needsContinuation == true else { continueHand(); return }
        let token = UUID()
        operationID = token
        isEvaluating = true
        errorMessage = nil
        let service = service
        let task = Task { try await service.advance(hand) }
        continuationTask = task
        defer {
            if operationID == token { isEvaluating = false; continuationTask = nil }
        }
        do {
            let nextHand = try await result(of: task)
            guard operationID == token else { return }
            self.hand = nextHand
            analysis = nil
            decisionHand = nil
            recordCompleted(nextHand)
        } catch {
            guard operationID == token else { return }
            errorMessage = message(for: error)
        }
    }

    private func recordCompleted(_ hand: PokerHand) {
        if hand.status == .completed, !results.contains(where: { $0.id == hand.id }) { results.append(hand) }
    }

    func next() async {
        guard !Task.isCancelled, screen == .training, analysis == nil,
              hand?.status == .completed, !isBusy else { return }
        if results.count >= sessionLength {
            do { try await service.endSession(); screen = .summary }
            catch { errorMessage = message(for: error) }
        } else {
            creationRequestID = nil
            await loadHand()
        }
    }

    func choose(_ option: HandActionOption) async {
        guard !Task.isCancelled, screen == .training, let hand,
              hand.status == .awaitingAction, analysis == nil, !isBusy,
              errorMessage == nil, pendingAction == nil,
              hand.availableActions.contains(option) else { return }
        let request = HandActionRequest(
            requestId: UUID().uuidString, expectedRevision: hand.revision,
            action: option.action, amount: option.amount
        )
        pendingAction = request
        await submit(request, for: hand)
    }

    func retry() async {
        guard !Task.isCancelled, screen == .training, errorMessage != nil, !isBusy else { return }
        switch errorRecovery {
        case .settings:
            return
        case .replaceHand:
            creationRequestID = nil
            await loadHand()
        case .retry:
            if analysis != nil {
                await advanceHand()
            } else if hand?.status == .completed {
                errorMessage = nil
                await next()
            } else if let pendingAction, let hand {
                await submit(pendingAction, for: hand)
            } else {
                await loadHand()
            }
        }
    }

    func configure(backend: Bool, address: String) -> Bool {
        let cleaned = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = try? BackendAddress.parse(cleaned)
        guard !backend || baseURL != nil else { return false }
        leaveSession()
        usesBackend = backend
        serverAddress = cleaned
        configurationIsInvalid = false
        defaults.set(backend, forKey: "modernPoker.usesBackend")
        defaults.set(cleaned, forKey: "modernPoker.serverAddress")
        service = Self.makeService(enabled: backend, baseURL: baseURL)
        return true
    }

    private func submit(_ request: HandActionRequest, for previous: PokerHand) async {
        let token = UUID()
        operationID = token
        isEvaluating = true
        errorMessage = nil
        errorRecovery = .retry
        let service = service
        let task = Task { try await service.act(on: previous, request: request) }
        actionTask = task
        defer {
            if operationID == token {
                isEvaluating = false
                actionTask = nil
            }
        }
        do {
            let response = try await result(of: task)
            guard operationID == token else { return }
            decisionHand = previous
            hand = response.hand
            analysis = response.analysis
            decisions.append(response.analysis)
            decisionCount += 1
            recordCompleted(response.hand)
            pendingAction = nil
        } catch {
            guard operationID == token else { return }
            // The server may already have committed the action; retry the exact same request ID.
            errorMessage = isCancellation(error)
                ? "Przerwano oczekiwanie na wynik. Ponów ten sam ruch, aby bezpiecznie sprawdzić jego wynik."
                : message(for: error)
            if (error as? PokerError)?.isHandUnavailable == true {
                pendingAction = nil
                errorRecovery = .replaceHand
            }
        }
    }

    private func loadHand() async {
        if configurationIsInvalid {
            errorMessage = "Zapisany adres serwera jest nieprawidłowy. Popraw go w ustawieniach lub wybierz trening na urządzeniu."
            errorRecovery = .settings
            return
        }
        handTask?.cancel()
        actionTask?.cancel()
        let token = UUID()
        operationID = token
        hand = nil
        decisionHand = nil
        analysis = nil
        decisions = []
        errorMessage = nil
        errorRecovery = .retry
        pendingAction = nil
        isLoading = true
        let requestID = creationRequestID ?? UUID().uuidString
        creationRequestID = requestID
        let service = service
        let cleanupTask = cleanupTask
        let task = Task {
            do { try await cleanupTask?.value }
            catch { try await service.endSession() }
            return try await service.startHand(requestId: requestID)
        }
        handTask = task
        defer {
            if operationID == token {
                isLoading = false
                handTask = nil
            }
        }
        do {
            let nextHand = try await result(of: task)
            guard operationID == token else { return }
            guard !results.contains(where: { $0.id == nextHand.id }) else { throw PokerError.invalidExercise }
            self.cleanupTask = nil
            hand = nextHand
            if let restored = try await service.restoredFeedback(for: nextHand) {
                guard operationID == token else { return }
                let snapshot = try await service.decisionSnapshot(for: nextHand)
                guard operationID == token else { return }
                decisionHand = snapshot
                analysis = restored
                decisions = [restored]
                decisionCount += 1
            }
            recordCompleted(nextHand)
        } catch {
            guard operationID == token else { return }
            if isCancellation(error) {
                screen = .home
                return
            }
            errorMessage = message(for: error)
        }
    }

    private func result<Value: Sendable>(of task: Task<Value, Error>) async throws -> Value {
        try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func message(for error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .notConnectedToInternet:
            return "Brak połączenia z internetem. Sprawdź sieć i spróbuj ponownie."
        case .cannotFindHost, .cannotConnectToHost:
            return "Nie możemy połączyć się z serwerem. Sprawdź, czy działa i czy jego adres jest poprawny."
        case .timedOut:
            return "Serwer nie odpowiedział na czas. Spróbuj ponownie."
        case .networkConnectionLost:
            return "Połączenie zostało przerwane. Możesz bezpiecznie ponowić ten sam ruch."
        default:
            return "Nie udało się połączyć z serwerem. Sprawdź połączenie i spróbuj ponownie."
        }
    }
}
