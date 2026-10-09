import Foundation

struct LocalPokerHand: Sendable {
    private(set) var state: PokerHand
    private let opponentCards: [PokerCard]
    private var remainingDeck: [PokerCard]

    /// An explicit deal initializer also permits deterministic rule tests without changing live randomness.
    init(state: PokerHand, opponentCards: [PokerCard], remainingDeck: [PokerCard]) throws {
        try HandValidation.validate(state)
        let cards = state.heroCards + state.board + opponentCards + remainingDeck
        let combinations = try PokerEngine.legalCombinations(for: state.opponentRange, excluding: Set(state.heroCards + state.board))
        guard state.status == .awaitingAction, opponentCards.count == 2,
              cards.count == 52, Set(cards) == Set(PokerCard.deck),
              combinations.contains(where: { Set([$0.first, $0.second]) == Set(opponentCards) })
        else { throw PokerError.invalidExercise }
        self.state = state
        self.opponentCards = opponentCards
        self.remainingDeck = remainingDeck
    }

    static func start<R: RandomNumberGenerator>(using generator: inout R) throws -> LocalPokerHand {
        try Task.checkCancellation()
        let cards = PokerCard.deck.shuffled(using: &generator)
        let hero = Array(cards.prefix(2))
        let board = Array(cards[2..<5])
        let range = PokerEngine.ranges[Int.random(in: PokerEngine.ranges.indices, using: &generator)]
        let combinations = try PokerEngine.legalCombinations(for: range, excluding: Set(hero + board))
        let opponent = combinations[Int.random(in: combinations.indices, using: &generator)]
        let hidden = [opponent.first, opponent.second]
        let deck = PokerCard.deck.filter { !Set(hero + board + hidden).contains($0) }.shuffled(using: &generator)
        let hand = PokerHand(
            id: UUID().uuidString, revision: 0, street: .flop, status: .awaitingAction,
            heroCards: hero, board: board, pot: 150, heroStack: 1_000, opponentStack: 950, toCall: 50,
            opponentRange: range, availableActions: options(pot: 150, heroStack: 1_000, opponentStack: 950, toCall: 50),
            history: [entry(street: .flop, player: .opponent, action: .bet, amount: 50)], result: nil
        )
        return try LocalPokerHand(state: hand, opponentCards: hidden, remainingDeck: deck)
    }

    mutating func apply<R: RandomNumberGenerator>(_ request: HandActionRequest, using generator: inout R) throws -> HandActionResponse {
        try HandValidation.validateRequest(request, for: state)
        try Task.checkCancellation()
        // Only public information enters the equity calculation. The stored runout and villain are never inputs.
        let estimate = try PokerEngine.estimate(heroCards: state.heroCards, board: state.board, range: state.opponentRange, using: &generator)
        let analysis = Self.analysis(for: state, action: request.action, estimate: estimate)
        var candidate = self
        candidate.advance(request)
        let response = HandActionResponse(hand: candidate.state, analysis: analysis)
        try HandValidation.validate(response, previous: state, request: request)
        try Task.checkCancellation()
        self = candidate
        return response
    }

    private mutating func advance(_ request: HandActionRequest) {
        let before = state
        var pot = before.pot
        var heroStack = before.heroStack
        var opponentStack = before.opponentStack
        var board = before.board
        var history = before.history + [Self.entry(street: before.street, player: .hero, action: request.action, amount: request.amount)]
        var result: HandResult?
        var street = before.street
        var toCall = 0

        if request.action == .fold {
            opponentStack += pot
            result = HandResult(reason: .fold, winner: .opponent, opponentCards: [], heroPayout: 0, opponentPayout: pot, summary: "Pasujesz. Rywal zabiera pulę; jego karty pozostają zakryte.")
        } else {
            heroStack -= request.amount
            pot += request.amount
            if request.action == .bet || request.action == .raise {
                let opponentCall = request.amount - before.toCall
                opponentStack -= opponentCall
                pot += opponentCall
                history.append(Self.entry(street: before.street, player: .opponent, action: .call, amount: opponentCall))
            }

            if before.street == .river || heroStack == 0 || opponentStack == 0 {
                while board.count < 5 { board.append(remainingDeck.removeFirst()) }
                street = .showdown
                let heroRank = PokerEngine.handRank(before.heroCards + board)
                let opponentRank = PokerEngine.handRank(opponentCards + board)
                let winner: HandWinner = heroRank == opponentRank ? .tie : (heroRank > opponentRank ? .hero : .opponent)
                let heroPayout = winner == .hero ? pot : (winner == .tie ? (pot + 1) / 2 : 0)
                let opponentPayout = pot - heroPayout
                heroStack += heroPayout
                opponentStack += opponentPayout
                let summary = winner == .tie ? "Remis. Dzielicie pulę." : (winner == .hero ? "Twój układ wygrywa. Pula trafia do ciebie." : "Rywal ma lepszy układ i wygrywa pulę.")
                result = HandResult(reason: .showdown, winner: winner, opponentCards: opponentCards, heroPayout: heroPayout, opponentPayout: opponentPayout, summary: summary)
            } else {
                board.append(remainingDeck.removeFirst())
                street = board.count == 4 ? .turn : .river
                if street == .turn {
                    history.append(Self.entry(street: street, player: .opponent, action: .check, amount: 0))
                } else {
                    toCall = min(max(1, pot / 2), heroStack, opponentStack)
                    opponentStack -= toCall
                    pot += toCall
                    history.append(Self.entry(street: street, player: .opponent, action: .bet, amount: toCall))
                }
            }
        }
        state = PokerHand(
            id: before.id, revision: before.revision + 1, street: street,
            status: result == nil ? .awaitingAction : .completed,
            heroCards: before.heroCards, board: board, pot: pot, heroStack: heroStack, opponentStack: opponentStack,
            toCall: result == nil ? toCall : 0, opponentRange: before.opponentRange,
            availableActions: result == nil ? Self.options(pot: pot, heroStack: heroStack, opponentStack: opponentStack, toCall: toCall) : [],
            history: history, result: result
        )
    }

    private static func options(pot: Int, heroStack: Int, opponentStack: Int, toCall: Int) -> [HandActionOption] {
        let cap = min(heroStack, opponentStack + toCall)
        if toCall > 0 {
            var options = [HandActionOption(action: .fold, amount: 0), HandActionOption(action: .call, amount: toCall)]
            if cap > toCall {
                let preset = min(cap, toCall * 2)
                options.append(HandActionOption(action: .raise, amount: preset))
                if cap != preset { options.append(HandActionOption(action: .raise, amount: cap)) }
            }
            return options
        }
        let preset = min(cap, max(1, pot / 2))
        var options = [HandActionOption(action: .check, amount: 0)]
        if cap > 0 {
            options.append(HandActionOption(action: .bet, amount: preset))
            if cap != preset { options.append(HandActionOption(action: .bet, amount: cap)) }
        }
        return options
    }

    private static func entry(street: HandStreet, player: HandPlayer, action: HandAction, amount: Int) -> HandHistoryEntry {
        HandHistoryEntry(id: UUID().uuidString, street: street, player: player, action: action, amount: amount)
    }

    private static func analysis(for hand: PokerHand, action: HandAction, estimate: PokerEngine.EquityEstimate) -> HandAnalysis {
        let required = hand.toCall > 0 ? Double(hand.toCall) / Double(hand.pot + hand.toCall) : nil
        let ev = hand.toCall > 0 ? estimate.equity * Double(hand.pot + hand.toCall) - Double(hand.toCall) : nil
        let percentage = (estimate.equity * 100).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pl_PL")))
        let price = required.map { "Próg sprawdzenia wynosi \(($0 * 100).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pl_PL"))))%. Pokazane EV sprawdzenia zakłada brak dalszych kosztów." } ?? "Check jest bezpłatny. Samo equity nie wyznacza najlepszego rozmiaru zakładu."
        return HandAnalysis(
            street: hand.street, action: action, equity: estimate.equity, requiredEquity: required, callEV: ev,
            sampleCount: estimate.sampleCount, marginOfError: estimate.marginOfError,
            explanation: "Przed tym ruchem twój oczekiwany udział w puli wynosił około \(percentage)% przeciwko jawnemu zakresowi. \(price) To obraz tej ulicy, nie ocena całej strategii. W treningu rywal sprawdza twoje zakłady i podbicia; na turnie czeka, a na riverze stawia pół puli."
        )
    }
}

enum HandValidation {
    static func validateRequest(_ request: HandActionRequest, for hand: PokerHand) throws {
        guard identifier(request.requestId), request.expectedRevision == hand.revision,
              hand.status == .awaitingAction,
              hand.availableActions.contains(HandActionOption(action: request.action, amount: request.amount))
        else { throw PokerError.invalidExercise }
    }

    static func validate(_ hand: PokerHand) throws {
        let visible = hand.heroCards + hand.board
        guard identifier(hand.id), (0...1_000_000).contains(hand.revision),
              hand.heroCards.count == 2, (3...5).contains(hand.board.count),
              visible.allSatisfy({ (2...14).contains($0.rank) }), Set(visible).count == visible.count,
              (1...1_000_000).contains(hand.pot), (0...1_000_000).contains(hand.heroStack),
              (0...1_000_000).contains(hand.opponentStack), (0...hand.pot).contains(hand.toCall),
              hand.toCall <= hand.heroStack, hand.history.count <= 100,
              Set(hand.history.map(\.id)).count == hand.history.count,
              hand.history.allSatisfy({ identifier($0.id) && $0.street != .showdown && (0...1_000_000).contains($0.amount) && (($0.action == .check || $0.action == .fold) ? $0.amount == 0 : $0.amount > 0) })
        else { throw PokerError.invalidExercise }
        let combinations = try PokerEngine.legalCombinations(for: hand.opponentRange, excluding: Set(visible))
        if hand.status == .awaitingAction {
            guard hand.result == nil, hand.heroStack > 0,
                  (hand.street == .flop && hand.board.count == 3) || (hand.street == .turn && hand.board.count == 4) || (hand.street == .river && hand.board.count == 5),
                  (1...10).contains(hand.availableActions.count), Set(hand.availableActions.map(\.id)).count == hand.availableActions.count,
                  hand.availableActions.allSatisfy({ option in
                      switch option.action {
                      case .fold: option.amount == 0
                      case .check: hand.toCall == 0 && option.amount == 0
                      case .call: hand.toCall > 0 && option.amount == hand.toCall
                      case .bet: hand.toCall == 0 && option.amount > 0 && option.amount <= min(hand.heroStack, hand.opponentStack)
                      case .raise: hand.toCall > 0 && option.amount > hand.toCall && option.amount <= min(hand.heroStack, hand.opponentStack + hand.toCall)
                      }
                  })
            else { throw PokerError.invalidExercise }
        } else {
            guard let result = hand.result, hand.availableActions.isEmpty, hand.toCall == 0,
                  (1...2_000).contains(result.summary.count), result.heroPayout >= 0, result.opponentPayout >= 0,
                  result.heroPayout <= hand.heroStack, result.opponentPayout <= hand.opponentStack,
                  result.heroPayout <= hand.pot, result.opponentPayout <= hand.pot,
                  result.heroPayout + result.opponentPayout == hand.pot
            else { throw PokerError.invalidExercise }
            if result.reason == .fold {
                guard result.opponentCards.isEmpty, result.winner != .tie,
                      (hand.street == .flop && hand.board.count == 3) || (hand.street == .turn && hand.board.count == 4) || (hand.street == .river && hand.board.count == 5),
                      result.heroPayout == (result.winner == .hero ? hand.pot : 0)
                else { throw PokerError.invalidExercise }
            } else {
                guard hand.street == .showdown, hand.board.count == 5, result.opponentCards.count == 2,
                      Set(visible + result.opponentCards).count == visible.count + 2,
                      combinations.contains(where: { Set([$0.first, $0.second]) == Set(result.opponentCards) })
                else { throw PokerError.invalidExercise }
                let heroRank = PokerEngine.handRank(hand.heroCards + hand.board)
                let opponentRank = PokerEngine.handRank(result.opponentCards + hand.board)
                let expected: HandWinner = heroRank == opponentRank ? .tie : (heroRank > opponentRank ? .hero : .opponent)
                guard result.winner == expected,
                      expected == .tie ? abs(result.heroPayout - result.opponentPayout) <= 1 : result.heroPayout == (expected == .hero ? hand.pot : 0)
                else { throw PokerError.invalidExercise }
            }
        }
    }

    static func validate(_ response: HandActionResponse, previous: PokerHand, request: HandActionRequest) throws {
        try validate(previous)
        try validateRequest(request, for: previous)
        let hand = response.hand
        try validate(hand)
        let additions = hand.history.dropFirst(previous.history.count)
        let heroPaid = additions.filter { $0.player == .hero }.reduce(0) { $0 + $1.amount }
        let opponentPaid = additions.filter { $0.player == .opponent }.reduce(0) { $0 + $1.amount }
        let oldTotal = previous.pot + previous.heroStack + previous.opponentStack
        let newTotal = hand.heroStack + hand.opponentStack + (hand.status == .completed ? 0 : hand.pot)
        guard hand.id == previous.id, hand.revision > previous.revision, hand.heroCards == previous.heroCards,
              hand.opponentRange == previous.opponentRange,
              hand.board.starts(with: previous.board), hand.history.starts(with: previous.history),
              additions.filter({ $0.player == .hero }).count == 1,
              additions.contains(where: { $0.player == .hero && $0.street == previous.street && $0.action == request.action && $0.amount == request.amount }),
              hand.pot == previous.pot + heroPaid + opponentPaid,
              hand.heroStack == previous.heroStack - heroPaid + (hand.result?.heroPayout ?? 0),
              hand.opponentStack == previous.opponentStack - opponentPaid + (hand.result?.opponentPayout ?? 0),
              oldTotal == newTotal,
              request.action != .fold || (hand.status == .completed && hand.result?.reason == .fold && hand.result?.winner == .opponent && hand.board == previous.board && hand.street == previous.street)
        else { throw PokerError.invalidExercise }
        let analysis = response.analysis
        let required = previous.toCall > 0 ? Double(previous.toCall) / Double(previous.pot + previous.toCall) : nil
        let ev = previous.toCall > 0 ? analysis.equity * Double(previous.pot + previous.toCall) - Double(previous.toCall) : nil
        let margin = analysis.sampleCount == 0 ? 0 : min(1, sqrt(log(40) / (2 * Double(analysis.sampleCount))))
        guard analysis.street == previous.street, analysis.action == request.action,
              analysis.equity.isFinite, (0...1).contains(analysis.equity),
              (0...1_000_000).contains(analysis.sampleCount), analysis.marginOfError.isFinite,
              abs(analysis.marginOfError - margin) < 0.000_001,
              equal(analysis.requiredEquity, required, tolerance: 0.000_001), equal(analysis.callEV, ev, tolerance: 0.01),
              (1...2_000).contains(analysis.explanation.count)
        else { throw PokerError.invalidAnalysis }
    }

    private static func identifier(_ value: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return (1...128).contains(value.count) && value.allSatisfy { allowed.contains($0) }
    }

    private static func equal(_ lhs: Double?, _ rhs: Double?, tolerance: Double) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.isFinite && abs(left - right) < tolerance
        default: false
        }
    }
}
