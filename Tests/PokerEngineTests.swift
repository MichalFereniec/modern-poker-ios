import Foundation
import Testing
@testable import ModernPokerCore

struct PokerEngineTests {
    @Test(arguments: [
        ("As Ks Qs Js Ts 2c 3d", "9s 8s 7s 6s 5s 2c 3d"),
        ("9s 8s 7s 6s 5s 2c 3d", "As Ah Ad Ac Ks 2c 3d"),
        ("As Ah Ad Ac Ks 2c 3d", "Ks Kh Kd Qs Qh 2c 3d"),
        ("Ks Kh Kd Qs Qh 2c 3d", "As Js 9s 7s 4s 2c 3d"),
        ("As Js 9s 7s 4s 2c 3d", "9s 8h 7d 6c 5s 2c 3d"),
        ("9s 8h 7d 6c 5s 2c 3d", "As Ah Ad Ks Qh 2c 3d"),
        ("As Ah Ad Ks Qh 2c 3d", "As Ah Ks Kh Qh 2c 3d"),
        ("As Ah Ks Kh Qh 2c 3d", "As Ah Ks Qh Jh 2c 3d"),
        ("As Ah Ks Qh Jh 2c 3d", "As Kh Qd Jh 9h 2c 3d"),
        ("6s 5h 4d 3c 2s Kh Qd", "As 5h 4d 3c 2s Kh Qd"),
        ("As 5h 4d 3c 2s Kh Qd", "Ks Kh Kd Qs Jh 2c 3d"),
        ("As Ah Ad Ks Kh Kd 2c", "As Ah Ad Qs Qh Qd 2c"),
        ("As Ah Ks Kh Qs Qh 2c", "As Ah Ks Kh Js Jh 2c"),
        ("As Ah Ad Ac Ks 2c 3d", "As Ah Ad Ac Qs 2c 3d"),
        ("As Ah Ks Qh Jh 2c 3d", "As Ah Ks Qh Th 2c 3d"),
        ("As Js 9s 7s 4s 2c 3d", "As Js 9s 6s 4s 2c 3d")
    ])
    func handRank_shouldRespectCategoriesAndKickers(_ stronger: String, _ weaker: String) {
        #expect(PokerEngine.handRank(cards(stronger)) > PokerEngine.handRank(cards(weaker)))
    }

    @Test func handRank_shouldSplitPot_whenBestFiveCardsAreEqual() {
        let board = cards("As Ks Qs Js Ts")
        #expect(PokerEngine.handRank(board + cards("2c 3d")) == PokerEngine.handRank(board + cards("9h 9d")))
    }

    @Test func handRank_shouldChooseBestFive_fromSevenCards() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            let seven = Array(PokerCard.deck.shuffled(using: &generator).prefix(7))
            var best = 0
            for first in 0..<7 {
                for second in (first + 1)..<7 {
                    let five = seven.enumerated().filter { $0.offset != first && $0.offset != second }.map(\.element)
                    best = max(best, PokerEngine.handRank(five))
                }
            }
            #expect(PokerEngine.handRank(seven) == best)
        }
    }

    @Test(arguments: [("AA", 6), ("AKs", 4), ("AKo", 12)])
    func legalCombinations_shouldWeightConcreteHands(_ hand: String, _ count: Int) throws {
        let range = OpponentRange(id: "test", name: "Test", description: "Test", hands: [hand])
        #expect(try PokerEngine.legalCombinations(for: range, excluding: []).count == count)
    }

    @Test func legalCombinations_shouldRemoveBlockedCards() throws {
        let range = OpponentRange(id: "test", name: "Test", description: "Test", hands: ["AA", "AKs", "AKo"])
        let blocked = Set(cards("As Kh"))
        let combinations = try PokerEngine.legalCombinations(for: range, excluding: blocked)
        #expect(combinations.count == 12) // 3 AA + 9 AK combinations.
        #expect(combinations.allSatisfy { !blocked.contains($0.first) && !blocked.contains($0.second) })
    }

    @Test(arguments: [["AK"], ["KAs"], ["AAo"], ["XX"], ["AA", "AA"], [String]()])
    func legalCombinations_shouldRejectInvalidNotation(_ hands: [String]) {
        let range = OpponentRange(id: "test", name: "Test", description: "Test", hands: hands)
        #expect(throws: PokerError.self) { try PokerEngine.legalCombinations(for: range, excluding: []) }
    }

    @Test func validate_shouldRejectFullyBlockedRange() {
        let exercise = exercise(hero: "As Ah", board: "Ad Ac 2c", hands: ["AA"])
        #expect(throws: PokerError.self) { try PokerEngine.validate(exercise) }
    }

    @Test func validate_shouldRejectDuplicateCardsAndInvalidAmounts() {
        #expect(throws: PokerError.self) {
            try PokerEngine.validate(exercise(hero: "As Ah", board: "As 3c 2c"))
        }
        #expect(throws: PokerError.self) {
            try PokerEngine.validate(exercise(pot: 20, call: 50))
        }
        #expect(throws: PokerError.self) {
            try PokerEngine.validate(exercise(pot: 0, call: 0))
        }
    }

    @Test func generate_shouldProduceValidDistinctRandomDeals() throws {
        var generator = SeededGenerator(seed: 19)
        var seenHeroes = Set<[PokerCard]>()
        var boardCounts = Set<Int>()
        for _ in 0..<100 {
            let exercise = try PokerEngine.generate(using: &generator)
            try PokerEngine.validate(exercise)
            seenHeroes.insert(exercise.heroCards)
            boardCounts.insert(exercise.board.count)
            #expect(Set(exercise.heroCards + exercise.board).count == exercise.heroCards.count + exercise.board.count)
        }
        #expect(seenHeroes.count > 90)
        #expect(boardCounts == [3, 4])
    }

    @Test func estimate_shouldAgreeWithKnownTwoOutDraw() throws {
        // AA vs KK on 2-7-9-3: only either remaining king wins for KK (2 of 44 river cards).
        let exercise = exercise(hero: "As Ah", board: "2c 7d 9h 3s", hands: ["KK"])
        var generator = SeededGenerator(seed: 724)
        let estimate = try PokerEngine.estimate(exercise, sampleCount: 10_000, using: &generator)
        #expect(abs(estimate.equity - 42.0 / 44.0) < 0.012)
        #expect(estimate.marginOfError > 0)
    }

    @Test func estimate_shouldAlwaysWinWithRoyalFlush() throws {
        let exercise = exercise(hero: "As Ks", board: "Qs Js Ts", hands: ["AA", "KK", "QQ"])
        var generator = SeededGenerator(seed: 123)
        let estimate = try PokerEngine.estimate(exercise, sampleCount: 500, using: &generator)
        #expect(estimate.equity == 1)
        #expect(estimate.marginOfError > 0) // Sampling certainty is not proof of exact enumeration.
    }

    @Test func estimate_shouldAwardHalfPotForEveryTie() throws {
        // Same ranks in both hands and a rainbow turn: every possible river gives equal best hands.
        let exercise = exercise(hero: "2c 3d", board: "As Kh Qd Jc", hands: ["32o"])
        var generator = SeededGenerator(seed: 456)
        let estimate = try PokerEngine.estimate(exercise, sampleCount: 1_000, using: &generator)
        #expect(estimate.equity == 0.5)
    }

    @Test(arguments: [(0.2, PokerAction.fold, -10.0), (0.3, PokerAction.call, 10.0)])
    func analyze_shouldUsePriceOfCallAndCurrentPot(_ equity: Double, _ recommendation: PokerAction, _ ev: Double) throws {
        let exercise = exercise(pot: 150, call: 50)
        let analysis = PokerEngine.analyze(exercise, action: recommendation, estimate: PokerEngine.EquityEstimate(equity: equity, sampleCount: 0))
        #expect(analysis.requiredEquity == 0.25)
        #expect(abs(analysis.callEV - ev) < 0.000_001)
        #expect(analysis.recommendedAction == recommendation)
        #expect(analysis.acceptableActions == [recommendation])
        #expect(analysis.isCorrect)
        try PokerEngine.validate(analysis, for: exercise, action: recommendation)
    }

    @Test func analyze_shouldAcceptBothActions_whenUncertaintyOverlapsThreshold() throws {
        let exercise = exercise(pot: 150, call: 50)
        let estimate = PokerEngine.EquityEstimate(equity: 0.255, sampleCount: 5_000)
        for action in [PokerAction.call, .fold] {
            let analysis = PokerEngine.analyze(exercise, action: action, estimate: estimate)
            #expect(Set(analysis.acceptableActions) == [.call, .fold])
            #expect(analysis.isCorrect)
            try PokerEngine.validate(analysis, for: exercise, action: action)
        }
    }

    @Test func validate_shouldRejectInconsistentAnalysis() {
        let exercise = exercise()
        let analysis = DecisionAnalysis(
            exerciseId: exercise.id, selectedAction: .call, equity: 0.1,
            requiredEquity: 0.25, callEV: -30, recommendedAction: .fold,
            acceptableActions: [.call], isCorrect: true, explanation: "Test",
            sampleCount: 5_000, marginOfError: 0.02
        )
        #expect(throws: PokerError.self) { try PokerEngine.validate(analysis, for: exercise, action: .call) }
    }

    @Test func coding_shouldRoundTripWithoutLeakingAnalysisInExercise() throws {
        let exercise = exercise()
        let data = try JSONEncoder().encode(exercise)
        let decoded = try JSONDecoder().decode(PokerExercise.self, from: data)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "heroCards", "board", "pot", "callAmount", "opponentRange"])
        #expect(decoded.heroCards == exercise.heroCards)
        #expect(decoded.opponentRange == exercise.opponentRange)
    }

    @Test func openAPI_shouldDecodeAndValidateItsPublishedExamples() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("docs/openapi-v1.json"))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let components = try #require(document["components"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        let exerciseSchema = try #require(schemas["PokerExercise"] as? [String: Any])
        let analysisSchema = try #require(schemas["DecisionAnalysis"] as? [String: Any])
        let exercises = try #require(exerciseSchema["examples"] as? [[String: Any]])
        let analyses = try #require(analysisSchema["examples"] as? [[String: Any]])
        let exercise = try JSONDecoder().decode(PokerExercise.self, from: JSONSerialization.data(withJSONObject: #require(exercises.first)))
        let analysis = try JSONDecoder().decode(DecisionAnalysis.self, from: JSONSerialization.data(withJSONObject: #require(analyses.first)))
        try PokerEngine.validate(exercise)
        try PokerEngine.validate(analysis, for: exercise, action: analysis.selectedAction)
    }

    @Test func service_shouldPreserveEquityAcrossRepeatedDecisions() async throws {
        let service = PokerService()
        let exercise = try await service.nextExercise()
        let call = try await service.evaluate(exercise, action: .call)
        let fold = try await service.evaluate(exercise, action: .fold)
        #expect(call.equity == fold.equity)
        #expect(call.callEV == fold.callEV)
        try PokerEngine.validate(call, for: exercise, action: .call)
        try PokerEngine.validate(fold, for: exercise, action: .fold)
    }

    @Test func service_shouldRespectCancellation() async {
        let task = Task {
            let service = PokerService()
            let exercise = try await service.nextExercise()
            return try await service.evaluate(exercise, action: .call)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled evaluation unexpectedly completed")
        } catch {
            #expect(error is CancellationError)
        }
    }

    private func exercise(
        hero: String = "As Ah", board: String = "2c 7d 9h", hands: [String] = ["KK"],
        pot: Int = 150, call: Int = 50
    ) -> PokerExercise {
        PokerExercise(
            id: "test_exercise", heroCards: cards(hero), board: cards(board), pot: pot, callAmount: call,
            opponentRange: OpponentRange(id: "test_range", name: "Test", description: "Test", hands: hands)
        )
    }

    private func cards(_ notation: String) -> [PokerCard] {
        notation.split(separator: " ").map { token in
            let symbols = Array(token)
            let labels = Array("23456789TJQKA")
            return PokerCard(rank: labels.firstIndex(of: symbols[0])! + 2, suit: Suit(rawValue: String(symbols[1]))!)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
