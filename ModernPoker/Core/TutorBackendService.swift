import Foundation

actor TutorBackendService: HandServing {
    private let baseURL: URL
    private let session: URLSession
    private var sessionID: String?
    private var sessionCreationKey = UUID().uuidString
    private var created: [String: PokerHand] = [:]
    private var snapshots: [String: PokerHand] = [:]
    private var feedback: [String: HandAnalysis] = [:]
    private var actionResults: [String: (request: HandActionRequest, response: HandActionResponse)] = [:]

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func startHand(requestId: String) async throws -> PokerHand {
        if let cached = created[requestId] { return cached }
        let sessions: [TutorSession] = try await get("api/v1/sessions")
        let current: TutorSession
        if let active = sessions.first(where: { $0.status == "active" }) {
            current = active
        } else {
            do {
                current = try await post("api/v1/sessions", body: EmptyBody(), key: sessionCreationKey)
            } catch {
                let recovered: [TutorSession] = try await get("api/v1/sessions")
                guard let active = recovered.first(where: { $0.status == "active" }) else { throw error }
                current = active
            }
        }
        sessionID = current.id
        let dto: TutorHand
        if let active = current.activeHandId {
            dto = try await get("api/v1/sessions/\(current.id)/hands/\(active)")
        } else {
            do {
                dto = try await post("api/v1/sessions/\(current.id)/hands", body: EmptyBody(), key: requestId)
            } catch {
                let recovered: TutorSession = try await get("api/v1/sessions/\(current.id)")
                guard let active = recovered.activeHandId else { throw error }
                dto = try await get("api/v1/sessions/\(current.id)/hands/\(active)")
            }
        }
        let hand = try dto.mapped()
        if let analysis = dto.feedback {
            feedback[hand.id] = try analysis.mapped()
            snapshots[hand.id] = try dto.decisionSnapshot()
        }
        created[requestId] = hand
        return hand
    }

    func decisionSnapshot(for hand: PokerHand) async throws -> PokerHand { snapshots[hand.id] ?? hand }

    func restoredFeedback(for hand: PokerHand) async throws -> HandAnalysis? { feedback[hand.id] }

    func act(on hand: PokerHand, request: HandActionRequest) async throws -> HandActionResponse {
        if let cached = actionResults[request.requestId] {
            guard cached.request == request, cached.response.hand.id == hand.id else { throw PokerError.invalidResponse }
            return cached.response
        }
        let path = try handPath(hand)
        let latest: TutorHand = try await get(path)
        let dto: TutorHand
        if let saved = latest.feedback, saved.street == hand.street, saved.action == request.action {
            dto = latest
        } else {
            guard latest.stage == "awaiting_action", latest.street == hand.street,
                  latest.availableActions.contains(request.action),
                  request.amount == (request.action == .bet ? latest.betAmount : 0) else { throw PokerError.invalidResponse }
            do {
                dto = try await post(path + "/actions", body: ActionBody(action: request.action, street: hand.street))
            } catch {
                let recovered: TutorHand = try await get(path)
                guard let saved = recovered.feedback, saved.street == hand.street, saved.action == request.action else { throw error }
                dto = recovered
            }
        }
        guard dto.id == hand.id, dto.userCards == hand.heroCards.map(\.id),
              let saved = dto.feedback, saved.decisionBoard == hand.board.map(\.id) else { throw PokerError.invalidResponse }
        let history = hand.history + [HandHistoryEntry(id: request.requestId, street: hand.street, player: .hero, action: request.action, amount: request.amount)]
        let result = HandActionResponse(hand: try dto.mapped(history: history), analysis: try saved.mapped())
        feedback[hand.id] = result.analysis
        actionResults[request.requestId] = (request, result)
        return result
    }

    func advance(_ hand: PokerHand) async throws -> PokerHand {
        guard hand.backend?.needsContinuation == true else { return hand }
        let path = try handPath(hand)
        let latest: TutorHand = try await get(path)
        let dto: TutorHand
        if latest.stage != "awaiting_continuation" || latest.street != hand.street {
            dto = latest
        } else {
            do {
                dto = try await post(path + "/continue", body: StreetBody(street: hand.street))
            } catch {
                let recovered: TutorHand = try await get(path)
                guard recovered.street != hand.street || recovered.stage == "showdown" else { throw error }
                dto = recovered
            }
        }
        guard dto.id == hand.id, dto.userCards == hand.heroCards.map(\.id),
              Array(dto.communityCards.prefix(hand.board.count)) == hand.board.map(\.id) else { throw PokerError.invalidResponse }
        feedback[hand.id] = nil
        return try dto.mapped(history: hand.history)
    }

    func endSession() async throws {
        guard let sessionID else { return }
        let current: TutorSession = try await get("api/v1/sessions/\(sessionID)")
        if current.status == "active" {
            let _: TutorSession = try await post("api/v1/sessions/\(sessionID)/end", body: EmptyBody())
        }
        self.sessionID = nil
        sessionCreationKey = UUID().uuidString
        snapshots = [:]
        created = [:]
        feedback = [:]
        actionResults = [:]
    }

    private func handPath(_ hand: PokerHand) throws -> String {
        guard let id = hand.backend?.sessionID, UUID(uuidString: id) != nil, UUID(uuidString: hand.id) != nil else {
            throw PokerError.invalidResponse
        }
        return "api/v1/sessions/\(id)/hands/\(hand.id)"
    }

    private struct EmptyBody: Encodable {}
    private struct ActionBody: Encodable { let action: HandAction; let street: HandStreet }
    private struct StreetBody: Encodable { let street: HandStreet }
    private struct APIError: Decodable { let code: String; let message: String }

    private func get<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        try await request(path, method: "GET", data: nil, key: nil)
    }
    private func post<Body: Encodable, Response: Decodable & Sendable>(_ path: String, body: Body, key: String? = nil) async throws -> Response {
        try await request(path, method: "POST", data: JSONEncoder().encode(body), key: key)
    }
    private func request<Response: Decodable & Sendable>(_ path: String, method: String, data: Data?, key: String?) async throws -> Response {
        try Task.checkCancellation()
        try BackendAddress.validate(baseURL)
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = data
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, data.count <= 256_000,
              response.mimeType == "application/json" else { throw PokerError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200...299).contains(response.statusCode) else {
            guard let error = try? decoder.decode(APIError.self, from: data) else { throw PokerError.server(status: response.statusCode) }
            let message: String
            switch error.code {
            case "insufficient_chips": message = "Przy stole zabrakło żetonów. Zakończ sesję i rozpocznij nową."
            case "simulation_unavailable": message = "Backend nie mógł obliczyć analizy. Spróbuj ponownie."
            case "session_ended": message = "Sesja na serwerze została zakończona. Wróć do początku."
            default: message = "Backend zwrócił błąd \(response.statusCode) (\(error.code)). Spróbuj ponownie."
            }
            throw PokerError.api(status: response.statusCode, code: error.code, message: message, isDecision: path.contains("/hands/"))
        }
        do { return try decoder.decode(Response.self, from: data) } catch { throw PokerError.invalidResponse }
    }
}
