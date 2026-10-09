import Foundation

enum Suit: String, Codable, CaseIterable, Sendable {
    case clubs = "c"
    case diamonds = "d"
    case hearts = "h"
    case spades = "s"
}

struct PokerCard: Codable, Hashable, Identifiable, Sendable {
    let rank: Int
    let suit: Suit

    var id: String { "\(rankLabel)\(suit.rawValue)" }

    var rankLabel: String {
        switch rank {
        case 14: "A"
        case 13: "K"
        case 12: "Q"
        case 11: "J"
        case 10: "T"
        default: String(rank)
        }
    }

    var suitSymbol: String {
        switch suit {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    static let deck: [PokerCard] = Suit.allCases.flatMap { suit in
        (2...14).map { PokerCard(rank: $0, suit: suit) }
    }
}

struct OpponentRange: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let hands: [String]
}

struct PokerExercise: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let heroCards: [PokerCard]
    let board: [PokerCard]
    /// Includes the opponent's all-in, but excludes the hero's call.
    let pot: Int
    let callAmount: Int
    let opponentRange: OpponentRange
}

enum PokerAction: String, Codable, Sendable {
    case call
    case fold
}

struct DecisionAnalysis: Codable, Sendable {
    let exerciseId: String
    let selectedAction: PokerAction
    /// Expected share of the pot: wins plus half of ties, in 0...1.
    let equity: Double
    let requiredEquity: Double
    let callEV: Double
    let recommendedAction: PokerAction
    let acceptableActions: [PokerAction]
    let isCorrect: Bool
    let explanation: String
    let sampleCount: Int
    /// Conservative 95% absolute uncertainty, in 0...1.
    let marginOfError: Double
}

enum PokerError: Error, LocalizedError, Sendable {
    case invalidExercise
    case invalidRange
    case invalidAnalysis
    case invalidServerURL
    case server(status: Int)
    case api(status: Int, code: String, message: String, isDecision: Bool)
    case invalidResponse

    var isExerciseUnavailable: Bool {
        guard case let .api(status, code, _, isDecision) = self, isDecision else { return false }
        return (status == 404 && code == "exercise_not_found") || (status == 410 && code == "exercise_expired")
    }

    var isHandUnavailable: Bool {
        guard case let .api(status, code, _, isDecision) = self, isDecision else { return false }
        return (status == 404 && code == "hand_not_found")
            || (status == 410 && code == "hand_expired")
            || (status == 409 && code == "stale_revision")
    }

    var errorDescription: String? {
        switch self {
        case .invalidExercise: "Rozdanie zawiera nieprawidłowe dane. Spróbuj pobrać kolejne."
        case .invalidRange: "Zakres rywala nie zawiera poprawnych kombinacji kart."
        case .invalidAnalysis: "Wynik analizy jest nieprawidłowy. Spróbuj ponownie."
        case .invalidServerURL: "Podaj poprawny adres serwera HTTP lub HTTPS."
        case let .server(status): "Serwer zwrócił błąd \(status). Spróbuj ponownie."
        case let .api(_, _, message, _): message
        case .invalidResponse: "Nie udało się odczytać odpowiedzi serwera."
        }
    }
}
