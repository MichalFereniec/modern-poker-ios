import SwiftUI

struct HomeView: View {
    let start: () -> Void
    let showHelp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 44
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 7) {
                        Circle().fill(PokerTheme.mint).frame(width: 5, height: 5)
                        Eyebrow(text: "TWÓJ OSOBISTY TRENER", color: PokerTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: -2) {
                        Text("Mniej intuicji.")
                            .foregroundStyle(PokerTheme.ivory)
                        Text("Więcej przewagi.")
                            .foregroundStyle(PokerTheme.gold)
                    }
                    .font(.system(size: min(titleSize, 64), weight: .regular, design: .serif))
                    .tracking(-1.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text("Dobre decyzje zostają z tobą.\nNawet kiedy karty nie sprzyjają.")
                        .font(.subheadline)
                        .foregroundStyle(PokerTheme.muted)
                        .lineSpacing(4)
                }

                HomeTableArt(appeared: appeared)
                    .frame(height: 245)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Button(action: showHelp) {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 23, weight: .light))
                            .foregroundStyle(PokerTheme.gold)
                            .frame(width: 38)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Jedna ręka. Cała historia.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PokerTheme.ivory)
                            Text("Od flopa do showdownu. Graj i poznawaj swoje szanse.")
                                .font(.caption)
                                .foregroundStyle(PokerTheme.muted)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PokerTheme.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PokerTheme.surface, in: .rect(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    }
                }
                .buttonStyle(PokerPressStyle())
                .accessibilityIdentifier("home.help")
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                PrimaryAction(title: "Zajmij miejsce", action: start)
                    .accessibilityIdentifier("home.start")
                if dynamicTypeSize.isAccessibilitySize {
                    Text("5 pełnych rozdań w sesji")
                        .font(.caption)
                        .foregroundStyle(PokerTheme.muted)
                } else {
                    HStack(spacing: 8) {
                        Text("5 PEŁNYCH ROZDAŃ")
                        Circle().frame(width: 3, height: 3).accessibilityHidden(true)
                        Text("OD FLOPA DO SHOWDOWNU")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(PokerTheme.muted)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background {
                LinearGradient(colors: [PokerTheme.background.opacity(0), PokerTheme.background, PokerTheme.background], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

private struct HomeTableArt: View {
    let appeared: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(PokerTheme.emerald.opacity(0.5))
                .frame(width: 280, height: 130)
                .blur(radius: 35)
                .offset(y: 45)
            Ellipse()
                .strokeBorder(PokerTheme.gold.opacity(0.16), lineWidth: 1)
                .frame(width: 335, height: 165)
                .rotationEffect(.degrees(-14))
                .offset(y: 42)
            Ellipse()
                .strokeBorder(PokerTheme.gold.opacity(0.08), lineWidth: 1)
                .frame(width: 370, height: 188)
                .rotationEffect(.degrees(-14))
                .offset(y: 42)
            PlayingCardView(card: PokerCard(rank: 13, suit: .hearts), width: 123)
                .rotationEffect(.degrees(appeared ? 15 : 4))
                .offset(x: appeared ? 47 : 12, y: 6)
                .pokerDeal(index: 1, trigger: "home-king")
            PlayingCardView(card: PokerCard(rank: 14, suit: .spades), width: 123)
                .rotationEffect(.degrees(appeared ? -13 : -4))
                .offset(x: appeared ? -44 : -10, y: -12)
                .pokerDeal(index: 2, trigger: "home-ace")
            ChipStack(color: PokerTheme.gold, count: 6, width: 55)
                .rotationEffect(.degrees(-13))
                .offset(x: -111, y: 93)
            ChipStack(color: PokerTheme.emerald, count: 4, width: 48)
                .offset(x: -68, y: 109)
            ChipStack(color: PokerTheme.gold, count: 3, width: 41)
                .rotationEffect(.degrees(12))
                .offset(x: 124, y: 72)
            Image(systemName: "sparkle")
                .font(.system(size: 17, weight: .ultraLight))
                .foregroundStyle(PokerTheme.gold.opacity(0.8))
                .offset(x: 133, y: -95)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .ultraLight))
                .foregroundStyle(PokerTheme.gold.opacity(0.5))
                .offset(x: -135, y: -82)
            Text("PLAY WITH INSIGHT")
                .font(.system(size: 8, weight: .medium))
                .tracking(3.5)
                .foregroundStyle(PokerTheme.gold.opacity(0.65))
                .rotationEffect(.degrees(-90))
                .offset(x: 156, y: -12)
            ChipPotBurst(trigger: appeared ? 1 : 0)
                .frame(width: 245, height: 180)
                .offset(y: 40)
        }
        .scaleEffect(appeared ? 1 : 0.93)
    }
}
