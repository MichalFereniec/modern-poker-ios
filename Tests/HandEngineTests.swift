import Foundation
import Testing
@testable import ModernPokerCore

struct HandEngineTests {
    @Test func sameHand_shouldAdvanceThroughAllThreeStreets() throws {
        var random = HandRandom(seed: 7)
        var game = try LocalPokerHand.start(using: &random)
        let first = game.state
        #expect(first.pot == 150 && first.heroStack == 1_000 && first.opponentStack == 950)
        let flop = try play(.call, game: &game, random: &random)
        #expect(flop.analysis.street == .flop)
        #expect(game.state.street == .turn && game.state.board.count == 4)
        #expect(game.state.pot == 200 && game.state.toCall == 0)
        #expect(game.state.heroStack == 950 && game.state.opponentStack == 950)
        let turn = game.state
        let turnResponse = try play(.check, game: &game, random: &random)
        #expect(turnResponse.analysis.requiredEquity == nil && turnResponse.analysis.callEV == nil)
        #expect(game.state.street == .river && game.state.board.count == 5)
        #expect(game.state.pot == 300 && game.state.toCall == 100)
        #expect(game.state.heroStack == 950 && game.state.opponentStack == 850)
        let river = game.state
        let result = try play(.call, game: &game, random: &random)
        #expect(result.analysis.street == .river)
        #expect(game.state.street == .showdown && game.state.status == .completed)
        #expect(game.state.pot == 400)
        #expect(game.state.heroStack + game.state.opponentStack == 2_100)
        #expect(game.state.heroCards == first.heroCards)
        #expect(game.state.board.starts(with: first.board) && game.state.board.starts(with: turn.board))
        #expect(game.state.board == river.board)
        #expect(game.state.history.starts(with: first.history) && game.state.history.starts(with: turn.history))
        #expect(game.state.result?.opponentCards.count == 2)
    }

    @Test func fold_shouldCompleteWithoutRevealingOrDrawingCards() throws {
        var random = HandRandom(seed: 8)
        var game = try LocalPokerHand.start(using: &random)
        let before = game.state
        _ = try play(.fold, game: &game, random: &random)
        #expect(game.state.board == before.board)
        #expect(game.state.result?.opponentCards == [])
        #expect(game.state.result?.reason == .fold && game.state.result?.winner == .opponent)
        #expect(game.state.heroStack == 1_000 && game.state.opponentStack == 1_100)
        #expect(game.state.availableActions.isEmpty)
        let request = HandActionRequest(requestId: "after_fold", expectedRevision: game.state.revision, action: .call, amount: 50)
        #expect(throws: PokerError.self) { try game.apply(request, using: &random) }
    }

    @Test func raiseAndBet_shouldChargeBothPlayersOnlyTheirAdditionalContribution() throws {
        var random = HandRandom(seed: 9)
        var game = try LocalPokerHand.start(using: &random)
        _ = try play(.raise, game: &game, random: &random)
        #expect(game.state.pot == 300 && game.state.heroStack == 900 && game.state.opponentStack == 900)
        #expect(game.state.history.contains { $0.player == .opponent && $0.action == .call && $0.amount == 50 })
        _ = try play(.bet, game: &game, random: &random)
        #expect(game.state.toCall == 300 && game.state.pot == 900)
        #expect(game.state.heroStack == 750 && game.state.opponentStack == 450)
        #expect(game.state.history.contains { $0.player == .opponent && $0.action == .call && $0.amount == 150 })
    }

    @Test func allIn_shouldRunOutOnceAndPayTheTrueWinner() throws {
        var random = HandRandom(seed: 10)
        var game = try LocalPokerHand.start(using: &random)
        let before = game.state
        let option = try #require(before.availableActions.first { $0.action == .raise && $0.amount == before.heroStack })
        let response = try game.apply(request(option, revision: before.revision), using: &random)
        let result = try #require(response.hand.result)
        #expect(response.hand.status == .completed && response.hand.board.count == 5)
        #expect(response.hand.pot == 2_100)
        #expect(response.hand.heroStack + response.hand.opponentStack == 2_100)
        #expect(response.hand.board.starts(with: before.board))
        #expect(Set(before.heroCards + response.hand.board + result.opponentCards).count == 9)
        #expect(result.heroPayout + result.opponentPayout == 2_100)
        try HandValidation.validate(response, previous: before, request: request(option, revision: before.revision))
    }

    @Test func showdown_shouldSplitRoyalFlushOnBoard() throws {
        var random = HandRandom(seed: 11)
        var game = try fixture(hero: "2c 3d", board: "As Ks Qs", villain: "2h 3h", runout: "Js Ts", hands: ["32s", "32o"])
        _ = try play(.check, game: &game, random: &random)
        _ = try play(.check, game: &game, random: &random)
        _ = try play(.call, game: &game, random: &random)
        #expect(game.state.result?.winner == .tie)
        #expect(game.state.result?.heroPayout == 100 && game.state.result?.opponentPayout == 100)
        #expect(game.state.heroStack == 1_050 && game.state.opponentStack == 1_050)
    }

    @Test func showdown_shouldPayHeroWithUnbeatableRoyalFlush() throws {
        var random = HandRandom(seed: 12)
        var game = try fixture(hero: "As Ks", board: "Qs Js Ts", villain: "Ah Ad", runout: "2c 3c", hands: ["AA"])
        _ = try play(.check, game: &game, random: &random)
        _ = try play(.check, game: &game, random: &random)
        _ = try play(.call, game: &game, random: &random)
        #expect(game.state.result?.winner == .hero)
        #expect(game.state.result?.heroPayout == 200)
        #expect(game.state.heroStack == 1_150 && game.state.opponentStack == 950)
    }

    @Test func analysis_shouldIgnoreActualVillainAndFutureDeck() throws {
        var first = try fixture(hero: "Ac Kd", board: "2s 7h 9d", villain: "Qs Qh", runout: "As Ks", hands: ["QQ", "JJ"])
        var second = try fixture(hero: "Ac Kd", board: "2s 7h 9d", villain: "Js Jh", runout: "3s 4s", hands: ["QQ", "JJ"])
        var firstRandom = HandRandom(seed: 13)
        var secondRandom = HandRandom(seed: 13)
        let firstResponse = try play(.check, game: &first, random: &firstRandom)
        let secondResponse = try play(.check, game: &second, random: &secondRandom)
        #expect(firstResponse.analysis == secondResponse.analysis)
        #expect(firstResponse.hand.board != secondResponse.hand.board)
        #expect(firstResponse.hand.result == nil && secondResponse.hand.result == nil)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(firstResponse.hand)) as? [String: Any])
        #expect(object["opponentCards"] == nil && object["remainingDeck"] == nil)
    }

    @Test func invalidActionAmountAndRevision_shouldLeaveHandUnchanged() throws {
        var random = HandRandom(seed: 14)
        var game = try LocalPokerHand.start(using: &random)
        let before = game.state
        for invalid in [
            HandActionRequest(requestId: "invalid_check", expectedRevision: 0, action: .check, amount: 0),
            HandActionRequest(requestId: "invalid_call", expectedRevision: 0, action: .call, amount: 49),
            HandActionRequest(requestId: "invalid_revision", expectedRevision: 1, action: .call, amount: 50)
        ] {
            #expect(throws: PokerError.self) { try game.apply(invalid, using: &random) }
            #expect(game.state == before)
        }
    }

    @Test func validation_shouldRejectBrokenChipConservationAndCardContinuity() throws {
        var random = HandRandom(seed: 15)
        var game = try LocalPokerHand.start(using: &random)
        let before = game.state
        let option = try #require(before.availableActions.first { $0.action == .call })
        let action = request(option, revision: before.revision)
        let valid = try game.apply(action, using: &random)
        let corrupt = try edited(valid.hand) { $0["heroStack"] = valid.hand.heroStack + 1 }
        #expect(throws: PokerError.self) {
            try HandValidation.validate(HandActionResponse(hand: corrupt, analysis: valid.analysis), previous: before, request: action)
        }
        let duplicates = try edited(valid.hand) { object in
            let hero = object["heroCards"] as! [[String: Any]]
            object["board"] = [hero[0], hero[0], hero[0], hero[0]]
        }
        #expect(throws: PokerError.self) { try HandValidation.validate(duplicates) }
    }

    private func play(_ action: HandAction, game: inout LocalPokerHand, random: inout HandRandom) throws -> HandActionResponse {
        let option = try #require(game.state.availableActions.first { $0.action == action })
        return try game.apply(request(option, revision: game.state.revision), using: &random)
    }

    private func request(_ option: HandActionOption, revision: Int) -> HandActionRequest {
        HandActionRequest(requestId: "request_\(revision)", expectedRevision: revision, action: option.action, amount: option.amount)
    }

    private func fixture(hero: String, board: String, villain: String, runout: String, hands: [String]) throws -> LocalPokerHand {
        let heroCards = cards(hero)
        let community = cards(board)
        let opponent = cards(villain)
        let future = cards(runout)
        let excluded = Set(heroCards + community + opponent + future)
        let hand = PokerHand(
            id: "fixture", revision: 0, street: .flop, status: .awaitingAction,
            heroCards: heroCards, board: community, pot: 100, heroStack: 1_000, opponentStack: 1_000, toCall: 0,
            opponentRange: OpponentRange(id: "test", name: "Test", description: "Jawny zakres", hands: hands),
            availableActions: [HandActionOption(action: .check, amount: 0), HandActionOption(action: .bet, amount: 50), HandActionOption(action: .bet, amount: 1_000)],
            history: [], result: nil
        )
        return try LocalPokerHand(state: hand, opponentCards: opponent, remainingDeck: future + PokerCard.deck.filter { !excluded.contains($0) })
    }

    private func edited(_ hand: PokerHand, change: (inout [String: Any]) -> Void) throws -> PokerHand {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(hand)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(PokerHand.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func cards(_ text: String) -> [PokerCard] {
        let ranks = Array("23456789TJQKA")
        return text.split(separator: " ").map { token in
            let chars = Array(token)
            return PokerCard(rank: ranks.firstIndex(of: chars[0])! + 2, suit: Suit(rawValue: String(chars[1]))!)
        }
    }
}

private struct HandRandom: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
