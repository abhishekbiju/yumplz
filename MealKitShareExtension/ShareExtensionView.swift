import SwiftUI
import UniformTypeIdentifiers

// MARK: - ShareExtensionView

struct ShareExtensionView: View {
    let itemProviders: [NSItemProvider]
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var detectedDescription: String = "Detecting content…"
    @State private var isQueuing = false
    @State private var isQueued = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("MealKit")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            VStack(spacing: 20) {
                // Content description
                Label(detectedDescription, systemImage: contentIcon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // State-dependent action area
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else if isQueued {
                    VStack(spacing: 8) {
                        Label("Queued for import", systemImage: "checkmark.circle.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.green)
                        Text("Open MealKit to review and save the recipe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button {
                        Task { await queueImport() }
                    } label: {
                        Group {
                            if isQueuing {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Processing…")
                                }
                            } else {
                                Label("Import Recipe", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isQueuing)
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 24)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isQueued)
        }
        .background(Color(.systemBackground))
        .task { await detectContent() }
    }

    // MARK: - Content detection

    private var contentIcon: String {
        if detectedDescription.contains("video") || detectedDescription.contains("Video") {
            return "play.rectangle.fill"
        } else if detectedDescription.contains("Detecting") {
            return "ellipsis.circle"
        } else {
            return "link"
        }
    }

    private func detectContent() async {
        for provider in itemProviders {
            // Prefer URL
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    let display = url.host ?? url.absoluteString
                    detectedDescription = display
                    return
                }
            }
            // Plain text URL fallback
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   text.hasPrefix("http") {
                    detectedDescription = URL(string: text)?.host ?? text
                    return
                }
            }
            // Video file
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                detectedDescription = "Video file"
                return
            }
        }
        detectedDescription = "Recipe content"
    }

    // MARK: - Queue import

    private func queueImport() async {
        isQueuing = true
        defer { isQueuing = false }

        for provider in itemProviders {
            // Try URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    let item = PendingImportItem(kind: .url, value: url.absoluteString)
                    PendingImportStore.append(item)
                    withAnimation { isQueued = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onComplete() }
                    return
                }
            }

            // Plain text URL fallback (some apps share as text)
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   URL(string: text)?.scheme?.hasPrefix("http") == true {
                    let item = PendingImportItem(kind: .url, value: text)
                    PendingImportStore.append(item)
                    withAnimation { isQueued = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onComplete() }
                    return
                }
            }

            // Video file — copy into shared container
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                do {
                    let fileURL = try await provider.loadItem(forTypeIdentifier: UTType.movie.identifier) as? URL
                    if let src = fileURL {
                        let dest = PendingImportStore.containerDirectory
                            .appendingPathComponent("videos", isDirectory: true)
                        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                        let destFile = dest.appendingPathComponent(src.lastPathComponent)
                        try? FileManager.default.removeItem(at: destFile)
                        try FileManager.default.copyItem(at: src, to: destFile)
                        let item = PendingImportItem(kind: .videoFile, value: destFile.path)
                        PendingImportStore.append(item)
                        withAnimation { isQueued = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onComplete() }
                        return
                    }
                } catch {
                    errorMessage = "Could not save video: \(error.localizedDescription)"
                    return
                }
            }
        }

        errorMessage = "No supported recipe content found in this share."
    }
}
