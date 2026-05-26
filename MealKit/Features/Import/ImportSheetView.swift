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

    /// Pre-filled paste text injected via deep-link. When non-nil the source picker
    /// opens directly on the paste entry step.
    var initialPasteText: String? = nil

    @State private var selectedSource: ImportSourceKind?
    @State private var urlText = ""
    @State private var pastedText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var phase: SheetPhase = .sourcePicker

    enum SheetPhase: Equatable {
        case sourcePicker
        case modelGate(forSource: ImportSourceKind)
        case working
        case review
    }

    var body: some View {
        ZStack {
            WarmGlassBackground()

            switch phase {
            case .sourcePicker:
                SourcePickerView(onSelect: handleSourceSelected, initialPasteText: initialPasteText)
                    .transition(.opacity.combined(with: .move(edge: .leading)))

            case .modelGate(let source):
                ModelDownloadGateView(downloads: downloads) {
                    phase = .working
                    Task { await runImport(source: source) }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))

            case .working:
                WorkingView(phase: importService.phase)
                    .transition(.opacity)

            case .review:
                if let draft = importService.draft {
                    RecipeDraftReviewView(
                        draft: draft,
                        onSave: { saveDraft(draft) },
                        onDiscard: { dismiss() }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.mkGentle, value: phase)
        .onChange(of: importService.phase) { _, newPhase in
            if newPhase == .done { phase = .review }
            if case .failed = newPhase { phase = .sourcePicker }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    private func handleSourceSelected(_ kind: ImportSourceKind) {
        if kind == .manual {
            createManualEntry()
            return
        }
        selectedSource = kind
        let llmReady = downloads.state(for: .llama3_2_3b).isReady
        phase = llmReady ? .working : .modelGate(forSource: kind)
        if llmReady {
            // Source picker already captured user input — start immediately.
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

    private func runImport(source: ImportSourceKind) async {
        let importSource: ImportSource
        switch source {
        case .url:
            guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme != nil else { return }
            importSource = .url(url)
        case .paste:
            importSource = .pastedText(pastedText)
        case .photo(let data):
            importSource = .photo(data)
        case .video:
            guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            importSource = .videoURL(url)
        case .manual:
            // Manual entry now handled in handleSourceSelected via createManualEntry().
            return
        }
        await importService.startImport(from: importSource)
    }

    private func saveDraft(_ dto: ParsedRecipeDTO) {
        try? importService.save(dto, in: modelContext)
        dismiss()
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
    var initialPasteText: String? = nil

    @State private var urlText = ""
    @State private var pastedText: String
    @State private var pickerItem: PhotosPickerItem?
    @State private var step: PickerStep

    enum PickerStep { case chooser, urlEntry, pasteEntry }

    init(onSelect: @escaping (ImportSourceKind) -> Void, initialPasteText: String? = nil) {
        self.onSelect = onSelect
        self.initialPasteText = initialPasteText
        _pastedText = State(initialValue: initialPasteText ?? "")
        _step = State(initialValue: initialPasteText != nil ? .pasteEntry : .chooser)
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
                        Text(ing.originalText)
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
