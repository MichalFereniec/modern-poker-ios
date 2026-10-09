import Foundation

enum PokerEngine {
    struct HoleCards: Sendable {
        let first: PokerCard
        let second: PokerCard
    }

    struct EquityEstimate: Sendable {
        let equity: Double
        let sampleCount: Int

        var marginOfError: Double {
            // Hoeffding's bound applies to independent samples in [0, 1], including split pots.
            sampleCount == 0 ? 0 : min(1, sqrt(log(40) / (2 * Double(sampleCount))))
        }
    }

    static let ranges = [
        OpponentRange(
            id: "premium", name: "Mocny zakres",
            description: "Zakładamy, że rywal ma wysoką parę albo asa z królem lub damą. Każda dostępna kombinacja jest równie prawdopodobna.",
            hands: ["AA", "KK", "QQ", "JJ", "TT", "AKs", "AKo", "AQs"]
        ),
        OpponentRange(
            id: "balanced", name: "Szerszy zakres",
            description: "Zakładamy pary od siódemek oraz mocne asy i figury. Każda dostępna kombinacja jest równie prawdopodobna.",
            hands: ["AA", "KK", "QQ", "JJ", "TT", "99", "88", "77", "AKs", "AKo", "AQs", "AQo", "AJs", "ATs", "KQs", "KJs", "QJs", "JTs"]
        ),
        OpponentRange(
            id: "wide", name: "Agresywny zakres",
            description: "Zakładamy wszystkie pary, wiele asów, figur i sąsiadujących kart w kolorze. Każda dostępna kombinacja jest równie prawdopodobna.",
            hands: ["AA", "KK", "QQ", "JJ", "TT", "99", "88", "77", "66", "55", "44", "33", "22", "AKs", "AKo", "AQs", "AQo", "AJs", "AJo", "ATs", "ATo", "A9s", "A8s", "A7s", "A6s", "A5s", "A4s", "A3s", "A2s", "KQs", "KQo", "KJs", "KJo", "KTs", "QJs", "QJo", "QTs", "JTs", "T9s", "98s", "87s", "76s"]
        )
    ]

    static func generate<R: RandomNumberGenerator>(using generator: inout R) throws -> PokerExercise {
        let cards = PokerCard.deck.shuffled(using: &generator)
        let boardCount = Bool.random(using: &generator) ? 3 : 4
        let pot = Int.random(in: 9...60, using: &generator) * 20
        let exercise = PokerExercise(
            id: UUID().uuidString,
            heroCards: Array(cards.prefix(2)),
            board: Array(cards[2..<(2 + boardCount)]),
            pot: pot,
            callAmount: Int.random(in: 2..<(pot / 10), using: &generator) * 10,
            opponentRange: ranges[Int.random(in: ranges.indices, using: &generator)]
        )
        try validate(exercise)
        return exercise
    }

    static func validate(_ exercise: PokerExercise) throws {
        let cards = exercise.heroCards + exercise.board
        guard isIdentifier(exercise.id, maximum: 128),
              exercise.heroCards.count == 2, (3...4).contains(exercise.board.count),
              cards.allSatisfy({ (2...14).contains($0.rank) }),
              Set(cards).count == cards.count,
              (1...1_000_000).contains(exercise.pot),
              (1...exercise.pot).contains(exercise.callAmount)
        else { throw PokerError.invalidExercise }
        _ = try legalCombinations(for: exercise.opponentRange, excluding: Set(cards))
    }

    static func legalCombinations(for range: OpponentRange, excluding blockers: Set<PokerCard>) throws -> [HoleCards] {
        guard isIdentifier(range.id, maximum: 64),
              (1...80).contains(range.name.count),
              (1...1_000).contains(range.description.count),
              (1...169).contains(range.hands.count),
              Set(range.hands).count == range.hands.count,
              range.hands.allSatisfy(isCanonicalHand)
        else { throw PokerError.invalidRange }

        let classes = Set(range.hands)
        let deck = PokerCard.deck.filter { !blockers.contains($0) }
        var combinations: [HoleCards] = []
        for firstIndex in deck.indices {
            for secondIndex in (firstIndex + 1)..<deck.count {
                let first = deck[firstIndex]
                let second = deck[secondIndex]
                let high = first.rank >= second.rank ? first : second
                let low = first.rank >= second.rank ? second : first
                let suffix = high.rank == low.rank ? "" : (high.suit == low.suit ? "s" : "o")
                if classes.contains(high.rankLabel + low.rankLabel + suffix) {
                    combinations.append(HoleCards(first: first, second: second))
                }
            }
        }
        guard !combinations.isEmpty else { throw PokerError.invalidRange }
        return combinations
    }

    static func estimate<R: RandomNumberGenerator>(
        _ exercise: PokerExercise,
        sampleCount: Int = 5_000,
        using generator: inout R
    ) throws -> EquityEstimate {
        try validate(exercise)
        return try estimate(heroCards: exercise.heroCards, board: exercise.board, range: exercise.opponentRange, sampleCount: sampleCount, using: &generator)
    }

    static func estimate<R: RandomNumberGenerator>(
        heroCards: [PokerCard], board: [PokerCard], range: OpponentRange,
        sampleCount: Int = 5_000, using generator: inout R
    ) throws -> EquityEstimate {
        let visible = heroCards + board
        guard heroCards.count == 2, (3...5).contains(board.count),
              visible.allSatisfy({ (2...14).contains($0.rank) }), Set(visible).count == visible.count
        else { throw PokerError.invalidExercise }
        guard (1...1_000_000).contains(sampleCount) else { throw PokerError.invalidAnalysis }
        let blockers = Set(visible)
        let combinations = try legalCombinations(for: range, excluding: blockers)
        let unknownCards = PokerCard.deck.filter { !blockers.contains($0) }
        let missingCount = 5 - board.count
        // Fixed-size seven-card buffers avoid rebuilding every hand for each simulation.
        let placeholder = unknownCards[0]
        var hero = heroCards + board + Array(repeating: placeholder, count: missingCount)
        var opponent = [placeholder, placeholder] + board + Array(repeating: placeholder, count: missingCount)
        var potShare = 0.0

        for sample in 0..<sampleCount {
            if sample.isMultiple(of: 128) { try Task.checkCancellation() }
            let hole = combinations[Int.random(in: combinations.indices, using: &generator)]
            opponent[0] = hole.first
            opponent[1] = hole.second
            var previousDraw: PokerCard?
            for missing in 0..<missingCount {
                var card: PokerCard
                repeat {
                    card = unknownCards[Int.random(in: unknownCards.indices, using: &generator)]
                } while card == hole.first || card == hole.second || card == previousDraw
                hero[7 - missingCount + missing] = card
                opponent[7 - missingCount + missing] = card
                previousDraw = card
            }
            let heroRank = handRank(hero)
            let opponentRank = handRank(opponent)
            if heroRank > opponentRank {
                potShare += 1
            } else if heroRank == opponentRank {
                potShare += 0.5
            }
        }
        return EquityEstimate(equity: potShare / Double(sampleCount), sampleCount: sampleCount)
    }

    static func analyze(_ exercise: PokerExercise, action: PokerAction, estimate: EquityEstimate) -> DecisionAnalysis {
        let finalPot = Double(exercise.pot + exercise.callAmount)
        let requiredEquity = Double(exercise.callAmount) / finalPot
        let callEV = estimate.equity * finalPot - Double(exercise.callAmount)
        let recommendedAction: PokerAction = callEV >= 0 ? .call : .fold
        let isBorderline = abs(estimate.equity - requiredEquity) <= estimate.marginOfError
        let acceptableActions: [PokerAction] = isBorderline ? [.call, .fold] : [recommendedAction]
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(Locale(identifier: "pl_PL"))
        let equityPercent = (estimate.equity * 100).formatted(format)
        let requiredPercent = (requiredEquity * 100).formatted(format)
        let conclusion: String
        if isBorderline {
            conclusion = "Wynik jest blisko granicy opłacalności. Błąd symulacji nie pozwala pewnie rozstrzygnąć — obie decyzje są zaliczone."
        } else if recommendedAction == .call {
            conclusion = "Sprawdzenie ma dodatnią wartość oczekiwaną. W długim okresie zarabia żetony przy tym założeniu o rywalu."
        } else {
            conclusion = "Cena sprawdzenia jest za wysoka względem twojego udziału w puli. Fold pozwala uniknąć tej straty."
        }
        return DecisionAnalysis(
            exerciseId: exercise.id, selectedAction: action,
            equity: estimate.equity, requiredEquity: requiredEquity, callEV: callEV,
            recommendedAction: recommendedAction, acceptableActions: acceptableActions,
            isCorrect: acceptableActions.contains(action),
            explanation: "Masz około \(equityPercent)% udziału w puli przeciwko podanemu zakresowi. Sprawdzenie za \(exercise.callAmount) do końcowej puli \(Int(finalPot)) wymaga \(requiredPercent)%. \(conclusion) Remisy są uwzględnione; pomijamy prowizję i strategię turniejową.",
            sampleCount: estimate.sampleCount, marginOfError: estimate.marginOfError
        )
    }

    static func validate(_ analysis: DecisionAnalysis, for exercise: PokerExercise, action: PokerAction) throws {
        let expectedThreshold = Double(exercise.callAmount) / Double(exercise.pot + exercise.callAmount)
        let expectedEV = analysis.equity * Double(exercise.pot + exercise.callAmount) - Double(exercise.callAmount)
        let borderline = abs(analysis.equity - expectedThreshold) <= analysis.marginOfError
        let recommendation: PokerAction = expectedEV >= 0 ? .call : .fold
        let expectedActions: Set<PokerAction> = borderline ? [.call, .fold] : [recommendation]
        let minimumMargin = analysis.sampleCount == 0 ? 0 : min(1, sqrt(log(40) / (2 * Double(analysis.sampleCount))))
        guard analysis.exerciseId == exercise.id, analysis.selectedAction == action,
              analysis.equity.isFinite, (0...1).contains(analysis.equity),
              analysis.requiredEquity.isFinite, abs(analysis.requiredEquity - expectedThreshold) < 0.000_001,
              analysis.callEV.isFinite, abs(analysis.callEV - expectedEV) < 0.01,
              analysis.marginOfError.isFinite, (0...1).contains(analysis.marginOfError),
              (0...1_000_000).contains(analysis.sampleCount),
              abs(analysis.marginOfError - minimumMargin) < 0.000_001,
              analysis.sampleCount != 0 || analysis.marginOfError == 0,
              analysis.recommendedAction == recommendation,
              Set(analysis.acceptableActions) == expectedActions,
              analysis.acceptableActions.count == expectedActions.count,
              analysis.isCorrect == expectedActions.contains(action),
              (1...2_000).contains(analysis.explanation.count)
        else { throw PokerError.invalidAnalysis }
    }

    /// Best five-card rank from five to seven cards; higher values win. Category then five rank nibbles.
    static func handRank(_ cards: [PokerCard]) -> Int {
        precondition((5...7).contains(cards.count))
        var counts = Array(repeating: 0, count: 15)
        var suitMasks = Array(repeating: 0, count: 4)
        var ranks = 0
        for card in cards {
            counts[card.rank] += 1
            let bit = 1 << card.rank
            ranks |= bit
            let suitIndex: Int
            switch card.suit {
            case .clubs: suitIndex = 0
            case .diamonds: suitIndex = 1
            case .hearts: suitIndex = 2
            case .spades: suitIndex = 3
            }
            suitMasks[suitIndex] |= bit
        }
        let flushMask = suitMasks.first { $0.nonzeroBitCount >= 5 }
        if let flushMask, let high = straightHigh(flushMask) { return encode(8, [high]) }
        let descendingRanks = stride(from: 14, through: 2, by: -1)
        if let quad = descendingRanks.first(where: { counts[$0] == 4 }) {
            return encode(7, [quad] + topRanks(ranks & ~(1 << quad), count: 1))
        }
        let trip = descendingRanks.first { counts[$0] >= 3 }
        if let trip, let pair = descendingRanks.first(where: { $0 != trip && counts[$0] >= 2 }) {
            return encode(6, [trip, pair])
        }
        if let flushMask { return encode(5, topRanks(flushMask, count: 5)) }
        if let high = straightHigh(ranks) { return encode(4, [high]) }
        if let trip { return encode(3, [trip] + topRanks(ranks & ~(1 << trip), count: 2)) }
        let pairs = descendingRanks.filter { counts[$0] == 2 }
        if pairs.count >= 2 {
            return encode(2, Array(pairs.prefix(2)) + topRanks(ranks & ~(1 << pairs[0]) & ~(1 << pairs[1]), count: 1))
        }
        if let pair = pairs.first {
            return encode(1, [pair] + topRanks(ranks & ~(1 << pair), count: 3))
        }
        return encode(0, topRanks(ranks, count: 5))
    }

    private static func straightHigh(_ mask: Int) -> Int? {
        for high in stride(from: 14, through: 6, by: -1) {
            let run = 0b11111 << (high - 4)
            if mask & run == run { return high }
        }
        let wheel = (1 << 14) | (1 << 5) | (1 << 4) | (1 << 3) | (1 << 2)
        return mask & wheel == wheel ? 5 : nil
    }

    private static func topRanks(_ mask: Int, count: Int) -> [Int] {
        var result: [Int] = []
        for rank in stride(from: 14, through: 2, by: -1) where mask & (1 << rank) != 0 {
            result.append(rank)
            if result.count == count { break }
        }
        return result
    }

    private static func encode(_ category: Int, _ ranks: [Int]) -> Int {
        ranks.enumerated().reduce(category << 20) { $0 | ($1.element << (16 - $1.offset * 4)) }
    }

    private static func isCanonicalHand(_ hand: String) -> Bool {
        let characters = Array(hand)
        let labels = Array("23456789TJQKA")
        guard (2...3).contains(characters.count),
              let first = labels.firstIndex(of: characters[0]),
              let second = labels.firstIndex(of: characters[1]) else { return false }
        if characters.count == 2 { return first == second }
        return first > second && (characters[2] == "s" || characters[2] == "o")
    }

    private static func isIdentifier(_ value: String, maximum: Int) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return (1...maximum).contains(value.count) && value.allSatisfy { allowed.contains($0) }
    }
}
