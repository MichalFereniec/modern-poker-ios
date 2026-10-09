import SwiftUI

enum PokerTheme {
    static let background = Color(red: 0.035, green: 0.065, blue: 0.065)
    static let surface = Color(red: 0.075, green: 0.11, blue: 0.105)
    static let emerald = Color(red: 0.035, green: 0.26, blue: 0.21)
    static let mint = Color(red: 0.57, green: 0.91, blue: 0.74)
    static let gold = Color(red: 0.88, green: 0.77, blue: 0.54)
    static let ivory = Color(red: 0.96, green: 0.95, blue: 0.89)
    static let muted = Color(red: 0.63, green: 0.70, blue: 0.66)
    static let coral = Color(red: 1, green: 0.63, blue: 0.49)
}

struct PokerBackground: View {
    var body: some View {
        ZStack {
            PokerTheme.background
            RadialGradient(
                colors: [PokerTheme.emerald.opacity(0.65), .clear],
                center: .init(x: 0.8, y: 0.28),
                startRadius: 10,
                endRadius: 460
            )
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
            }
        }
        .ignoresSafeArea()
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = PokerTheme.gold

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(2.2)
            .foregroundStyle(color)
    }
}

struct PokerWordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(PokerTheme.gold)
            VStack(alignment: .leading, spacing: 0) {
                Text("MODERN")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                Text("POKER")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .tracking(4)
            }
            .foregroundStyle(PokerTheme.ivory)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Modern Poker")
    }
}

struct PlayingCardView: View {
    let card: PokerCard?
    let width: CGFloat
    var isFaceDown = false

    private var ink: Color {
        guard let card else { return PokerTheme.background }
        return card.suit == .hearts || card.suit == .diamonds
            ? Color(red: 0.69, green: 0.16, blue: 0.18)
            : Color(red: 0.055, green: 0.12, blue: 0.11)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.115)
                .fill(isFaceDown ? PokerTheme.emerald : PokerTheme.ivory)
            if isFaceDown {
                cardBack
            } else if let card {
                cardFace(card)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: width * 0.115)
                .strokeBorder(.white.opacity(isFaceDown ? 0.2 : 0.65), lineWidth: 1)
        }
        .frame(width: width, height: width * 1.43)
        .shadow(color: .black.opacity(0.28), radius: width * 0.14, x: 0, y: width * 0.07)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func cardFace(_ card: PokerCard) -> some View {
        ZStack {
            Image(systemName: symbolName(card.suit))
                .font(.system(size: width * 0.47, weight: .regular))
                .offset(y: width * 0.11)
            VStack {
                HStack(alignment: .top) {
                    VStack(spacing: -width * 0.04) {
                        Text(card.rank == 10 ? "10" : card.rankLabel)
                            .font(.system(size: width * 0.27, weight: .semibold, design: .serif))
                        Text(card.suitSymbol)
                            .font(.system(size: width * 0.23))
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Text(card.rank == 10 ? "10" : card.rankLabel)
                        .font(.system(size: width * 0.19, weight: .semibold, design: .serif))
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(width * 0.105)
        }
        .foregroundStyle(ink)
    }

    private var cardBack: some View {
        ZStack {
            Canvas { context, size in
                var path = Path()
                for offset in stride(from: -size.height, through: size.width, by: 8) {
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                }
                context.stroke(path, with: .color(PokerTheme.gold.opacity(0.13)), lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: width * 0.11))
            RoundedRectangle(cornerRadius: width * 0.07)
                .strokeBorder(PokerTheme.gold.opacity(0.65), lineWidth: 1)
                .padding(width * 0.085)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: width * 0.35))
                .foregroundStyle(PokerTheme.gold)
        }
    }

    private var accessibilityDescription: String {
        guard !isFaceDown, let card else { return "Zakryta karta" }
        let rank: String = switch card.rank {
        case 14: "As"
        case 13: "Król"
        case 12: "Dama"
        case 11: "Walet"
        default: String(card.rank)
        }
        let suit: String = switch card.suit {
        case .clubs: "trefl"
        case .diamonds: "karo"
        case .hearts: "kier"
        case .spades: "pik"
        }
        return "\(rank) \(suit)"
    }

    private func symbolName(_ suit: Suit) -> String {
        switch suit {
        case .clubs: "suit.club.fill"
        case .diamonds: "suit.diamond.fill"
        case .hearts: "suit.heart.fill"
        case .spades: "suit.spade.fill"
        }
    }
}

struct EmptyCardView: View {
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.115)
            .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            .overlay {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: width * 0.28))
                    .foregroundStyle(.white.opacity(0.08))
            }
            .frame(width: width, height: width * 1.43)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Karta jeszcze nieodkryta")
    }
}

struct ChipStack: View {
    let color: Color
    var count = 5
    var width: CGFloat = 48

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Ellipse()
                    .fill(color.gradient)
                    .overlay {
                        Ellipse().strokeBorder(.black.opacity(0.22), lineWidth: 1)
                        Ellipse()
                            .strokeBorder(PokerTheme.ivory.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [5, 9]))
                            .padding(3)
                    }
                    .frame(width: width, height: width * 0.4)
                    .offset(y: -CGFloat(index) * 5)
            }
        }
        .frame(width: width, height: width * 0.4 + CGFloat(count) * 5)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 2, y: 8)
        .accessibilityHidden(true)
    }
}

struct FeltSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 150)
            .fill(
                RadialGradient(
                    colors: [Color(red: 0.06, green: 0.29, blue: 0.23), Color(red: 0.025, green: 0.13, blue: 0.115)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 310
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 150)
                    .strokeBorder(PokerTheme.gold.opacity(0.17), lineWidth: 1)
                    .padding(9)
                RoundedRectangle(cornerRadius: 150)
                    .strokeBorder(.black.opacity(0.18), lineWidth: 7)
            }
            .shadow(color: .black.opacity(0.28), radius: 25, y: 15)
    }
}

struct PrimaryAction: View {
    let title: String
    var symbol = "arrow.right"
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView().tint(PokerTheme.background)
                } else {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(PokerTheme.mint)
        .foregroundStyle(PokerTheme.background)
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Trwa ładowanie" : "")
    }
}

// Adapted from AllegroShare's AnimatedButtonStyle; native glass keeps its own interaction.
struct PokerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SessionProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...total, id: \.self) { hand in
                Capsule()
                    .fill(hand <= current ? PokerTheme.mint : .white.opacity(0.12))
                    .frame(width: hand == current ? 24 : 12, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rozdanie \(current) z \(total)")
    }
}

extension PokerAction {
    var displayName: String { self == .call ? "CALL" : "FOLD" }
    var polishName: String { self == .call ? "Sprawdzenie" : "Pas" }
}

extension HandAction {
    var displayName: String { rawValue.uppercased() }

    var polishName: String {
        switch self {
        case .fold: "Pas"
        case .check: "Czekanie"
        case .call: "Sprawdzenie"
        case .bet: "Zakład"
        case .raise: "Podbicie"
        }
    }
}

extension HandStreet {
    var displayName: String { rawValue.uppercased() }
}
