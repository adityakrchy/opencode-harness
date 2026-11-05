import AppKit
import SwiftUI

// MARK: - Palette

extension Color {
    static let ocAccent = Color(red: 1.0, green: 0.40, blue: 0.15)
    static let ocAccentSoft = Color(red: 1.0, green: 0.58, blue: 0.29)
    static let ocTeal = Color(red: 0.22, green: 0.79, blue: 0.69)
    static let ocViolet = Color(red: 0.62, green: 0.52, blue: 0.96)
    static let ocSuccess = Color(red: 0.25, green: 0.82, blue: 0.57)
    static let ocWarning = Color(red: 1.0, green: 0.73, blue: 0.28)
    static let ocDanger = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let ocInfo = Color(red: 0.35, green: 0.68, blue: 1.0)

    static let ocCanvas = adaptive(
        light: NSColor(calibratedRed: 0.947, green: 0.941, blue: 0.922, alpha: 1),
        dark: NSColor(calibratedRed: 0.038, green: 0.043, blue: 0.055, alpha: 1)
    )
    static let ocSidebar = adaptive(
        light: NSColor(calibratedRed: 0.914, green: 0.906, blue: 0.882, alpha: 1),
        dark: NSColor(calibratedRed: 0.052, green: 0.059, blue: 0.075, alpha: 1)
    )
    static let ocSurface = adaptive(
        light: NSColor(calibratedRed: 0.996, green: 0.996, blue: 0.988, alpha: 1),
        dark: NSColor(calibratedRed: 0.071, green: 0.082, blue: 0.105, alpha: 1)
    )
    static let ocSurfaceRaised = adaptive(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.996, alpha: 1),
        dark: NSColor(calibratedRed: 0.094, green: 0.108, blue: 0.138, alpha: 1)
    )
    static let ocSurfaceSunken = adaptive(
        light: NSColor(calibratedRed: 0.918, green: 0.914, blue: 0.898, alpha: 1),
        dark: NSColor(calibratedRed: 0.047, green: 0.054, blue: 0.069, alpha: 1)
    )
    static let ocHover = adaptive(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    static let ocBorder = adaptive(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.085)
    )
    static let ocBorderStrong = adaptive(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.white.withAlphaComponent(0.15)
    )
    static let ocTextPrimary = adaptive(
        light: NSColor(calibratedRed: 0.075, green: 0.081, blue: 0.098, alpha: 1),
        dark: NSColor(calibratedRed: 0.950, green: 0.956, blue: 0.968, alpha: 1)
    )
    static let ocTextSecondary = adaptive(
        light: NSColor(calibratedRed: 0.35, green: 0.37, blue: 0.42, alpha: 1),
        dark: NSColor(calibratedRed: 0.63, green: 0.66, blue: 0.72, alpha: 1)
    )
    static let ocTextTertiary = adaptive(
        light: NSColor(calibratedRed: 0.51, green: 0.53, blue: 0.57, alpha: 1),
        dark: NSColor(calibratedRed: 0.44, green: 0.47, blue: 0.53, alpha: 1)
    )
    static let ocCodeBackground = adaptive(
        light: NSColor(calibratedRed: 0.945, green: 0.941, blue: 0.925, alpha: 1),
        dark: NSColor(calibratedRed: 0.045, green: 0.052, blue: 0.067, alpha: 1)
    )
    static let ocCodeGutter = adaptive(
        light: NSColor(calibratedRed: 0.90, green: 0.895, blue: 0.875, alpha: 1),
        dark: NSColor(calibratedRed: 0.06, green: 0.068, blue: 0.086, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

// MARK: - Typography

extension Font {
    static func ocRounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func ocBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func ocMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Motion

enum Motion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let gentle = Animation.easeInOut(duration: 0.24)
    static let quick = Animation.easeOut(duration: 0.15)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.72)
}

// MARK: - Backgrounds

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Color.ocCanvas
            GeometryReader { proxy in
                RadialGradient(
                    colors: [
                        Color.ocAccent.opacity(colorScheme == .dark ? 0.10 : 0.06),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.8
                )
                RadialGradient(
                    colors: [
                        Color.ocTeal.opacity(colorScheme == .dark ? 0.045 : 0.035),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.7
                )
            }
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.08))
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
