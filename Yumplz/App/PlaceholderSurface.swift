import SwiftUI

/// Visual placeholder for tabs that haven't been fully implemented yet.
/// Uses the glassmorphic card style so even in-progress screens feel polished.
struct PlaceholderSurface: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let progress: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 48)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 104, height: 104)
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.mkHeading)

                Text(subtitle)
                    .font(.mkBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text(progress)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ZStack {
        WarmGlassBackground()
        PlaceholderSurface(
            title: "Discover",
            subtitle: "Daily hero · editorial rails · browse by cuisine.",
            systemImage: "sparkles",
            progress: "Q13 — pending Content Library ingest"
        )
    }
}
