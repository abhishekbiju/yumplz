import SwiftUI

/// Shown the first time the user triggers an import action when the LLM model
/// hasn't been downloaded yet. Presents a clear explanation of the one-time
/// download size and an explicit "Download now" CTA.
///
/// Once the download completes, it calls `onReady()` so the caller can proceed.
struct ModelDownloadGateView: View {
    var downloads: ModelDownloadManager
    var onReady: () -> Void

    @State private var isDownloading = false
    @State private var errorMessage: String?

    private var llmState: DownloadState { downloads.state(for: .llama3_2_3b) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 28)

            Text("One-Time AI Download")
                .font(.mkDisplay)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text("MealKit uses a **local AI model** to read and understand recipes — no internet connection needed after this download.")
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            // Download info chips
            HStack(spacing: 12) {
                InfoChip(icon: "arrow.down.circle", label: "~2.0 GB")
                InfoChip(icon: "wifi", label: "Wi-Fi recommended")
                InfoChip(icon: "lock.fill", label: "Stays on device")
            }
            .padding(.bottom, 36)

            // Progress or CTA
            if case .downloading(let p) = llmState {
                VStack(spacing: 16) {
                    ProgressView(value: p)
                        .tint(.accentColor)
                        .padding(.horizontal, 40)

                    Text(progressLabel(p))
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)

                    Button("Cancel") {
                        downloads.cancelDownload(for: .llama3_2_3b)
                        isDownloading = false
                    }
                    .foregroundStyle(.secondary)
                }
            } else if case .ready = llmState {
                // Should not normally be visible — gate dismissed immediately.
                ProgressView()
                    .onAppear { onReady() }
            } else {
                Button {
                    isDownloading = true
                    errorMessage = nil
                    Task {
                        do {
                            try await downloads.ensureReady(.llama3_2_3b)
                        } catch {
                            isDownloading = false
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Download AI Model", systemImage: "arrow.down.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
                .disabled(isDownloading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.mkCaption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }
            }

            Spacer()
        }
        .onChange(of: downloads.state(for: .llama3_2_3b).isReady) { _, ready in
            if ready { onReady() }
        }
    }

    // MARK: Helpers

    private func progressLabel(_ progress: Double) -> String {
        let downloadedMB = Int(Double(LocalModel.llama3_2_3b.approximateBytes) * progress / 1_000_000)
        let totalMB = Int(LocalModel.llama3_2_3b.approximateBytes / 1_000_000)
        return "\(downloadedMB) MB / \(totalMB) MB"
    }
}

// MARK: - Info chip

private struct InfoChip: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.mkCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 16)
    }
}

#Preview {
    ModelDownloadGateView(downloads: ModelDownloadManager(), onReady: {})
        .background(WarmGlassBackground())
}
