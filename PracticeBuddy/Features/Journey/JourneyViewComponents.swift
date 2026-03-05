import SwiftUI
import Combine

struct LadderActionUser: Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
}

struct PBRewardConfettiOverlay: View {
    let styleID: String
    let token: Int

    @State private var animate = false

    private var colors: [Color] {
        if styleID == "reward_confetti_spark" {
            return [.yellow, .orange, .mint, .cyan, .pink]
        }
        return [.blue, .green, .orange, .purple, .red]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<16, id: \.self) { index in
                    let xSeed = Double((index * 37) % 100) / 100.0
                    let ySeed = Double((index * 53) % 100) / 100.0
                    Circle()
                        .fill(colors[index % colors.count].opacity(0.9))
                        .frame(width: 7, height: 7)
                        .position(
                            x: animate ? proxy.size.width * xSeed : proxy.size.width * 0.5,
                            y: animate ? proxy.size.height * (0.16 + ySeed * 0.42) : proxy.size.height * 0.1
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: 0.95).delay(Double(index) * 0.01),
                            value: animate
                        )
                }
            }
        }
        .onChange(of: token) { _, _ in
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .onAppear {
            animate = true
        }
        .accessibilityHidden(true)
    }
}

struct PBDuelFinisherOverlay: View {
    let styleID: String
    let token: Int
    @Environment(\.pbTypography) private var type

    @State private var animate = false

    private var highlight: Color {
        if styleID == "reward_duel_finisher_fx_resonance" {
            return .mint
        }
        return .blue
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .stroke(highlight.opacity(0.55), lineWidth: 2)
                    .frame(width: animate ? proxy.size.width * 0.72 : 24, height: animate ? proxy.size.width * 0.72 : 24)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.05), value: animate)

                Circle()
                    .stroke(highlight.opacity(0.36), lineWidth: 2)
                    .frame(width: animate ? proxy.size.width * 0.52 : 20, height: animate ? proxy.size.width * 0.52 : 20)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.0).delay(0.07), value: animate)

                VStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(highlight)
                    Text("Duel Finalized")
                        .font(type.button)
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(animate ? 1.0 : 0.82)
                .opacity(animate ? 0 : 1)
                .animation(.easeOut(duration: 1.0), value: animate)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .onChange(of: token) { _, _ in
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}
