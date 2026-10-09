import SwiftUI

struct TrainingView: View {
    let hand: PokerHand
    let isEvaluating: Bool
    let showRange: () -> Void
    let choose: (HandActionOption) -> Void

    @State private var submittedAmount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                StreetProgress(street: hand.street)
                VStack(spacing: 5) {
                    Eyebrow(text: "\(hand.street.displayName) · TWOJA DECYZJA")
                    Text(hand.toCall > 0 ? "Wchodzisz w to?" : "Twój ruch przy stole.")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(PokerTheme.ivory)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                rangeButton
                PokerHandTable(hand: hand, isEvaluating: isEvaluating && submittedAmount > 0, compact: true)
                    .padding(.horizontal, -5)
                Text(hand.toCall > 0 ? "Do sprawdzenia: \(hand.toCall.formatted()) żetonów." : "Nie musisz dopłacać, żeby pozostać w rozdaniu.")
                    .font(.caption)
                    .foregroundStyle(PokerTheme.muted)
                    .multilineTextAlignment(.center)
                HandHistoryView(history: hand.history)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HandDecisionControls(options: hand.availableActions, heroStack: hand.heroStack, isEvaluating: isEvaluating) { option in
                submittedAmount = option.amount
                choose(option)
            }
        }
    }

    private var rangeButton: some View {
        Button(action: showRange) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.stack")
                    .foregroundStyle(PokerTheme.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hand.backend == nil ? "ZAKRES RYWALA" : "ZAKRESY TRZECH RYWALI")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.7)
                        .foregroundStyle(PokerTheme.muted)
                    Text(hand.backend == nil ? hand.opponentRange.name : "4 graczy · rywale czekają lub sprawdzają")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PokerTheme.ivory)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .foregroundStyle(PokerTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PokerTheme.surface, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.07), lineWidth: 1) }
        }
        .buttonStyle(PokerPressStyle())
        .accessibilityHint("Zobacz opis oraz wszystkie możliwe ręce przeciwnika")
        .accessibilityIdentifier("training.range")
    }
}

private struct StreetProgress: View {
    let street: HandStreet

    private let streets: [HandStreet] = [.flop, .turn, .river, .showdown]
    private var activeIndex: Int { streets.firstIndex(of: street) ?? 0 }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(streets.enumerated()), id: \.element) { index, item in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(index <= activeIndex ? PokerTheme.mint : .white.opacity(0.1))
                        .frame(height: 3)
                    Text(item.displayName)
                        .font(.system(size: 8, weight: index == activeIndex ? .bold : .medium))
                        .tracking(0.8)
                        .foregroundStyle(index == activeIndex ? PokerTheme.ivory : PokerTheme.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Etap rozdania: \(street.displayName)")
    }
}

private struct PokerHandTable: View {
    let hand: PokerHand
    var isEvaluating = false
    var compact = false
    var showdownCardsFrom: Int?

    @State private var arrived = false

    private var firstNewBoardCard: Int {
        if let showdownCardsFrom { return showdownCardsFrom }
        guard hand.status == .awaitingAction,
              !hand.history.contains(where: { $0.player == .hero && $0.street == hand.street }) else { return 5 }
        switch hand.street {
        case .flop: return 0
        case .turn: return 3
        case .river: return 4
        case .showdown: return 5
        }
    }

    private var isFirstDeal: Bool {
        hand.street == .flop && hand.status == .awaitingAction && !hand.history.contains { $0.player == .hero }
    }

    private var revealedOpponentCards: [PokerCard] {
        guard hand.result?.reason == .showdown else { return [] }
        return hand.result?.opponentCards ?? []
    }

    private var chipBurstTrigger: Int {
        guard arrived else { return 0 }
        if isEvaluating { return hand.revision + 2 }
        return (hand.history.last?.amount ?? 0) > 0 ? hand.revision + 1 : 0
    }

    var body: some View {
        ZStack {
            FeltSurface().padding(.horizontal, 3).padding(.vertical, 12)
            VStack(spacing: compact ? 13 : 22) {
                opponent
                pot
                board
                hero
            }
            .padding(.vertical, compact ? 9 : 16)
        }
        .onAppear { arrived = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stół pokerowy")
    }

    @ViewBuilder
    private var opponent: some View {
        if let table = hand.backend {
            HStack(spacing: 12) {
                ForEach(1..<4, id: \.self) { seat in
                    VStack(spacing: 5) {
                        HStack(spacing: 3) {
                            if table.privateCards.count == 4 {
                                ForEach(table.privateCards[seat]) { card in
                                    PlayingCardView(card: card, width: 30)
                                        .pokerDeal(index: seat, trigger: "\(hand.id)-reveal-\(seat)")
                                }
                            } else {
                                PlayingCardView(card: nil, width: 24, isFaceDown: true)
                                PlayingCardView(card: nil, width: 24, isFaceDown: true)
                            }
                        }
                        Text("RYWAL \(seat)").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(PokerTheme.muted)
                        Text(table.stacks[seat], format: .number.precision(.fractionLength(0...2)))
                            .font(.caption.weight(.bold)).foregroundStyle(table.winners.contains(seat) ? PokerTheme.mint : PokerTheme.gold)
                    }.frame(maxWidth: .infinity)
                }
            }.padding(.horizontal, 14).padding(.vertical, 9)
                .background(PokerTheme.background.opacity(0.7), in: .rect(cornerRadius: 20))
                .padding(.horizontal, 14)
        } else {
        HStack(spacing: 12) {
            HStack(spacing: revealedOpponentCards.isEmpty ? -10 : 5) {
                if revealedOpponentCards.isEmpty {
                    PlayingCardView(card: nil, width: 28, isFaceDown: true).rotationEffect(.degrees(-9))
                    PlayingCardView(card: nil, width: 28, isFaceDown: true).rotationEffect(.degrees(9))
                } else {
                    ForEach(Array(revealedOpponentCards.enumerated()), id: \.element.id) { index, card in
                        PlayingCardView(card: card, width: 45)
                            .pokerDeal(index: index + 1, trigger: "\(hand.id)-showdown")
                            .accessibilityIdentifier("result.opponent.\(index)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("RYWAL")
                    .font(.caption2.weight(.medium)).tracking(2)
                    .foregroundStyle(PokerTheme.muted)
                Text(hand.opponentStack == 0 && hand.status == .awaitingAction ? "ALL-IN" : hand.opponentStack.formatted())
                    .font(.caption.weight(.bold)).tracking(1)
                    .foregroundStyle(PokerTheme.gold)
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, compact ? 6 : 10)
        .background(PokerTheme.background.opacity(0.7), in: .capsule)
        }
    }

    private var pot: some View {
        HStack(spacing: 13) {
            ChipStack(color: PokerTheme.gold, count: 3, width: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(hand.status == .completed ? "PULA ROZDANIA" : "W PULI")
                    .font(.system(size: 9, weight: .medium)).tracking(2)
                    .foregroundStyle(PokerTheme.muted)
                Text(hand.pot, format: .number)
                    .font(.system(size: compact ? 25 : 27, weight: .medium, design: .rounded))
                    .foregroundStyle(PokerTheme.ivory)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pula: \(hand.pot) żetonów")
        .accessibilityIdentifier("training.pot")
        .overlay {
            ChipPotBurst(trigger: chipBurstTrigger)
                .frame(width: 235, height: 170)
        }
    }

    private var board: some View {
        HStack(spacing: 7) {
            ForEach(Array(hand.board.enumerated()), id: \.element.id) { index, card in
                PlayingCardView(card: card, width: 47)
                    .pokerDeal(index: max(0, index - firstNewBoardCard), trigger: "\(hand.id)-\(card.id)", animated: index >= firstNewBoardCard)
                    .accessibilityIdentifier("training.board.\(index)")
            }
            ForEach(hand.board.count..<5, id: \.self) { index in
                EmptyCardView(width: 47).accessibilityIdentifier("training.board.\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Karty wspólne")
    }

    private var hero: some View {
        VStack(spacing: compact ? 6 : 10) {
            HStack(spacing: 0) {
                ForEach(Array(hand.heroCards.enumerated()), id: \.element.id) { index, card in
                    PlayingCardView(card: card, width: compact ? 64 : 68)
                        .rotationEffect(.degrees(index == 0 ? -7 : 7))
                        .offset(x: index == 0 ? 2 : -2)
                        .pokerDeal(index: index + 4, trigger: hand.id, animated: isFirstDeal)
                        .accessibilityIdentifier("training.hero.\(index)")
                }
            }
            HStack(spacing: 8) {
                Eyebrow(text: "TY", color: PokerTheme.muted)
                Text(hand.backend?.stacks.first ?? Double(hand.heroStack), format: .number.precision(.fractionLength(0...2)))
                    .font(.caption.weight(.semibold)).foregroundStyle(PokerTheme.ivory)
                Image(systemName: "circle.stack").font(.caption2).foregroundStyle(PokerTheme.gold)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Twoje karty i żetony")
    }
}

private struct HandDecisionControls: View {
    let options: [HandActionOption]
    let heroStack: Int
    let isEvaluating: Bool
    let choose: (HandActionOption) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 10) {
            if isEvaluating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(PokerTheme.mint)
                    Text("Ruch rywala i analiza…").font(.caption).foregroundStyle(PokerTheme.muted)
                }
            }
            GlassEffectContainer(spacing: 10) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) { actionButtons }
                } else if options.count <= 3 {
                    HStack(spacing: 10) { actionButtons }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { actionButtons }
                }
            }
            .disabled(isEvaluating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(PokerTheme.background.opacity(0.94).ignoresSafeArea(edges: .bottom))
    }

    private var actionButtons: some View {
        ForEach(options) { option in
            if option.action == .fold {
                actionButton(option).buttonStyle(.glass).foregroundStyle(PokerTheme.ivory)
            } else {
                actionButton(option).buttonStyle(.glassProminent).tint(PokerTheme.mint).foregroundStyle(PokerTheme.background)
            }
        }
    }

    private func actionButton(_ option: HandActionOption) -> some View {
        Button { choose(option) } label: {
            VStack(spacing: 4) {
                Text(option.amount > 0 && option.amount == heroStack ? "ALL-IN" : option.action.displayName)
                    .font(.headline).tracking(1)
                Text(option.amount > 0 ? "Dopłacam \(option.amount.formatted())" : option.action.polishName)
                    .font(.caption)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: options.count > 2 ? 44 : 55)
        }
        .accessibilityLabel("\(option.action.polishName)\(option.amount > 0 ? ". Dopłacam \(option.amount) żetonów" : "")")
        .accessibilityIdentifier("training.\(option.action.rawValue).\(option.amount)")
    }
}

struct AnalysisView: View {
    let hand: PokerHand
    let analysis: HandAnalysis
    let nextTitle: String
    var isLoading = false
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                StreetProgress(street: analysis.street)
                VStack(alignment: .leading, spacing: 13) {
                    Eyebrow(text: "\(analysis.street.displayName) · TWÓJ RUCH: \(analysis.action.displayName)")
                    Text("Twój ruch.\nZobacz liczby.")
                        .font(.system(.largeTitle, design: .serif)).foregroundStyle(PokerTheme.ivory)
                    Text("Patrzymy na karty i informacje, które znałeś w chwili ruchu.")
                        .font(.subheadline).foregroundStyle(PokerTheme.muted)
                }
                HandRecap(hand: hand)
                DecisionInsight(analysis: analysis, pot: hand.pot, toCall: hand.toCall)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryAction(title: isLoading ? "Odkrywamy karty…" : nextTitle, action: next)
                .disabled(isLoading)
                .accessibilityIdentifier("analysis.next")
                .padding(.horizontal, 24).padding(.vertical, 13)
                .background(PokerTheme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
        }
    }
}

private struct HandRecap: View {
    let hand: PokerHand

    var body: some View {
        HStack(spacing: 7) {
            ForEach(hand.heroCards) { card in PlayingCardView(card: card, width: 32) }
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 24).padding(.horizontal, 5)
            ForEach(hand.board) { card in PlayingCardView(card: card, width: 27) }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Twoje karty i karty wspólne przed decyzją")
    }
}

private struct DecisionInsight: View {
    let analysis: HandAnalysis
    var pot: Int?
    var toCall: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    metric(title: "TWOJE EQUITY", value: analysis.equity, size: 40, color: PokerTheme.mint)
                    Spacer(minLength: 12)
                    if let threshold = analysis.requiredEquity {
                        metric(title: analysis.teaching == nil ? "CENA CALL" : "PRÓG BET", value: threshold, size: 28, color: PokerTheme.gold)
                    }
                }
                VStack(spacing: 12) {
                    bar(value: analysis.equity, color: PokerTheme.mint)
                    if let threshold = analysis.requiredEquity { bar(value: threshold, color: PokerTheme.gold) }
                }
                if let pot, let toCall, toCall > 0, analysis.requiredEquity != nil {
                    Text("Cena sprawdzenia: \(toCall.formatted()) / \((pot + toCall).formatted()) żetonów po call.")
                        .font(.caption).foregroundStyle(PokerTheme.muted)
                } else if analysis.requiredEquity == nil {
                    Label("Check nie wymaga dopłaty.", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(PokerTheme.muted)
                }
                if let ev = analysis.callEV {
                    Divider().overlay(.white.opacity(0.05))
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("EV sprawdzenia").font(.subheadline.weight(.medium)).foregroundStyle(PokerTheme.ivory)
                            Text("Bez dalszych zakładów").font(.caption2).foregroundStyle(PokerTheme.muted)
                        }
                        Spacer(minLength: 8)
                        Text(ev, format: .number.sign(strategy: .always()).precision(.fractionLength(1)))
                            .font(.system(.title2, design: .rounded).weight(.medium))
                            .foregroundStyle(ev >= 0 ? PokerTheme.mint : PokerTheme.coral)
                        Image(systemName: "circle.stack").font(.caption).foregroundStyle(PokerTheme.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let teaching = analysis.teaching {
                    Divider().overlay(.white.opacity(0.05))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(teaching.gradeTitle).font(.headline).foregroundStyle(teaching.grade == "bad" ? PokerTheme.coral : PokerTheme.mint)
                        Text("Model wskazuje: \(teaching.recommendationTitle)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(PokerTheme.ivory)
                        HStack {
                            Text("EV check: \(teaching.checkEV.formatted(.number.precision(.fractionLength(1))))")
                            Spacer()
                            if let ev = teaching.betEV { Text("EV bet: \(ev.formatted(.number.precision(.fractionLength(1))))") }
                        }.font(.caption).foregroundStyle(PokerTheme.muted)
                        Text("Wygrana bez podziału: \(teaching.winProbability.formatted(.percent.precision(.fractionLength(1))))")
                            .font(.caption).foregroundStyle(PokerTheme.gold)
                    }
                }
                Text("\(analysis.sampleCount.formatted()) symulacji · niepewność equity ±\((analysis.marginOfError * 100).formatted(.number.precision(.fractionLength(1)))) p.p. (95%)")
                    .font(.caption2).foregroundStyle(PokerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(23)
            .background(PokerTheme.surface, in: .rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.07), lineWidth: 1) }
            VStack(alignment: .leading, spacing: 12) {
                Label("Co mówi ta sytuacja?", systemImage: "lightbulb.min")
                    .font(.headline).foregroundStyle(PokerTheme.ivory)
                Text(analysis.explanation)
                    .font(.subheadline).foregroundStyle(PokerTheme.muted)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                Text(analysis.teaching == nil ? "Equity to udział w puli względem założonego zakresu rywala. Cena call i jego EV są migawką przy założeniu braku kolejnych zakładów — nie stanowią pełnej oceny strategii na dalsze ulice." : "Equity uwzględnia podziały puli. Próg 25% wynika z zakładu 10 i dopłat trzech rywali. Ocena dotyczy tego uproszczonego modelu, przy niepewności symulacji.")
                    .font(.caption).foregroundStyle(PokerTheme.muted)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.85)) { appeared = true }
        }
    }

    private func metric(title: String, value: Double, size: CGFloat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(PokerTheme.muted)
            Text(value, format: .percent.precision(.fractionLength(1)))
                .font(.system(size: size, weight: .light, design: .rounded))
                .tracking(-1).foregroundStyle(color).contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(value: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.05))
                Capsule().fill(color.gradient)
                    .frame(width: geometry.size.width * (appeared ? min(1, max(0, value)) : 0))
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

struct HandResultView: View {
    let hand: PokerHand
    let decisions: [HandAnalysis]
    let isLastHand: Bool
    let next: () -> Void

    @State private var appeared = false

    private var won: Bool { hand.result?.winner == .hero }
    private var title: String {
        switch hand.result?.winner {
        case .hero: "Pula jest twoja."
        case .opponent: "Pula trafia do rywali."
        case .tie: "Dzielicie pulę."
        case nil: "Koniec rozdania."
        }
    }
    private var newBoardFrom: Int {
        guard hand.result?.reason == .showdown else { return 5 }
        switch decisions.last?.street {
        case .flop: return 3
        case .turn: return 4
        default: return 5
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                StreetProgress(street: hand.result?.reason == .showdown ? .showdown : hand.street)
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: hand.result?.reason == .showdown ? "SHOWDOWN · KARTY NA STÓŁ" : "ROZDANIE ZAKOŃCZONE PASEM")
                    Text(title).font(.system(.largeTitle, design: .serif)).foregroundStyle(PokerTheme.ivory)
                    if let result = hand.result {
                        Text(result.summary).font(.subheadline).foregroundStyle(PokerTheme.muted).lineSpacing(4)
                    }
                }
                PokerHandTable(hand: hand, showdownCardsFrom: newBoardFrom)
                if let result = hand.result {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TWOJA WYPŁATA Z PULI").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(PokerTheme.muted)
                            Text(hand.backend?.payouts.first ?? Double(result.heroPayout), format: .number.precision(.fractionLength(0...2)))
                                .font(.system(.title, design: .rounded).weight(.medium))
                                .foregroundStyle(won ? PokerTheme.mint : PokerTheme.ivory)
                        }
                        Spacer()
                        ChipStack(color: PokerTheme.gold, count: 5, width: 42)
                    }
                    .padding(20)
                    .background(PokerTheme.surface, in: .rect(cornerRadius: 23))
                }
                Text("Wynik jednego rozdania nie przesądza o jakości decyzji. Wróć do liczb z każdej ulicy.")
                    .font(.caption).foregroundStyle(PokerTheme.muted).lineSpacing(4)
                if let table = hand.backend, table.isFoldReview {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Co gdybyś nie spasował?", systemImage: "arrow.triangle.branch").font(.headline).foregroundStyle(PokerTheme.gold)
                        Text(table.hypotheticalWinners.contains(0) ? "W hipotetycznym showdownie miałbyś udział w puli." : "W hipotetycznym showdownie pula trafiłaby do rywali.")
                        Text("To osobny podgląd. Twój faktyczny wynik po pasie nie zawiera wypłaty.")
                    }.font(.subheadline).foregroundStyle(PokerTheme.muted).padding(20)
                        .background(PokerTheme.surface, in: .rect(cornerRadius: 23))
                }
                HandHistoryView(history: hand.history)
                decisionsReview
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryAction(title: isLastHand ? "Zobacz swoją sesję" : "Kolejne rozdanie", action: next)
                .accessibilityIdentifier("result.next")
                .padding(.horizontal, 24).padding(.vertical, 13)
                .background(PokerTheme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
        }
        .overlay {
            PokerCelebrationView(trigger: appeared && won ? 1 : 0, intensity: .hand).ignoresSafeArea()
        }
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared && won)
    }

    private var decisionsReview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Twoje decyzje").font(.headline).foregroundStyle(PokerTheme.ivory)
            ForEach(Array(decisions.enumerated()), id: \.offset) { index, analysis in
                DisclosureGroup {
                    DecisionInsight(analysis: analysis).padding(.top, 17)
                } label: {
                    HStack {
                        Text("\(index + 1). \(analysis.street.displayName)")
                            .font(.subheadline.weight(.medium)).foregroundStyle(PokerTheme.ivory)
                        Spacer()
                        Text(analysis.action.displayName).font(.caption.weight(.bold)).foregroundStyle(PokerTheme.gold)
                    }
                    .padding(.vertical, 6)
                }
                .tint(PokerTheme.muted)
            }
        }
    }
}

private struct HandHistoryView: View {
    let history: [HandHistoryEntry]

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(history) { entry in
                    HStack(spacing: 10) {
                        Text(entry.street.displayName)
                            .font(.system(size: 9, weight: .medium)).tracking(0.6)
                            .foregroundStyle(PokerTheme.muted).frame(width: 58, alignment: .leading)
                        Text(entry.player == .hero ? "Ty" : "Rywal")
                            .font(.caption.weight(.medium)).foregroundStyle(PokerTheme.ivory)
                        Spacer(minLength: 5)
                        Text(entry.action.displayName)
                            .font(.caption.weight(.semibold)).foregroundStyle(entry.player == .hero ? PokerTheme.mint : PokerTheme.gold)
                        if entry.amount > 0 {
                            Text(entry.amount, format: .number)
                                .font(.caption.monospacedDigit()).foregroundStyle(PokerTheme.ivory)
                        }
                    }
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 7)
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(PokerTheme.gold)
                Text("Historia rozdania").font(.subheadline.weight(.medium)).foregroundStyle(PokerTheme.ivory)
                Spacer()
                Text("\(history.count)").font(.caption.monospacedDigit()).foregroundStyle(PokerTheme.muted)
            }
            .frame(minHeight: 30)
        }
        .tint(PokerTheme.muted)
        .padding(17)
        .background(PokerTheme.surface, in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("hand.history")
    }
}

struct SessionSummaryView: View {
    let hands: [PokerHand]
    let decisionCount: Int
    let restart: () -> Void
    let home: () -> Void

    @State private var appeared = false

    private var wonCount: Int { hands.filter { $0.result?.winner == .hero }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                Eyebrow(text: "SESJA ZAKOŃCZONA")
                ZStack {
                    Circle().strokeBorder(PokerTheme.gold.opacity(0.13), lineWidth: 1).frame(width: 195, height: 195)
                    Circle().fill(PokerTheme.emerald.opacity(0.25)).frame(width: 170, height: 170)
                    VStack(spacing: 5) {
                        Image(systemName: "suit.spade.fill").font(.title2).foregroundStyle(PokerTheme.gold)
                        Text("\(hands.count)").font(.system(size: 72, weight: .light, design: .serif)).foregroundStyle(PokerTheme.ivory)
                        Eyebrow(text: "PEŁNYCH ROZDAŃ", color: PokerTheme.muted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hands.count) ukończonych rozdań")
                .accessibilityIdentifier("summary.score")
                VStack(spacing: 10) {
                    Text("Cała historia.\nWięcej doświadczenia.")
                        .font(.system(.largeTitle, design: .serif)).foregroundStyle(PokerTheme.ivory)
                        .multilineTextAlignment(.center)
                    Text("\(decisionCount) decyzji · \(wonCount) wygranych pul")
                        .font(.subheadline.weight(.medium)).foregroundStyle(PokerTheme.gold)
                    Text("Wygrane pule mówią o wyniku sesji.\nLiczby z poszczególnych ulic pomagają zrozumieć grę.")
                        .font(.subheadline).foregroundStyle(PokerTheme.muted)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }
                VStack(spacing: 0) {
                    ForEach(Array(hands.enumerated()), id: \.element.id) { index, hand in
                        summaryRow(index: index, hand: hand)
                        if index < hands.count - 1 { Divider().overlay(.white.opacity(0.04)) }
                    }
                }
                .padding(.horizontal, 18)
                .background(PokerTheme.surface, in: .rect(cornerRadius: 24))
            }
            .padding(.horizontal, 26).padding(.vertical, 25)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 9) {
                PrimaryAction(title: "Jeszcze pięć rozdań", symbol: "arrow.clockwise", action: restart)
                    .accessibilityIdentifier("summary.restart")
                Button("Wróć do początku", action: home)
                    .font(.subheadline).foregroundStyle(PokerTheme.muted)
                    .frame(minHeight: 44).buttonStyle(PokerPressStyle())
                    .accessibilityIdentifier("summary.home")
            }
            .padding(.horizontal, 26).padding(.top, 12)
            .background(PokerTheme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
        }
        .overlay { PokerCelebrationView(trigger: appeared ? 1 : 0, intensity: .session).ignoresSafeArea() }
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared)
    }

    private func summaryRow(index: Int, hand: PokerHand) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(PokerTheme.muted).frame(width: 18)
            HStack(spacing: 3) {
                ForEach(hand.heroCards) { card in PlayingCardView(card: card, width: 23) }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(winnerText(hand.result?.winner)).font(.subheadline.weight(.medium)).foregroundStyle(PokerTheme.ivory)
                Text(hand.result?.reason == .showdown ? "Showdown" : "Rozstrzygnięcie przez pas")
                    .font(.caption2).foregroundStyle(PokerTheme.muted)
            }
            Spacer(minLength: 0)
            Text(hand.pot, format: .number).font(.caption.monospacedDigit()).foregroundStyle(PokerTheme.gold)
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("summary.hand.\(index)")
    }

    private func winnerText(_ winner: HandWinner?) -> String {
        switch winner {
        case .hero: "Twoja pula"
        case .opponent: "Pula rywala"
        case .tie: "Podział puli"
        case nil: "Zakończone"
        }
    }
}
