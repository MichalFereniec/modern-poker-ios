import Foundation

/// Authoritative four-seat data, kept separate from the local heads-up engine.
struct BackendHandInfo: Codable, Equatable, Sendable {
    let sessionID: String
    let stage: String
    let stacks: [Double]
    let ranges: [OpponentRange]
    let privateCards: [[PokerCard]]
    let payouts: [Double]
    let chipChanges: [Double]
    let winners: [Int]
    let hypotheticalWinners: [Int]
    var needsContinuation: Bool { stage == "awaiting_continuation" }
    var isFoldReview: Bool { stage == "fold_review" }
}

struct BackendTeaching: Codable, Equatable, Sendable {
    let grade: String
    let recommendation: String
    let checkEV: Double
    let betEV: Double?
    let incrementalBetEV: Double?
    let winProbability: Double
    let madeHand: String

    var gradeTitle: String {
        switch grade {
        case "good": "Dobry ruch"
        case "bad": "Lepszy był inny ruch"
        default: "Rozsądny ruch"
        }
    }
    var recommendationTitle: String {
        switch recommendation {
        case "bet": "BET"
        case "check": "CHECK"
        default: "CHECK lub BET"
        }
    }
}

struct TutorSession: Decodable, Sendable {
    let id: String
    let status: String
    let handIds: [String]
    let activeHandId: String?
}

struct TutorHand: Decodable, Sendable {
    let id: String
    let sessionId: String
    let status: String
    let street: HandStreet
    let stage: String
    let userCards: [String]
    let communityCards: [String]
    let pot: Int
    let stacks: [Double]
    let availableActions: [HandAction]
    let betAmount: Int
    let opponentRanges: [TutorRange]
    let feedback: TutorFeedback?
    let showdown: TutorShowdown?
    let review: TutorReview?

    func mapped(history: [HandHistoryEntry] = []) throws -> PokerHand {
        let hero = try userCards.map(Self.card)
        let board = try communityCards.map(Self.card)
        guard hero.count == 2, (3...5).contains(board.count), stacks.count == 4,
              stacks.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 4_000_000_000 }),
              opponentRanges.map(\.playerIndex) == [1, 2, 3], (0...4_000_000_000).contains(pot), Set(hero + board).count == hero.count + board.count,
              ["awaiting_action", "awaiting_continuation", "showdown", "fold_review"].contains(stage) else {
            throw PokerError.invalidResponse
        }
        let ranges = opponentRanges.map { OpponentRange(id: $0.id, name: $0.name, description: $0.description, hands: $0.hands) }
        let privateCards = try (showdown?.privateCards ?? review?.privateCards ?? []).map { try $0.map(Self.card) }
        let payouts = showdown?.payouts ?? review?.actualPayouts ?? []
        let winners = showdown?.winners ?? review?.actualWinners ?? []
        let terminal = stage == "showdown" || stage == "fold_review"
        guard !terminal || (privateCards.count == 4 && privateCards.allSatisfy({ $0.count == 2 }) && payouts.count == 4),
              payouts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 4_000_000_000 }),
              payouts.reduce(0, +) <= 4_000_000_000 else { throw PokerError.invalidResponse }
        let awarded = showdown?.potAwarded ?? review?.potAwarded ?? pot
        let result: HandResult? = terminal ? HandResult(
            reason: stage == "fold_review" ? .fold : .showdown,
            winner: winners.contains(0) ? (winners.count == 1 ? .hero : .tie) : .opponent,
            opponentCards: privateCards.dropFirst().first ?? [],
            heroPayout: Int(payouts[0]), opponentPayout: Int(payouts.dropFirst().reduce(0, +)),
            summary: stage == "fold_review"
                ? "Spasowałeś. Pula została rozliczona między rywalami. Odkryte karty pokazują też, co mogłoby się wydarzyć, gdybyś pozostał w grze."
                : "Karty wszystkich graczy są odkryte. Pula trafia do zwycięzców; żetony przechodzą do kolejnego rozdania."
        ) : nil
        var hand = PokerHand(
            id: id, revision: history.count + board.count - 3, street: stage == "showdown" ? .showdown : street,
            status: terminal ? .completed : .awaitingAction,
            heroCards: hero, board: board, pot: awarded, heroStack: Int(stacks[0]), opponentStack: Int(stacks[1]),
            toCall: 0, opponentRange: ranges[0],
            availableActions: stage == "awaiting_action" ? availableActions.map { HandActionOption(action: $0, amount: $0 == .bet ? betAmount : 0) } : [],
            history: history, result: result
        )
        hand.backend = BackendHandInfo(
            sessionID: sessionId, stage: stage, stacks: stacks, ranges: ranges, privateCards: privateCards,
            payouts: payouts, chipChanges: showdown?.chipChanges ?? review?.actualChipChanges ?? [],
            winners: winners, hypotheticalWinners: review?.winners ?? []
        )
        return hand
    }

    func decisionSnapshot() throws -> PokerHand? {
        guard let feedback else { return nil }
        let ranges = opponentRanges.map { OpponentRange(id: $0.id, name: $0.name, description: $0.description, hands: $0.hands) }
        guard feedback.stacksBeforeAction.count == 4,
              feedback.stacksBeforeAction.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 4_000_000_000 }), ranges.count == 3 else { throw PokerError.invalidResponse }
        var hand = PokerHand(id: id, revision: 0, street: feedback.street, status: .awaitingAction,
                             heroCards: try userCards.map(Self.card), board: try feedback.decisionBoard.map(Self.card),
                             pot: feedback.potBeforeAction, heroStack: Int(feedback.stacksBeforeAction[0]), opponentStack: Int(feedback.stacksBeforeAction[1]),
                             toCall: 0, opponentRange: ranges[0],
                             availableActions: feedback.availableActions.map { HandActionOption(action: $0, amount: $0 == .bet ? betAmount : 0) }, history: [], result: nil)
        hand.backend = BackendHandInfo(sessionID: sessionId, stage: "awaiting_action", stacks: feedback.stacksBeforeAction,
                                       ranges: ranges, privateCards: [], payouts: [], chipChanges: [], winners: [], hypotheticalWinners: [])
        return hand
    }

    static func card(_ value: String) throws -> PokerCard {
        guard let card = PokerCard.deck.first(where: { $0.id == value }) else { throw PokerError.invalidResponse }
        return card
    }
}

struct TutorRange: Decodable, Sendable {
    let playerIndex: Int
    let id: String
    let name: String
    let description: String
    let hands: [String]
}

struct TutorFeedback: Decodable, Sendable {
    let action: HandAction
    let street: HandStreet
    let decisionBoard: [String]
    let potBeforeAction: Int
    let stacksBeforeAction: [Double]
    let availableActions: [HandAction]
    let equity: Double
    let marginOfError: Double
    let sampleCount: Int
    let requiredEquity: Double
    let recommendation: String
    let grade: String
    let madeHand: String
    let actionEvs: TutorEVs
    let incrementalBetEv: Double?
    let outcomeProbabilities: TutorOutcomes
    let explanation: [String]

    func mapped() throws -> HandAnalysis {
        guard (0...1).contains(equity), (0...1).contains(marginOfError),
              [0, 10_000].contains(sampleCount), actionEvs.check.isFinite,
              actionEvs.bet.map(\.isFinite) ?? true else { throw PokerError.invalidAnalysis }
        var result = HandAnalysis(street: street, action: action, equity: equity, requiredEquity: requiredEquity,
                                  callEV: nil, sampleCount: sampleCount, marginOfError: marginOfError,
                                  explanation: "Ocena porównuje CHECK, BET i FOLD przeciwko trzem ujawnionym zakresom. Rywale zawsze czekają lub sprawdzają zakład 10. Model zakłada brak dalszych zakładów po tej decyzji; nie jest strategią GTO.")
        result.teaching = BackendTeaching(grade: grade, recommendation: recommendation, checkEV: actionEvs.check,
                                         betEV: actionEvs.bet, incrementalBetEV: incrementalBetEv,
                                         winProbability: outcomeProbabilities.outrightWin, madeHand: madeHand)
        return result
    }
}
struct TutorEVs: Decodable, Sendable { let check: Double; let bet: Double? }
struct TutorOutcomes: Decodable, Sendable { let outrightWin: Double }
struct TutorShowdown: Decodable, Sendable {
    let privateCards: [[String]]
    let winners: [Int]
    let payouts: [Double]
    let chipChanges: [Double]
    let potAwarded: Int
}
struct TutorReview: Decodable, Sendable {
    let privateCards: [[String]]
    let winners: [Int]
    let actualWinners: [Int]
    let actualPayouts: [Double]
    let actualChipChanges: [Double]
    let potAwarded: Int
}
