import SwiftUI
import UniformTypeIdentifiers

// MARK: - ShareExtensionView

struct ShareExtensionView: View {
    let itemProviders: [NSItemProvider]
    let onComplete: () -> Void
    let onCancel: () -> Void
    /// Opens yumplz with the shared URL embedded in the deep link (primary open path).
    let onOpenImport: (String) -> Void

    @State private var detectedURL: String?
    @State private var detectedPlatform: SocialPlatform = .other
    @State private var isVideoFile = false
    @State private var isQueuing = false
    @State private var isQueued = false
    @State private var queuedOpenApp = false
    @State private var openFailed = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 20) {
                previewCard

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else if isQueued {
                    successView
                } else if detectedURL != nil || isVideoFile {
                    actionButtons
                } else {
                    ProgressView("Reading shared content…")
                        .padding(.top, 24)
                }

                Text("Parsed on your device — nothing is sent to the cloud.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.vertical, 24)
        }
        .background(Color(.systemBackground))
        .task { await detectContent() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("yumplz")
                .font(.headline)
            Spacer()
            Button("Cancel", action: onCancel)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: platformIcon)
                    .font(.title3)
                    .foregroundStyle(platformColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SocialPlatformDetector.displayName(for: detectedPlatform))
                        .font(.subheadline.weight(.semibold))
                    Text(isVideoFile ? "Video file" : kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let url = detectedURL {
                Text(url)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await queueImport(openApp: false) }
            } label: {
                actionLabel("Save for Later", loading: isQueuing && !queuedOpenApp)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isQueuing)

            Button {
                Task { await queueImport(openApp: true) }
            } label: {
                actionLabel("Open yumplz & Import", loading: isQueuing && queuedOpenApp)
            }
            .buttonStyle(.bordered)
            .disabled(isQueuing)
        }
        .padding(.horizontal, 20)
    }

    private func actionLabel(_ title: String, loading: Bool) -> some View {
        Group {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Saving…")
                }
            } else {
                Text(title)
            }
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var successView: some View {
        VStack(spacing: 8) {
            Label("Queued for import", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
            if queuedOpenApp {
                Text(openFailed
                     ? "Saved — open yumplz manually to finish importing."
                     : "Opening yumplz…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Open yumplz anytime to finish importing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var platformIcon: String {
        isVideoFile ? "film.fill" : SocialPlatformDetector.systemImage(for: detectedPlatform)
    }

    private var platformColor: Color {
        switch detectedPlatform {
        case .youtube: return .red
        case .tiktok: return .primary
        case .instagram: return .pink
        case .other: return .accentColor
        }
    }

    private var kindLabel: String {
        guard let url = detectedURL else { return "Link" }
        return url.contains("/shorts/") ? "YouTube Short" : "Recipe link"
    }

    private func detectContent() async {
        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                detectedURL = url.absoluteString
                detectedPlatform = SocialPlatformDetector.platform(for: url)
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = ImportLinkParser.importableURL(from: text) {
                detectedURL = url.absoluteString
                detectedPlatform = SocialPlatformDetector.platform(for: url)
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                isVideoFile = true
                detectedPlatform = .other
                return
            }
        }
        errorMessage = "No supported recipe content found in this share."
    }

    private func queueImport(openApp: Bool) async {
        isQueuing = true
        queuedOpenApp = openApp
        defer { isQueuing = false }

        do {
            if isVideoFile {
                try await queueVideoFile(openApp: openApp)
                return
            }
            guard let urlString = detectedURL,
                  ImportLinkParser.importableURL(from: urlString) != nil else {
                errorMessage = "No valid recipe link found."
                return
            }

            if openApp {
                withAnimation { isQueued = true }
                // Defense in depth: also queue so a manual launch recovers the recipe
                // if opening the app is ever blocked by the OS.
                if PendingImportStore.isUsingAppGroupContainer {
                    PendingImportStore.append(PendingImportItem(kind: .url, value: urlString, autoStartImport: true))
                }
                onOpenImport(urlString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onComplete()
                }
            } else {
                guard PendingImportStore.isUsingAppGroupContainer else {
                    errorMessage = "Shared storage unavailable. Set a Development Team in Xcode so the App Group entitlement is active, then rebuild."
                    return
                }
                PendingImportStore.append(PendingImportItem(kind: .url, value: urlString, autoStartImport: true))
                finishQueueing(openApp: false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func queueVideoFile(openApp: Bool) async throws {
        for provider in itemProviders where provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            guard let src = try await provider.loadItem(forTypeIdentifier: UTType.movie.identifier) as? URL else { continue }
            let dest = PendingImportStore.containerDirectory
                .appendingPathComponent("videos", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let destFile = dest.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.removeItem(at: destFile)
            try FileManager.default.copyItem(at: src, to: destFile)

            if openApp {
                withAnimation { isQueued = true }
                let payload = "file://\(destFile.path)"
                if PendingImportStore.isUsingAppGroupContainer {
                    PendingImportStore.append(PendingImportItem(
                        kind: .videoFile,
                        value: destFile.path,
                        extractionMode: .transcribeAudio,
                        autoStartImport: true
                    ))
                }
                onOpenImport(payload)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onComplete()
                }
            } else {
                guard PendingImportStore.isUsingAppGroupContainer else {
                    errorMessage = "Shared storage unavailable. Set a Development Team in Xcode so the App Group entitlement is active, then rebuild."
                    return
                }
                PendingImportStore.append(PendingImportItem(
                    kind: .videoFile,
                    value: destFile.path,
                    extractionMode: .transcribeAudio,
                    autoStartImport: true
                ))
                finishQueueing(openApp: false)
            }
            return
        }
        throw ShareExtensionError.videoCopyFailed
    }

    private func finishQueueing(openApp: Bool) {
        withAnimation { isQueued = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            onComplete()
        }
    }
}

private enum ShareExtensionError: LocalizedError {
    case videoCopyFailed

    var errorDescription: String? {
        "Could not copy the shared video."
    }
}
