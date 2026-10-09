import SwiftUI

extension View {
    func pokerDeal(index: Int, trigger: String, animated: Bool = true) -> some View {
        modifier(CardDealModifier(index: index, trigger: trigger, animated: animated))
    }
}

private struct CardDealModifier: ViewModifier {
    let index: Int
    let trigger: String
    let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDealt = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isDealt || reduceMotion || !animated ? 1 : 0.55)
            .rotation3DEffect(
                .degrees(isDealt || reduceMotion || !animated ? 0 : 105),
                axis: (x: 0.25, y: 1, z: 0),
                perspective: 0.5
            )
            .rotationEffect(.degrees(isDealt || reduceMotion || !animated ? 0 : Double(index.isMultiple(of: 2) ? -28 : 28)))
            .offset(
                x: isDealt || reduceMotion || !animated ? 0 : CGFloat(2 - index) * 22,
                y: isDealt || reduceMotion || !animated ? 0 : -220
            )
            .opacity(isDealt || reduceMotion || !animated ? 1 : 0)
            .task(id: trigger) {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { isDealt = reduceMotion || !animated }
                guard !reduceMotion, animated else { return }
                do {
                    try await Task.sleep(for: .milliseconds(30 + max(0, index) * 70))
                    try Task.checkCancellation()
                    withAnimation(.spring(duration: 0.7, bounce: 0.2)) { isDealt = true }
                } catch {
                    // A new hand or leaving the table cancels its pending card deal.
                }
            }
    }
}

/// Place over the pot. Positive triggers play on arrival and whenever they change.
struct ChipPotBurst: View {
    let trigger: Int

    var body: some View {
        PokerParticleBurst(trigger: trigger, style: .chips)
    }
}

/// A short celebration for decision quality, independent of the simulated runout.
struct PokerCelebrationView: View {
    enum Intensity {
        case hand
        case session
    }

    let trigger: Int
    var intensity: Intensity = .hand

    var body: some View {
        PokerParticleBurst(trigger: trigger, style: intensity == .session ? .session : .hand)
    }
}

private enum ParticleStyle {
    case chips
    case hand
    case session

    var duration: Double {
        switch self {
        case .chips: 1.1
        case .hand: 1.5
        case .session: 2.1
        }
    }

    var count: Int {
        switch self {
        case .chips: 16
        case .hand: 52
        case .session: 110
        }
    }
}

private struct PokerParticleBurst: View {
    let trigger: Int
    let style: ParticleStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?

    var body: some View {
        ZStack {
            if reduceMotion {
                Circle()
                    .fill(PokerTheme.gold.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                    .opacity(startedAt == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: startedAt)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: startedAt == nil)) { timeline in
                    Canvas { context, size in
                        guard let startedAt else { return }
                        let elapsed = timeline.date.timeIntervalSince(startedAt)
                        guard elapsed >= 0, elapsed < style.duration else { return }
                        drawParticles(context: context, size: size, elapsed: elapsed)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: trigger) {
            startedAt = nil
            guard trigger > 0 else { return }
            startedAt = .now
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.45 : style.duration))
                try Task.checkCancellation()
                startedAt = nil
            } catch {
                // The replacement task owns the next burst; do not clear its state.
            }
        }
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, elapsed: Double) {
        let colors = [PokerTheme.gold, PokerTheme.mint, PokerTheme.ivory]
        for index in 0..<style.count {
            let seed = Double(index)
            let delay = Double(index % 7) * 0.017
            let age = max(0, elapsed - delay)
            guard elapsed >= delay else { continue }
            let progress = min(age / (style.duration - 0.12), 1)
            let variation = Double((index * 37) % 101) / 100
            let color = colors[index % colors.count]
            let position = position(index: index, variation: variation, age: age, size: size)
            let radius = style == .chips ? 5 + variation * 4 : 2.5 + variation * 3.5
            var particle = context
            particle.opacity = min(age * 18, 1) * max(0, 1 - pow(progress, 3))
            particle.translateBy(x: position.x, y: position.y)
            particle.rotate(by: .radians(seed + age * (4 + variation * 8)))

            if style == .chips {
                let chip = Path(ellipseIn: CGRect(x: -radius, y: -radius * 0.7, width: radius * 2, height: radius * 1.4))
                particle.fill(chip, with: .color(color))
                particle.stroke(chip, with: .color(PokerTheme.ivory.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                particle.stroke(
                    Path(ellipseIn: CGRect(x: -radius * 0.5, y: -radius * 0.35, width: radius, height: radius * 0.7)),
                    with: .color(.black.opacity(0.2)),
                    lineWidth: 1
                )
            } else if index.isMultiple(of: 4) {
                particle.fill(sparkle(radius: radius * 1.5), with: .color(color))
            } else {
                let flutter = 0.25 + abs(cos(age * 9 + seed)) * 0.75
                particle.scaleBy(x: flutter, y: 1)
                particle.fill(
                    Path(roundedRect: CGRect(x: -radius, y: -radius * 0.45, width: radius * 2, height: radius * 0.9), cornerRadius: 1),
                    with: .color(color)
                )
            }
        }
    }

    private func position(index: Int, variation: Double, age: Double, size: CGSize) -> CGPoint {
        if style == .chips {
            let angle = Double(index) * .pi * 2 / Double(style.count)
            let distance = (45 + variation * 50) * sin(min(age / style.duration, 1) * .pi)
            return CGPoint(
                x: size.width * 0.5 + cos(angle) * distance,
                y: size.height * 0.5 + sin(angle) * distance * 0.5 - sin(age * .pi) * 48
            )
        }

        let fromLeft = index.isMultiple(of: 2)
        let originX = style == .session ? size.width * (fromLeft ? 0.08 : 0.92) : size.width * 0.5
        let originY = size.height * (style == .session ? 0.72 : 0.32)
        let horizontalSpeed = style == .session
            ? (fromLeft ? 1.0 : -1.0) * (70 + variation * 160)
            : (Double((index * 17) % 100) / 50 - 1) * 180
        let verticalSpeed = style == .session ? -250 - variation * 220 : -100 - variation * 140
        return CGPoint(
            x: originX + horizontalSpeed * age,
            y: originY + verticalSpeed * age + 180 * age * age
        )
    }

    private func sparkle(radius: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: -radius))
            path.addLine(to: CGPoint(x: radius * 0.25, y: -radius * 0.25))
            path.addLine(to: CGPoint(x: radius, y: 0))
            path.addLine(to: CGPoint(x: radius * 0.25, y: radius * 0.25))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addLine(to: CGPoint(x: -radius * 0.25, y: radius * 0.25))
            path.addLine(to: CGPoint(x: -radius, y: 0))
            path.addLine(to: CGPoint(x: -radius * 0.25, y: -radius * 0.25))
            path.closeSubpath()
        }
    }
}
