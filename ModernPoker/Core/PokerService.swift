import Foundation

actor PokerService {
    private let baseURL: URL?
    private let session: URLSession
    private var lastEstimate: (exercise: PokerExercise, estimate: PokerEngine.EquityEstimate)?
    private var localHand: LocalPokerHand?
    private var lastCreatedHand: (requestID: String, hand: PokerHand)?
    private var actionCache: [String: CachedAction] = [:]
    private var actionOrder: [String] = []

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func startHand(requestId: String) async throws -> PokerHand {
        try Task.checkCancellation()
        try validateRequestID(requestId)
        if let baseURL {
            let hand: PokerHand = try await request(
                baseURL: baseURL, path: "v2/hands", body: CreateHandBody(requestId: requestId),
                status: 201, isDecision: false
            )
            try HandValidation.validate(hand)
            guard hand.revision == 0, hand.street == .flop, hand.status == .awaitingAction else {
                throw PokerError.invalidResponse
            }
            return hand
        }
        if let lastCreatedHand, lastCreatedHand.requestID == requestId { return lastCreatedHand.hand }
        var generator = SystemRandomNumberGenerator()
        let created = try LocalPokerHand.start(using: &generator)
        try HandValidation.validate(created.state)
        try Task.checkCancellation()
        localHand = created
        lastCreatedHand = (requestId, created.state)
        return created.state
    }

    func act(on hand: PokerHand, request actionRequest: HandActionRequest) async throws -> HandActionResponse {
        try Task.checkCancellation()
        try validateRequestID(actionRequest.requestId)
        try HandValidation.validate(hand)
        guard actionRequest.expectedRevision == hand.revision else { throw PokerError.invalidExercise }
        if let baseURL {
            let response: HandActionResponse = try await request(
                baseURL: baseURL, path: "v2/hands/\(hand.id)/actions", body: actionRequest,
                status: 200, isDecision: true
            )
            try HandValidation.validate(response, previous: hand, request: actionRequest)
            return response
        }
        // A successful retry returns the original snapshot before checking the now-advanced revision.
        let cacheKey = hand.id + ":" + actionRequest.requestId
        if let cached = actionCache[cacheKey] {
            guard cached.handID == hand.id, cached.request == actionRequest else {
                throw handError(status: 409, code: "idempotency_conflict", message: "Ten identyfikator żądania został już użyty dla innego ruchu.")
            }
            try HandValidation.validate(cached.response, previous: hand, request: actionRequest)
            return cached.response
        }
        guard var candidate = localHand, candidate.state.id == hand.id else {
            throw handError(status: 404, code: "hand_not_found", message: "Nie znaleziono tego rozdania. Rozpocznij nowe.")
        }
        guard candidate.state == hand else {
            throw handError(status: 409, code: "stale_revision", message: "Stan rozdania zmienił się. Rozpocznij nowe rozdanie.")
        }
        guard hand.availableActions.contains(HandActionOption(action: actionRequest.action, amount: actionRequest.amount)) else {
            throw handError(status: 422, code: "illegal_action", message: "Ten ruch nie jest dostępny w bieżącym rozdaniu.")
        }
        var generator = SystemRandomNumberGenerator()
        let response = try candidate.apply(actionRequest, using: &generator)
        try HandValidation.validate(response, previous: hand, request: actionRequest)
        try Task.checkCancellation()
        // Publish the entire transition and its retry result together; cancelled calculations commit nothing.
        localHand = candidate
        actionCache[cacheKey] = CachedAction(handID: hand.id, request: actionRequest, response: response)
        actionOrder.append(cacheKey)
        if actionOrder.count > 32 { actionCache[actionOrder.removeFirst()] = nil }
        return response
    }

    private struct CreateHandBody: Encodable {
        let requestId: String
    }

    private struct CachedAction {
        let handID: String
        let request: HandActionRequest
        let response: HandActionResponse
    }

    private func validateRequestID(_ value: String) throws {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard (1...128).contains(value.count), value.allSatisfy({ allowed.contains($0) }) else {
            throw PokerError.invalidExercise
        }
    }

    private func handError(status: Int, code: String, message: String) -> PokerError {
        .api(status: status, code: code, message: message, isDecision: true)
    }

    func nextExercise() async throws -> PokerExercise {
        try Task.checkCancellation()
        if let baseURL {
            let exercise: PokerExercise = try await request(
                baseURL: baseURL, path: "v1/exercises", body: EmptyBody(), status: 201, isDecision: false
            )
            try PokerEngine.validate(exercise)
            return exercise
        }
        var generator = SystemRandomNumberGenerator()
        let exercise = try PokerEngine.generate(using: &generator)
        lastEstimate = nil
        return exercise
    }

    func evaluate(_ exercise: PokerExercise, action: PokerAction) async throws -> DecisionAnalysis {
        try Task.checkCancellation()
        try PokerEngine.validate(exercise)
        if let baseURL {
            let analysis: DecisionAnalysis = try await request(
                baseURL: baseURL,
                path: "v1/exercises/\(exercise.id)/decisions",
                body: DecisionBody(action: action), status: 200, isDecision: true
            )
            try PokerEngine.validate(analysis, for: exercise, action: action)
            return analysis
        }

        let estimate: PokerEngine.EquityEstimate
        if let lastEstimate, lastEstimate.exercise == exercise {
            estimate = lastEstimate.estimate
        } else {
            var generator = SystemRandomNumberGenerator()
            estimate = try PokerEngine.estimate(exercise, using: &generator)
            lastEstimate = (exercise, estimate)
        }
        return PokerEngine.analyze(exercise, action: action, estimate: estimate)
    }

    private struct EmptyBody: Encodable {}

    private struct DecisionBody: Encodable {
        let action: PokerAction
    }

    private struct APIError: Decodable {
        let code: String
        let message: String

        var isValid: Bool {
            let codes = [
                "invalid_request", "validation_error", "unsupported_media_type", "exercise_not_found", "exercise_expired",
                "simulation_unavailable", "hand_not_found", "hand_expired", "stale_revision", "idempotency_conflict", "illegal_action"
            ]
            return codes.contains(code) && (1...1_000).contains(message.count)
                && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private struct HTTPPayload: Sendable {
        let data: Data
        let status: Int
        let isJSON: Bool
    }

    private func request<Body: Encodable, Response: Decodable>(
        baseURL: URL, path: String, body: Body, status: Int, isDecision: Bool
    ) async throws -> Response {
        try BackendAddress.validate(baseURL)
        let url = path.split(separator: "/").reduce(baseURL) { $0.appendingPathComponent(String($1)) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let payload = try await withThrowingTaskGroup(of: HTTPPayload.self) { group in
            group.addTask { [session, request] in
                try await Self.receive(request, session: session, expectedStatus: status)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let payload = try await group.next() else { throw PokerError.invalidResponse }
            return payload
        }
        try Task.checkCancellation()
        guard payload.status == status else {
            if payload.isJSON, let error = try? JSONDecoder().decode(APIError.self, from: payload.data), error.isValid {
                throw PokerError.api(status: payload.status, code: error.code, message: error.message, isDecision: isDecision)
            }
            throw PokerError.server(status: payload.status)
        }
        guard payload.isJSON else { throw PokerError.invalidResponse }
        do {
            return try JSONDecoder().decode(Response.self, from: payload.data)
        } catch {
            throw PokerError.invalidResponse
        }
    }

    private static func receive(_ request: URLRequest, session: URLSession, expectedStatus: Int) async throws -> HTTPPayload {
        let (bytes, response) = try await session.bytes(for: request)
        // Stop the underlying task on an early limit/mime failure and on timeout/cancellation.
        defer { bytes.task.cancel() }
        return try await withTaskCancellationHandler {
            guard let response = response as? HTTPURLResponse else { throw PokerError.invalidResponse }
            let isJSON = response.mimeType?.lowercased() == "application/json"
            guard isJSON else { return HTTPPayload(data: Data(), status: response.statusCode, isJSON: false) }
            let invalidResponse = response.statusCode == expectedStatus ? PokerError.invalidResponse : .server(status: response.statusCode)
            guard response.expectedContentLength <= 65_536 else { throw invalidResponse }
            var data = Data()
            for try await byte in bytes {
                if data.count.isMultiple(of: 1_024) { try Task.checkCancellation() }
                guard data.count < 65_536 else { throw invalidResponse }
                data.append(byte)
            }
            return HTTPPayload(data: data, status: response.statusCode, isJSON: true)
        } onCancel: {
            bytes.task.cancel()
        }
    }
}
