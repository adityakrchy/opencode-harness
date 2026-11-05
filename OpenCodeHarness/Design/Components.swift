import SwiftUI
import AppKit

// MARK: - Brand

struct BrandMark: View {
    var size: CGFloat = 30
    var glow: Bool = false

    var body: some View {
        ZStack {
            if glow {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color.ocAccent.opacity(0.45))
                    .blur(radius: size * 0.45)
                    .scaleEffect(1.08)
            }
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.18, blue: 0.23),
                            Color(red: 0.045, green: 0.05, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.7)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.ocAccent)
                        .frame(width: size * 0.16, height: size * 0.16)
                        .blur(radius: size * 0.06)
                        .offset(x: -size * 0.16, y: size * 0.16)
                }
            HStack(spacing: size * 0.055) {
                Image(systemName: "chevron.right")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                RoundedRectangle(cornerRadius: size * 0.035)
                    .frame(width: size * 0.27, height: size * 0.085)
                    .offset(y: size * 0.14)
            }
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.28), radius: glow ? 12 : 3, y: glow ? 5 : 1)
    }
}

struct BrandWordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            BrandMark(size: 26, glow: true)
            VStack(alignment: .leading, spacing: -1) {
                Text("OPENCODE")
                    .font(.ocRounded(12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.ocTextPrimary)
                Text("H A R N E S S")
                    .font(.ocMono(8, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
            }
        }
    }
}

// MARK: - Buttons

struct IconButton: View {
    var systemImage: String
    var help: String = ""
    var size: CGFloat = 28
    var tint: Color = .ocTextSecondary
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(hovering ? Color.ocTextPrimary : tint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(hovering ? Color.ocHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(Motion.quick) { hovering = value }
        }
        .help(help)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .ocAccent
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(configuration.isPressed ? 0.78 : 1), tint.opacity(configuration.isPressed ? 0.62 : 0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                    }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .shadow(color: tint.opacity(0.22), radius: configuration.isPressed ? 2 : 8, y: 3)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.ocTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Color.ocHover : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

struct HoverScale: ViewModifier {
    var scale: CGFloat = 1.012
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Surfaces

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.ocSurface.opacity(0.55))
                    }
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.ocBorder, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

struct CardSurface: ViewModifier {
    var radius: CGFloat = 12
    var fill: Color = .ocSurface

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.ocBorder, lineWidth: 0.7)
            }
    }
}

extension View {
    func cardSurface(radius: CGFloat = 12, fill: Color = .ocSurface) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }

    func ocTooltip(_ text: String) -> some View {
        help(text)
    }
}

// MARK: - Labels & tags

struct SectionLabel: View {
    var text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.ocMono(9.5, weight: .semibold))
                .tracking(1.15)
                .foregroundStyle(Color.ocTextTertiary)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.ocMono(9, weight: .medium))
                    .foregroundStyle(Color.ocTextTertiary)
            }
        }
    }
}

struct StatusDot: View {
    var color: Color
    var pulsing: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.5 : 0.5)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.65), radius: 3)
        }
        .frame(width: 12, height: 12)
        .onAppear { pulse = true }
    }
}

struct Tag: View {
    var text: String
    var icon: String?
    var tint: Color = .ocTextSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .semibold))
            }
            Text(text)
                .font(.ocMono(9.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
        )
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.15), lineWidth: 0.5)
        }
    }
}

struct KeyCap: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.ocMono(10, weight: .medium))
            .foregroundStyle(Color.ocTextTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.ocHover)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.ocBorder, lineWidth: 0.5)
            }
    }
}

// MARK: - Animated elements

struct StreamingCaret: View {
    @State private var visible = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.ocAccent)
            .frame(width: 2.5, height: 15)
            .opacity(visible ? 1 : 0.15)
            .animation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}

struct ShimmerText: View {
    var text: String
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.ocTextSecondary)
            .overlay {
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 120)
                .mask(Text(text).font(.system(size: 11, weight: .medium)))
                .blendMode(.screen)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 4
    var size: CGFloat = 28
    var tint: Color = .ocAccent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ocHover, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.45), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(Motion.smooth, value: progress)
        }
        .frame(width: size, height: size)
    }
}

struct Spinner: View {
    var size: CGFloat = 14
    var tint: Color = .ocAccent
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.82)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - Empty states

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.ocAccent.opacity(0.08))
                    .frame(width: 66, height: 66)
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(Color.ocAccent)
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.ocRounded(17, weight: .semibold))
                    .foregroundStyle(Color.ocTextPrimary)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(30)
    }
}

// MARK: - Toast

struct ToastView: View {
    var toast: ToastMessage
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(toast.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
        }
        .foregroundStyle(Color.ocTextPrimary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().fill(Color.ocSurface.opacity(0.75)))
        )
        .overlay {
            Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    }
}

// MARK: - Formatters

enum Format {
    static func tokens(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return String(Int(value))
    }

    static func cost(_ value: Double) -> String {
        if value <= 0 { return "$0.00" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        return String(format: "$%.2f", value)
    }

    static func duration(_ value: Double) -> String {
        if value < 1 { return String(format: "%.0fms", value * 1000) }
        if value < 60 { return String(format: "%.1fs", value) }
        return String(format: "%dm %02ds", Int(value) / 60, Int(value) % 60)
    }

    static func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Utility

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func readingWidth(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self, perform: onChange)
    }
}

struct Chevron: View {
    var open: Bool
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(open ? 90 : 0))
            .foregroundStyle(Color.ocTextTertiary)
            .animation(Motion.quick, value: open)
    }
}
