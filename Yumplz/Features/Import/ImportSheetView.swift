import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Import sheet

/// The primary import entry point. Presented as a sheet from the Library FAB.
/// Guards behind ModelDownloadGateView if the LLM hasn't been downloaded yet.
struct ImportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Injected services — owned by the app-level environment.
    var downloads: ModelDownloadManager
    var importService: ImportService

    /// Called with the newly-created blank Recipe when the user chooses Manual Entry.
    /// The parent (LibraryView) uses this to navigate directly to RecipeDetailView.
    var onManualEntry: (Recipe) -> Void = { _ in }

    /// Pre-filled paste text injected via deep-link.
    var initialPasteText: String? = nil

    /// Pre-filled URL from Share Extension.
    var initialImportURL: String? = nil

    /// Pre-filled video path from Share Extension (App Group container).
    var initialVideoPath: String? = nil

    /// When true, user already confirmed import in the Share Extension — skip the picker.
    var autoStartImport: Bool = false

    /// Extraction mode chosen in the Share Extension.
    var shareExtractionMode: ShareExtractionMode = .captionOrDescription

    @State private var selectedSource: ImportSourceKind?
    @State private var urlText = ""
    @State private var pastedText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var phase: SheetPhase
    @State private var didAutoStartURLImport = false
    @State private var importErrorMessage = ""

    enum SheetPhase: Equatable {
        case sourcePicker
        case importing
        case modelGate(forSource: ImportSourceKind)
        case error
    }

    init(
        downloads: ModelDownloadManager,
        importService: ImportService,
        onManualEntry: @escaping (Recipe) -> Void = { _ in },
        initialPasteText: String? = nil,
        initialImportURL: String? = nil,
        initialVideoPath: String? = nil,
        autoStartImport: Bool = false,
        shareExtractionMode: ShareExtractionMode = .captionOrDescription
    ) {
        self.downloads = downloads
        self.importService = importService
        self.onManualEntry = onManualEntry
        self.initialPasteText = initialPasteText
        self.initialImportURL = initialImportURL
        self.initialVideoPath = initialVideoPath
        self.autoStartImport = autoStartImport
        self.shareExtractionMode = shareExtractionMode

        let skipSourcePicker = Self.shouldSkipSourcePicker(
            autoStartImport: autoStartImport,
            initialPasteText: initialPasteText,
            initialImportURL: initialImportURL,
            initialVideoPath: initialVideoPath
        )

        if skipSourcePicker {
            let llmReady = downloads.state(for: .llama3_2_3b).isReady
            if llmReady {
                _phase = State(initialValue: .importing)
            } else if initialVideoPath != nil {
                _phase = State(initialValue: .modelGate(forSource: .video))
                _selectedSource = State(initialValue: .video)
            } else if initialImportURL.flatMap({ ImportLinkParser.importableURL(from: $0) }) != nil {
                _phase = State(initialValue: .modelGate(forSource: .url))
                _selectedSource = State(initialValue: .url)
            } else if !(initialPasteText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                _phase = State(initialValue: .modelGate(forSource: .paste))
                _selectedSource = State(initialValue: .paste)
            } else {
                _phase = State(initialValue: .importing)
            }
        } else {
            _phase = State(initialValue: .sourcePicker)
        }

        _urlText = State(initialValue: initialImportURL ?? "")
        _pastedText = State(initialValue: initialPasteText ?? "")
    }

    private static func shouldSkipSourcePicker(
        autoStartImport: Bool,
        initialPasteText: String?,
        initialImportURL: String?,
        initialVideoPath: String?
    ) -> Bool {
        guard autoStartImport else { return false }
        if initialVideoPath != nil { return true }
        if initialImportURL.flatMap({ ImportLinkParser.importableURL(from: $0) }) != nil { return true }
        return !(initialPasteText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// True when the import in flight originated from an Instagram link — those
    /// can't be scraped, so any failure should surface the share-the-video guidance.
    private var isInstagramSource: Bool {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return SocialPlatformDetector.platform(for: url) == .instagram
    }

    var body: some View {
        ZStack {
            WarmGlassBackground()

            switch phase {
            case .sourcePicker:
                SourcePickerView(
                    onSelect: handleSourceSelected,
                    urlText: $urlText,
                    pastedText: $pastedText,
                    initialPasteText: initialPasteText
                )
                    .transition(.opacity.combined(with: .move(edge: .leading)))

            case .importing:
                WorkingView(phase: activeImportPhase)
                    .transition(.opacity)

            case .modelGate(let source):
                ModelDownloadGateView(downloads: downloads) {
                    launchAsyncImport(source: source)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

            case .error:
                ImportErrorView(
                    message: importErrorMessage,
                    canRetry: selectedSource != nil,
                    onRetry: {
                        if let source = selectedSource {
                            launchAsyncImport(source: source)
                        }
                    },
                    onChooseAnother: {
                        importService.reset()
                        phase = .sourcePicker
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.mkGentle, value: phase)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await autoStartSharedImportIfNeeded() }
        .onChange(of: importService.phase) { _, newPhase in
            guard phase == .importing else { return }
            switch newPhase {
            case .parsingWithAI, .done, .failed:
                dismiss()
            default:
                break
            }
        }
    }

    // MARK: Private

    private var activeImportPhase: ImportPhase {
        importService.phase.isWorking ? importService.phase : .idle
    }

    /// User confirmed import in Share Extension — run immediately, skip the in-app picker.
    private func autoStartSharedImportIfNeeded() async {
        guard autoStartImport, !didAutoStartURLImport else { return }
        didAutoStartURLImport = true

        let llmReady = downloads.state(for: .llama3_2_3b).isReady

        if let path = initialVideoPath {
            selectedSource = .video
            if llmReady {
                launchAsyncImport(source: .video)
            } else {
                phase = .modelGate(forSource: .video)
            }
            return
        }

        if let raw = initialImportURL, ImportLinkParser.importableURL(from: raw) != nil {
            urlText = raw
            selectedSource = .url
            if llmReady {
                launchAsyncImport(source: .url)
            } else {
                phase = .modelGate(forSource: .url)
            }
            return
        }

        if let paste = initialPasteText, !paste.isEmpty {
            pastedText = paste
            selectedSource = .paste
            if llmReady {
                launchAsyncImport(source: .paste)
            } else {
                phase = .modelGate(forSource: .paste)
            }
        }
    }

    private func handleSourceSelected(_ kind: ImportSourceKind) {
        // Guards against a double-tap on "Import" registering twice during the
        // sourcePicker -> importing transition animation, which would create
        // two placeholder Recipes and kick off two redundant background imports.
        guard phase == .sourcePicker else { return }

        if kind == .manual {
            createManualEntry()
            return
        }
        selectedSource = kind
        let llmReady = downloads.state(for: .llama3_2_3b).isReady
        if llmReady {
            phase = .importing
            launchAsyncImport(source: kind)
        } else {
            phase = .modelGate(forSource: kind)
        }
    }

    /// Creates a blank manual-entry Recipe, persists it, dismisses the sheet,
    /// and fires `onManualEntry` so the parent can navigate to RecipeDetailView.
    private func createManualEntry() {
        let recipe = Recipe(title: "")
        recipe.sourceKind = .manual
        recipe.needsReview = true
        recipe.importedAt = Date()
        modelContext.insert(recipe)
        try? modelContext.save()
        let created = recipe
        dismiss()
        onManualEntry(created)
    }

    private func launchAsyncImport(source kind: ImportSourceKind) {
        guard let importSource = makeImportSource(from: kind) else {
            importErrorMessage = "Enter a valid URL before importing."
            phase = .error
            return
        }
        phase = .importing
        _ = importService.beginBackgroundImport(
            from: importSource,
            in: modelContext,
            extractionMode: shareExtractionMode
        )
    }

    private func makeImportSource(from kind: ImportSourceKind) -> ImportSource? {
        switch kind {
        case .url:
            guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme != nil else { return nil }
            return .url(url)
        case .paste:
            return .pastedText(pastedText)
        case .photo(let data):
            return .photo(data)
        case .video:
            if let path = initialVideoPath {
                return .videoURL(URL(fileURLWithPath: path))
            }
            let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .videoURL(URL(fileURLWithPath: trimmed))
        case .manual:
            return nil
        }
    }
}

// MARK: - Import source kinds (UI-level enum)

enum ImportSourceKind: Equatable {
    case url
    case photo(Data)
    case video
    case paste
    case manual
}

// MARK: - Source picker

private struct SourcePickerView: View {
    var onSelect: (ImportSourceKind) -> Void
    @Binding var urlText: String
    @Binding var pastedText: String
    var initialPasteText: String? = nil

    @State private var pickerItem: PhotosPickerItem?
    @State private var step: PickerStep

    enum PickerStep { case chooser, urlEntry, pasteEntry }

    init(
        onSelect: @escaping (ImportSourceKind) -> Void,
        urlText: Binding<String>,
        pastedText: Binding<String>,
        initialPasteText: String? = nil
    ) {
        self.onSelect = onSelect
        _urlText = urlText
        _pastedText = pastedText
        self.initialPasteText = initialPasteText
        if initialPasteText != nil {
            _step = State(initialValue: .pasteEntry)
            pastedText.wrappedValue = initialPasteText ?? ""
        } else {
            _step = State(initialValue: .chooser)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if step == .chooser {
                        chooserGrid
                    } else if step == .urlEntry {
                        urlEntryView
                    } else {
                        pasteEntryView
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Chooser grid

    private var chooserGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            SourceTile(icon: "link", label: "From URL") {
                step = .urlEntry
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                SourceTileContent(icon: "camera.fill", label: "Photo / Camera")
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        onSelect(.photo(data))
                    }
                }
            }
            SourceTile(icon: "play.rectangle.fill", label: "Video URL") {
                step = .urlEntry  // reuse URL entry, caller distinguishes
            }
            SourceTile(icon: "doc.on.clipboard", label: "Paste Text") {
                step = .pasteEntry
            }
            SourceTile(icon: "pencil", label: "Manual Entry") {
                onSelect(.manual)
            }
        }
    }

    // MARK: URL entry

    private var urlEntryView: some View {
        VStack(spacing: 16) {
            TextField("https://…", text: $urlText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding()
                .glassCard()

            Button("Import") {
                onSelect(.url)
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlText.isEmpty)

            Button("Back") { step = .chooser }
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Paste entry

    private var pasteEntryView: some View {
        VStack(spacing: 16) {
            TextEditor(text: $pastedText)
                .frame(minHeight: 160)
                .padding()
                .glassCard()

            Button("Import") { onSelect(.paste) }
                .buttonStyle(.borderedProminent)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Back") { step = .chooser }
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Source tile helpers

private struct SourceTile: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SourceTileContent(icon: icon, label: label)
        }
    }
}

private struct SourceTileContent: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor)

            Text(label)
                .font(.mkCaption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassCard()
    }
}

// MARK: - Instagram guidance card

private struct InstagramGuidanceCard: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "video.badge.checkmark")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 10) {
                    Text("Share the video file instead")
                        .font(.mkHeading)
                        .multilineTextAlignment(.center)

                    Text("Instagram captions can't be read from a link. In Instagram, tap ··· → Save Video, then share the file to yumplz.")
                        .font(.mkBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(28)
            .glassCard()
            .padding(.horizontal, 24)

            Button("Got it") { onDismiss() }
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Import error view

/// Shown when an import fails. Surfaces the error (instead of silently dropping
/// the user back to a blank source picker) and offers retry / pick-another.
private struct ImportErrorView: View {
    let message: String
    let canRetry: Bool
    var onRetry: () -> Void
    var onChooseAnother: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.mkLilac)

                VStack(spacing: 10) {
                    Text("Couldn't import that")
                        .font(.mkHeading)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.mkBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(28)
            .glassCard()
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                if canRetry {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
                Button("Choose Another Method", action: onChooseAnother)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Working view

private struct WorkingView: View {
    let phase: ImportPhase

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                ProgressView()
                    .controlSize(.large)
                    .tint(.accentColor)
            }
            VStack(spacing: 8) {
                Text("Importing…")
                    .font(.mkHeading)
                Text(phase.displayLabel)
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Recipe draft review

private struct RecipeDraftReviewView: View {
    let draft: ParsedRecipeDTO
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Title", value: draft.title)
                    LabeledContent("Servings", value: "\(draft.servings)")
                    if let p = draft.prepTimeMinutes {
                        LabeledContent("Prep", value: "\(p) min")
                    }
                    if let c = draft.cookTimeMinutes {
                        LabeledContent("Cook", value: "\(c) min")
                    }
                }
                Section("Ingredients (\(draft.ingredients.count))") {
                    ForEach(draft.ingredients, id: \.originalText) { ing in
                        Text(IngredientDisplayFormatter.normalizedOriginalText(for: ing))
                            .font(.mkBody)
                    }
                }
                Section("Steps (\(draft.steps.count))") {
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { i, step in
                        if step.isSectionHeader {
                            Text(step.text)
                                .font(.mkHeading)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(i + 1). \(step.text)")
                                .font(.mkBody)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(WarmGlassBackground())
            .navigationTitle("Review Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", action: onDiscard)
                }
            }
        }
    }
}
