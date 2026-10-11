import SwiftUI

/// 空调室内机插画；开机时下方持续飘出风流。
struct ACUnitView: View {
    let isOn: Bool
    let tint: Color

    var body: some View {
        VStack(spacing: -6) {
            unitBody
                .frame(width: 150, height: 46)
                .zIndex(1)
            AirflowView(tint: tint, isOn: isOn)
                .frame(width: 128, height: 74)
                .opacity(isOn ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: isOn)
        }
        .frame(height: 116, alignment: .top)
    }

    private var unitBody: some View {
        ZStack(alignment: .bottom) {
            // 机身
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.86)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            // 出风口
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.30)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 10)
                .overlay(alignment: .top) {
                    // 导风板：开机时向下打开
                    Rectangle()
                        .fill(Color(white: 0.92))
                        .frame(height: isOn ? 2 : 5)
                        .padding(.horizontal, 6)
                }
            // 指示灯
            Circle()
                .fill(isOn ? tint : Color(white: 0.7))
                .frame(width: 4, height: 4)
                .shadow(color: isOn ? tint : .clear, radius: 3)
                .offset(x: 58, y: -16)
        }
        .animation(.easeInOut(duration: 0.4), value: isOn)
    }
}

/// 向下流动、逐渐消散的半透明风线。
struct AirflowView: View {
    let tint: Color
    let isOn: Bool
    private let streaks = 24

    var body: some View {
        TimelineView(.animation(paused: !isOn)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<streaks {
                    let seed = Double(i) * 1.618
                    let fx = (Double(i) + 0.5) / Double(streaks)
                    let speed = 0.55 + 0.25 * sin(seed * 3.1)
                    let phase = (t * speed + seed).truncatingRemainder(dividingBy: 1)

                    var path = Path()
                    let segments = 12
                    for s in 0...segments {
                        let p = Double(s) / Double(segments)
                        let y = p * size.height
                        // 越往下越向外扩散，并带一点摆动
                        let spread = (fx - 0.5) * size.width * (0.8 + 0.5 * p)
                        let wave = sin(p * 5 + t * 2.2 + seed) * 2.5 * p
                        let pt = CGPoint(x: size.width / 2 + spread + wave, y: y)
                        s == 0 ? path.move(to: pt) : path.addLine(to: pt)
                    }
                    // 一段亮带沿风线向下移动
                    let gradient = Gradient(stops: [
                        .init(color: tint.opacity(0), location: 0),
                        .init(color: tint.opacity(0), location: max(0, phase - 0.35)),
                        .init(color: tint.opacity(0.26), location: phase),
                        .init(color: tint.opacity(0), location: min(1, phase + 0.05)),
                        .init(color: tint.opacity(0), location: 1),
                    ])
                    ctx.stroke(path,
                               with: .linearGradient(gradient, startPoint: .zero,
                                                     endPoint: CGPoint(x: 0, y: size.height)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            .mask(LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom))
            .blur(radius: 1.2)
        }
    }
}
