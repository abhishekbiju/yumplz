import SwiftUI
import UIKit

// MARK: - Color tokens

extension Color {
    /// Light lavender (light mode) / deep purple (dark mode).
    static let mkBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.08, blue: 0.15, alpha: 1)
            : UIColor(red: 0.97, green: 0.96, blue: 1.00, alpha: 1)
    })

    /// Deeper lavender (light) / elevated purple surface (dark).
    static let mkSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.11, blue: 0.20, alpha: 1)
            : UIColor(red: 0.93, green: 0.91, blue: 0.99, alpha: 1)
    })

    /// Teal-green for secondary accents (dietary tags, "healthy" badges, etc.)
    static let mkGreen = Color(red: 0.25, green: 0.42, blue: 0.42)

    /// Medium purple secondary accent.
    static let mkPurple = Color(red: 0.48, green: 0.36, blue: 0.66)

    /// Soft lilac for tags, chips, and subtle highlights.
    static let mkLilac = Color(red: 0.72, green: 0.61, blue: 0.90)

    /// Adaptive stroke tint for glass cards.
    static let mkGlassTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.18)
            : UIColor.white.withAlphaComponent(0.85)
    })
}

// MARK: - Glass card modifier

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 20
    var tint: Color?

    private var resolvedTint: Color {
        tint ?? .mkGlassTint
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(resolvedTint.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.35 : 0.07),
                radius: 18,
                x: 0,
                y: 6
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - Glass gradient background

/// Full-screen purple gradient with blurred accent blobs — the backdrop
/// used behind every top-level view. Adapts to light and dark mode.
struct WarmGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.mkBackground, .mkSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.35 : 0.22))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -90, y: -130)

            Circle()
                .fill(Color.mkLilac.opacity(colorScheme == .dark ? 0.28 : 0.20))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: 110, y: 280)

            Circle()
                .fill(
                    Color(
                        red: colorScheme == .dark ? 0.55 : 0.85,
                        green: colorScheme == .dark ? 0.35 : 0.65,
                        blue: colorScheme == .dark ? 0.70 : 0.90
                    )
                    .opacity(colorScheme == .dark ? 0.22 : 0.15)
                )
                .frame(width: 180, height: 180)
                .blur(radius: 60)
                .offset(x: 130, y: -40)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Spring presets

extension Animation {
    /// Snappy spring — button taps, card appearances.
    static let mkSnap = Animation.spring(response: 0.35, dampingFraction: 0.72)
    /// Gentle spring — sheet presentations, page transitions.
    static let mkGentle = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Bouncy spring — FAB, badge pop-ins.
    static let mkBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
}

// MARK: - Typography helpers

extension Font {
    /// Large display text (Discover hero title, etc.)
    static let mkDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    /// Section headings inside lists / cards.
    static let mkHeading = Font.system(size: 20, weight: .semibold, design: .rounded)
    /// Body text.
    static let mkBody = Font.system(size: 16, weight: .regular)
    /// Captions, timestamps, meta info.
    static let mkCaption = Font.system(size: 12, weight: .medium)
}

// MARK: - Gradient FAB button style

struct GradientFABStyle: ButtonStyle {
    var size: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(
                color: Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.45),
                radius: configuration.isPressed ? 6 : 14,
                x: 0,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.mkSnap, value: configuration.isPressed)
    }
}

// MARK: - Tag chip

struct TagChip: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.mkCaption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
                    .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
            )
            .foregroundStyle(color)
    }
}

// MARK: - Purple screen + styled lists

/// Backdrop used behind tab roots and settings screens.
struct PurpleScreenContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            WarmGlassBackground()
            content()
        }
    }
}

/// Hides the system list background and uses glass rows on the purple gradient.
struct MKInsetListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(Color.primary.opacity(0.12))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

extension View {
    func mkInsetListStyle() -> some View {
        modifier(MKInsetListStyle())
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double  // 0–1
    var lineWidth: CGFloat = 4
    var color: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.mkGentle, value: progress)
        }
    }
}
