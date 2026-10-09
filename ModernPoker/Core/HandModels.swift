import Foundation

enum HandStreet: String, Codable, CaseIterable, Sendable {
    case flop, turn, river, showdown
}

enum HandAction: String, Codable, Sendable {
    case fold, check, call, bet, raise
}

struct HandActionOption: Codable, Equatable, Sendable, Identifiable {
    let action: HandAction
    /// Additional chips paid now, including the call part of a raise. Zero for check/fold.
    let amount: Int
    var id: String { "\(action.rawValue)-\(amount)" }
}

enum HandPlayer: String, Codable, Sendable { case hero, opponent }
enum HandStatus: String, Codable, Sendable { case awaitingAction, completed }
enum HandWinner: String, Codable, Sendable { case hero, opponent, tie }
enum HandEndReason: String, Codable, Sendable { case fold, showdown }

struct HandHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let street: HandStreet
    let player: HandPlayer
    let action: HandAction
    let amount: Int
}

struct HandResult: Codable, Equatable, Sendable {
    let reason: HandEndReason
    let winner: HandWinner
    /// Empty after a fold; revealed only at showdown.
    let opponentCards: [PokerCard]
    let heroPayout: Int
    let opponentPayout: Int
    let summary: String
}

struct PokerHand: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let revision: Int
    let street: HandStreet
    let status: HandStatus
    let heroCards: [PokerCard]
    let board: [PokerCard]
    /// During play includes committed chips; at completion is the settled pot before payout.
    let pot: Int
    /// Uncommitted chips during play, final chips including payout at completion.
    let heroStack: Int
    let opponentStack: Int
    let toCall: Int
    let opponentRange: OpponentRange
    let availableActions: [HandActionOption]
    let history: [HandHistoryEntry]
    let result: HandResult?
    var backend: BackendHandInfo? = nil
}

struct HandAnalysis: Codable, Equatable, Sendable {
    let street: HandStreet
    let action: HandAction
    let equity: Double
    /// Nil when no bet is faced. A price benchmark, not a full multi-street strategy recommendation.
    let requiredEquity: Double?
    /// Call-versus-fold snapshot assuming no later costs; nil when checking is free.
    let callEV: Double?
    let sampleCount: Int
    let marginOfError: Double
    let explanation: String
    var teaching: BackendTeaching? = nil
}

struct HandActionRequest: Codable, Equatable, Sendable {
    let requestId: String
    let expectedRevision: Int
    let action: HandAction
    let amount: Int
}

struct HandActionResponse: Codable, Equatable, Sendable {
    let hand: PokerHand
    /// Calculated from the public state BEFORE the action, never from newly revealed cards.
    let analysis: HandAnalysis
}

protocol HandServing: Sendable {
    func startHand(requestId: String) async throws -> PokerHand
    func act(on hand: PokerHand, request: HandActionRequest) async throws -> HandActionResponse
    func advance(_ hand: PokerHand) async throws -> PokerHand
    func endSession() async throws
    func restoredFeedback(for hand: PokerHand) async throws -> HandAnalysis?
    func decisionSnapshot(for hand: PokerHand) async throws -> PokerHand
}

extension HandServing {
    func advance(_ hand: PokerHand) async throws -> PokerHand { hand }
    func endSession() async throws {}
    func restoredFeedback(for hand: PokerHand) async throws -> HandAnalysis? { nil }
    func decisionSnapshot(for hand: PokerHand) async throws -> PokerHand { hand }
}

extension PokerService: HandServing {}
