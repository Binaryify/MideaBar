// 生成 MideaBar 的 App 图标：swift make-icon.swift <输出 1024px PNG 路径>
// 图标即代码：改这里再跑 `make icon` 即可重新生成 AppIcon.icns。
import AppKit
import SwiftUI

let cool = Color(red: 0.55, green: 0.82, blue: 1.0)

struct AppIcon: View {
    private let plate = RoundedRectangle(cornerRadius: 185, style: .continuous)

    var body: some View {
        ZStack {
            // macOS 图标网格：1024 画布内 824 的圆角矩形，四周留 100
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.19, blue: 0.23),
                                        Color(red: 0.05, green: 0.06, blue: 0.08)],
                               startPoint: .top, endPoint: .bottom)
                // 冷气光晕（裁剪在底板内）
                Ellipse()
                    .fill(cool.opacity(0.32))
                    .frame(width: 560, height: 320)
                    .blur(radius: 90)
                    .offset(y: 190)
                Airflow()
                    .frame(width: 620, height: 340)
                    .offset(y: 160)
                ACUnit()
                    .frame(width: 600, height: 190)
                    .offset(y: -150)
            }
            .frame(width: 824, height: 824)
            .clipShape(plate)
            .overlay(
                plate.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 3)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct ACUnit: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.84)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.55), radius: 26, y: 16)
            // 顶部高光
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 2)
            // 出风口
            UnevenRoundedRectangle(bottomLeadingRadius: 44, bottomTrailingRadius: 44, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.18)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 44)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color(white: 0.93))
                        .frame(height: 9)
                        .padding(.horizontal, 30)
                        .offset(y: 3)
                }
            // 指示灯
            Circle()
                .fill(cool)
                .frame(width: 16, height: 16)
                .shadow(color: cool, radius: 12)
                .offset(x: 236, y: -112)
        }
    }
}

/// 从出风口向下展开的柔和风带。
struct Airflow: View {
    var body: some View {
        Canvas { ctx, size in
            let n = 7
            for i in 0..<n {
                let f = (Double(i) + 0.5) / Double(n) - 0.5 // -0.5…0.5
                var p = Path()
                // 左右对称地向外展开，越靠边越弯
                let top = CGPoint(x: size.width / 2 + f * 440, y: 0)
                let bottom = CGPoint(x: size.width / 2 + f * 640, y: size.height)
                let ctrl = CGPoint(x: size.width / 2 + f * 420, y: size.height * 0.6)
                p.move(to: top)
                p.addQuadCurve(to: bottom, control: ctrl)
                let g = Gradient(stops: [
                    .init(color: cool.opacity(0.95), location: 0),
                    .init(color: cool.opacity(0.55), location: 0.45),
                    .init(color: cool.opacity(0), location: 1),
                ])
                ctx.stroke(p, with: .linearGradient(g, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)),
                           style: StrokeStyle(lineWidth: 18, lineCap: .round))
            }
        }
        .blur(radius: 5)
    }
}

@MainActor
func render(to path: String) throws {
    let renderer = ImageRenderer(content: AppIcon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { throw NSError(domain: "icon", code: 1) }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "icon", code: 2) }
    try png.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
try MainActor.assumeIsolated { try render(to: out) }
print("✓ \(out)")
