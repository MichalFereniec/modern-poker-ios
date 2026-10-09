import SwiftUI

struct ModernPokerRoot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = TrainingStore()
    @State private var sheet: PokerSheet?
    @State private var showsExitConfirmation = false

    var body: some View {
        ZStack {
            PokerBackground()
            VStack(spacing: 0) {
                navigationBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(PokerTheme.mint)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.screen)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.analysis?.street)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .help:
                PokerHelpSheet()
            case .settings:
                PokerSettingsSheet(store: store)
            case let .ranges(ranges):
                TabView {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                        PokerRangeSheet(range: range).tabItem { Label("Rywal \(index + 1)", systemImage: "person.fill") }
                    }
                }
            case let .range(range):
                PokerRangeSheet(range: range)
            }
        }
        .confirmationDialog("Zakończyć obecną sesję?", isPresented: $showsExitConfirmation, titleVisibility: .visible) {
            Button("Wróć do początku", role: .destructive) { store.leaveSession() }
            Button("Gram dalej", role: .cancel) {}
        } message: {
            Text("Postęp tej sesji zostanie wyzerowany.")
        }
    }

    private var navigationBar: some View {
        GlassEffectContainer(spacing: 16) {
            HStack {
                if store.screen == .home {
                    PokerWordmark()
                    Spacer()
                    roundButton("Jak grać", symbol: "questionmark") { sheet = .help }
                    roundButton("Ustawienia", symbol: "slider.horizontal.3") { sheet = .settings }
                } else {
                    roundButton("Zamknij sesję", symbol: "xmark") {
                        if store.screen == .summary { store.leaveSession() } else { showsExitConfirmation = true }
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Text(store.screen == .summary ? "TWÓJ POSTĘP" : "ROZDANIE \(store.handNumber) / \(store.sessionLength)")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(PokerTheme.muted)
                        SessionProgress(current: store.screen == .summary ? store.sessionLength : store.handNumber, total: store.sessionLength)
                    }
                    Spacer()
                    roundButton("Jak grać", symbol: "questionmark") { sheet = .help }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 9)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private var content: some View {
        switch store.screen {
        case .home:
            HomeView(start: { Task { await store.start() } }, showHelp: { sheet = .help })
                .transition(.opacity)
        case .training:
            if let error = store.errorMessage {
                errorView(error)
            } else if let hand = store.hand {
                if let analysis = store.analysis, let previous = store.decisionHand {
                    AnalysisView(hand: previous, analysis: analysis, nextTitle: continuationTitle(for: hand), isLoading: store.isEvaluating) {
                        Task { await store.advanceHand() }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if hand.status == .completed {
                    HandResultView(hand: hand, decisions: store.decisions, isLastHand: store.results.count >= store.sessionLength) {
                        Task { await store.next() }
                    }
                    .transition(.opacity)
                } else {
                    TrainingView(hand: hand, isEvaluating: store.isEvaluating, showRange: {
                        if let ranges = hand.backend?.ranges { sheet = .ranges(ranges) }
                        else { sheet = .range(hand.opponentRange) }
                    }) { option in
                        Task { await store.choose(option) }
                    }
                    .id("\(hand.id)-\(hand.revision)")
                    .transition(.opacity)
                }
            } else {
                loadingView
            }
        case .summary:
            SessionSummaryView(hands: store.results, decisionCount: store.decisionCount, restart: { Task { await store.start() } }, home: { store.leaveSession() })
                .transition(.opacity)
        }
    }

    private func continuationTitle(for hand: PokerHand) -> String {
        if hand.backend?.needsContinuation == true {
            switch hand.street {
            case .flop: return "Odkryj turn"
            case .turn: return "Odkryj river"
            default: return "Odkryj karty rywali"
            }
        }
        if hand.status == .completed {
            return hand.result?.reason == .showdown ? "Odkryj karty rywala" : "Zobacz wynik rozdania"
        }
        if hand.street == store.analysis?.street { return "Kontynuuj licytację" }
        switch hand.street {
        case .flop: return "Wróć do stołu"
        case .turn: return "Odkryj turn"
        case .river: return "Odkryj river"
        case .showdown: return "Odkryj karty rywala"
        }
    }

    private func roundButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 31, height: 31)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(PokerTheme.ivory)
        .accessibilityLabel(title)
    }

    private var loadingView: some View {
        VStack(spacing: 28) {
            HStack(spacing: -18) {
                PlayingCardView(card: nil, width: 65, isFaceDown: true).rotationEffect(.degrees(-13))
                PlayingCardView(card: nil, width: 65, isFaceDown: true)
                PlayingCardView(card: nil, width: 65, isFaceDown: true).rotationEffect(.degrees(13))
            }
            .accessibilityHidden(true)
            VStack(spacing: 13) {
                Text("Nowe rozdanie.\nNowe możliwości.")
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(PokerTheme.ivory)
                    .multilineTextAlignment(.center)
                ProgressView().tint(PokerTheme.mint)
                Text("Tasujemy karty…").font(.subheadline).foregroundStyle(PokerTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(errorTitle, systemImage: store.errorRecovery == .replaceHand ? "clock.arrow.circlepath" : "wifi.exclamationmark")
                .foregroundStyle(PokerTheme.ivory)
        } description: {
            Text(message).foregroundStyle(PokerTheme.muted)
        } actions: {
            Button(errorActionTitle) {
                if store.errorRecovery == .settings {
                    sheet = .settings
                } else {
                    Task { await store.retry() }
                }
            }
                .buttonStyle(.glassProminent)
                .tint(PokerTheme.mint)
                .foregroundStyle(PokerTheme.background)
                .accessibilityIdentifier("training.recover")
        }
    }

    private var errorTitle: String {
        switch store.errorRecovery {
        case .retry: "Przerwa przy stole"
        case .replaceHand: "Czas na nowe rozdanie"
        case .settings: "Sprawdź adres serwera"
        }
    }

    private var errorActionTitle: String {
        switch store.errorRecovery {
        case .retry: "Spróbuj ponownie"
        case .replaceHand: "Wylosuj nowe rozdanie"
        case .settings: "Otwórz ustawienia"
        }
    }
}

private enum PokerSheet: Identifiable {
    case help
    case settings
    case range(OpponentRange)
    case ranges([OpponentRange])

    var id: String {
        switch self {
        case .help: "help"
        case .settings: "settings"
        case .ranges: "ranges"
        case let .range(range): "range-\(range.id)"
        }
    }
}

private struct PokerRangeSheet: View {
    let range: OpponentRange
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 13) {
                        Eyebrow(text: "CZYTAJ RYWALA")
                        Text(range.name)
                            .font(.system(.largeTitle, design: .serif))
                            .foregroundStyle(PokerTheme.ivory)
                        Text(range.description)
                            .font(.body)
                            .foregroundStyle(PokerTheme.muted)
                            .lineSpacing(5)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Możliwe ręce").font(.headline).foregroundStyle(PokerTheme.ivory)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 9)], spacing: 9) {
                            ForEach(range.hands, id: \.self) { hand in
                                Text(hand)
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(PokerTheme.gold)
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(PokerTheme.emerald.opacity(0.5), in: .rect(cornerRadius: 12))
                            }
                        }
                        Text("s — karty w tym samym kolorze · o — w różnych kolorach. Para, np. QQ, oznacza dwie damy.")
                            .font(.caption)
                            .foregroundStyle(PokerTheme.muted)
                            .lineSpacing(4)
                    }
                    Label {
                        Text("Nie znasz kart rywala. W tym ćwiczeniu zakładamy, że jego ręka jest losowana z tego zakresu. Każda dostępna kombinacja kart ma taką samą wagę.")
                            .font(.subheadline)
                            .lineSpacing(4)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(PokerTheme.gold)
                    }
                    .foregroundStyle(PokerTheme.muted)
                    .padding(19)
                    .background(PokerTheme.surface, in: .rect(cornerRadius: 20))
                }
                .padding(25)
            }
            .background(PokerTheme.background)
            .navigationTitle("Zakres rywala")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct PokerHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 27) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "ZROZUM SWÓJ RUCH")
                        Text("Dobry poker\nto dobre decyzje.")
                            .font(.system(.largeTitle, design: .serif))
                            .foregroundStyle(PokerTheme.ivory)
                        Text("Texas Hold’em. Ty, rywale i decyzja, która ma znaczenie.")
                            .font(.subheadline)
                            .foregroundStyle(PokerTheme.muted)
                    }
                    helpRow("01", title: "Jedno rozdanie, kolejne ulice", text: "Zaczynasz na flopie z trzema kartami wspólnymi. Twoje dwie karty i karty rywala pozostają te same. Po zamknięciu licytacji odkrywasz turn, potem river. Showdown ujawnia rękę rywala i zwycięzcę.")
                    helpRow("02", title: "Wybierz swój ruch", text: "CHECK: czekasz bez dopłaty. CALL: sprawdzasz. BET i RAISE: stawiasz lub przebijasz o pokazany rozmiar. Kwota oznacza żetony dopłacane teraz, także przy raise. FOLD kończy rozdanie od razu. Po sprawdzonym all-in pozostałe karty odkrywają się bez dalszych zakładów.")
                    helpRow("03", title: "Poznaj liczby po decyzji", text: "Equity to oczekiwany udział w puli przeciwko podanemu zakresowi. Próg call i jego wartość są punktem odniesienia bez kosztów przyszłych zakładów, a nie pełną oceną strategii. Analizę liczymy z kart znanych przed twoim ruchem.")
                    helpRow("04", title: "Tryb lokalny", text: "W lokalnym treningu rywal stawia 50 na flopie, czeka na turnie i stawia połowę puli na riverze. Sprawdza twoje zakłady i przebicia. To uproszczony model do nauki przebiegu rozdania; W trybie backendu grasz przeciwko trzem rywalom: możesz czekać, postawić 10 lub spasować. Rywale czekają albo sprawdzają. Po analizie odkrywasz kolejną kartę. Po pasie przeglądasz osobny hipotetyczny wynik, bez wypłaty dla ciebie.")
                    Text("Gramy o wiedzę. Wszystkie żetony są wirtualne.")
                        .font(.caption)
                        .foregroundStyle(PokerTheme.gold)
                }
                .padding(25)
            }
            .background(PokerTheme.background)
            .navigationTitle("Przy stole")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func helpRow(_ number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(PokerTheme.gold)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline).foregroundStyle(PokerTheme.ivory)
                Text(text).font(.subheadline).foregroundStyle(PokerTheme.muted).lineSpacing(5)
            }
        }
    }
}

private struct PokerSettingsSheet: View {
    let store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var usesBackend: Bool
    @State private var serverAddress: String
    @State private var invalidURL = false

    init(store: TrainingStore) {
        self.store = store
        _usesBackend = State(initialValue: store.usesBackend)
        _serverAddress = State(initialValue: store.serverAddress)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Korzystaj z backendu", isOn: $usesBackend)
                    if usesBackend {
                        TextField("Adres serwera", text: $serverAddress, prompt: Text("http://localhost:8080"))
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Adres serwera backendu")
                    }
                } header: {
                    Text("Źródło rozdań")
                } footer: {
                    Text(usesBackend ? "Serwer generuje rozdania i ocenia decyzje zgodnie z kontraktem OpenAPI. Na fizycznym iPhonie użyj adresu serwera w sieci lokalnej." : "Rozdania są losowane na urządzeniu. Equity liczymy symulacją Monte Carlo. Połączenie z internetem nie jest potrzebne.")
                }
                if invalidURL {
                    Section {
                        Label("Podaj poprawny adres HTTP lub HTTPS, bez loginu, hasła, parametrów ani fragmentu.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(PokerTheme.coral)
                    }
                }
                Section {
                    LabeledContent("Gra", value: "Texas Hold’em")
                    LabeledContent("Sesja", value: "5 rozdań")
                    LabeledContent("Żetony", value: "Wirtualne")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PokerTheme.background)
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz", action: save)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        if store.configure(backend: usesBackend, address: serverAddress) {
            dismiss()
        } else {
            invalidURL = true
        }
    }
}
