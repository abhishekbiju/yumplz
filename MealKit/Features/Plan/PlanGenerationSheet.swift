import SwiftUI
import SwiftData

// MARK: - Constraint form

/// Sheet that collects generation constraints, drives PlanGenerationService,
/// and presents the draft for review before committing.
struct PlanGenerationSheet: View {
    let downloads: ModelDownloadManager
    let inference: InferenceService
    let allRecipes: [Recipe]

    @Environment(\.modelContext)            private var context
    @Environment(\.dismiss)                 private var dismiss
    @Environment(UserPreferencesStore.self) private var prefs

    // Constraint form state
    @State private var numberOfDays: Int = 7
    @State private var selectedDietaryTags: Set<String> = []
    @State private var hasAppliedPrefsDefaults = false
    @State private var excludedCuisine: String = ""
    @State private var maxCookTime: MaxCookTimeOption = .any
    @State private var servings: Int = 2

    @State private var service: PlanGenerationService?
    @State private var showModelGate = false

    private static let dietaryOptions = ["Vegetarian", "Vegan", "Gluten-Free", "Dairy-Free"]

    enum MaxCookTimeOption: String, CaseIterable, Identifiable {
        case any = "Any"
        case quick = "≤30 min"
        case medium = "≤60 min"
        case long = "≤90 min"

        var id: String { rawValue }
        var seconds: Int? {
            switch self {
            case .any:    return nil
            case .quick:  return 30 * 60
            case .medium: return 60 * 60
            case .long:   return 90 * 60
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()
                content
            }
            .navigationTitle("Generate Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                if !hasAppliedPrefsDefaults {
                    selectedDietaryTags = prefs.dietaryDefaults
                    hasAppliedPrefsDefaults = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showModelGate) {
            ModelDownloadGateView(downloads: downloads) {
                showModelGate = false
                startGeneration()
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if let svc = service {
            switch svc.state {
            case .idle:
                constraintForm
            case .generating(let step, let progress):
                generatingView(step: step, progress: progress)
            case .draft(let draft):
                DraftReviewView(
                    draft: draft,
                    allRecipes: allRecipes,
                    onAccept: {
                        svc.commit(draft: draft, pool: allRecipes, context: context)
                        dismiss()
                    },
                    onRetry: {
                        svc.reset()
                        startGeneration()
                    },
                    onCancel: {
                        svc.reset()
                        dismiss()
                    }
                )
            case .failed(let error):
                failedView(error: error)
            }
        } else {
            constraintForm
        }
    }

    // MARK: - Constraint form

    private var constraintForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Days
                VStack(alignment: .leading, spacing: 8) {
                    Label("Number of days", systemImage: "calendar")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                    Stepper("\(numberOfDays) day\(numberOfDays == 1 ? "" : "s")",
                            value: $numberOfDays, in: 1...7)
                        .font(.mkBody)
                }
                .padding(16)
                .glassCard()

                // Dietary
                VStack(alignment: .leading, spacing: 12) {
                    Label("Dietary restrictions", systemImage: "leaf")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.dietaryOptions, id: \.self) { tag in
                            FilterChip(
                                title: tag,
                                isSelected: selectedDietaryTags.contains(tag)
                            ) {
                                if selectedDietaryTags.contains(tag) {
                                    selectedDietaryTags.remove(tag)
                                } else {
                                    selectedDietaryTags.insert(tag)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .glassCard()

                // Cook time
                VStack(alignment: .leading, spacing: 8) {
                    Label("Max cook time", systemImage: "timer")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                    Picker("Max cook time", selection: $maxCookTime) {
                        ForEach(MaxCookTimeOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
                .glassCard()

                // Servings
                VStack(alignment: .leading, spacing: 8) {
                    Label("Servings per meal", systemImage: "person.2")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                    Stepper("\(servings) serving\(servings == 1 ? "" : "s")",
                            value: $servings, in: 1...12)
                        .font(.mkBody)
                }
                .padding(16)
                .glassCard()

                // Generate button
                Button {
                    handleGenerateTap()
                } label: {
                    Label("Generate Plan", systemImage: "sparkles")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(allRecipes.isEmpty)

                if allRecipes.isEmpty {
                    Text("Add some recipes to your Library first.")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Generating view

    private func generatingView(step: String, progress: Double) -> some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                ProgressRing(progress: progress, lineWidth: 6)
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 8) {
                Text("Building your plan…")
                    .font(.mkHeading)
                Text(step)
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
                    .animation(.default, value: step)
            }
            Spacer()
            Button("Cancel") {
                service?.reset()
                dismiss()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Failed view

    private func failedView(error: Error) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.mkLilac)
            Text("Generation failed")
                .font(.mkHeading)
            Text(error.localizedDescription)
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try again") {
                service?.reset()
                startGeneration()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Logic

    private func handleGenerateTap() {
        let llmReady = downloads.state(for: .llama3_2_3b).isReady
        if llmReady {
            startGeneration()
        } else {
            showModelGate = true
        }
    }

    private func startGeneration() {
        let svc = PlanGenerationService(inference: inference, downloads: downloads)
        service = svc
        let constraints = PlanConstraints(
            startDate: Date(),
            numberOfDays: numberOfDays,
            dietaryTags: selectedDietaryTags,
            excludedCuisines: excludedCuisine.isEmpty ? [] : [excludedCuisine],
            maxCookTimeSeconds: maxCookTime.seconds,
            servings: servings
        )
        Task {
            await svc.generate(constraints: constraints, from: allRecipes, context: context)
        }
    }
}

// MARK: - Draft review

private struct DraftReviewView: View {
    let draft: [DraftMeal]
    let allRecipes: [Recipe]
    let onAccept: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    private var draftByDay: [(Date, [DraftMeal])] {
        let grouped = Dictionary(grouping: draft) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(draftByDay, id: \.0) { date, meals in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayFormatter.string(from: date))
                                .font(.mkCaption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            ForEach(meals) { meal in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meal.slot.displayName)
                                            .font(.mkCaption)
                                            .foregroundStyle(.secondary)
                                        Text(meal.recipeTitle)
                                            .font(.mkBody.weight(.medium))
                                    }
                                    Spacer()
                                    Image(systemName: meal.slot.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .glassCard(cornerRadius: 12)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }

            VStack(spacing: 12) {
                Button(action: onAccept) {
                    Label("Accept Plan", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 20) {
                    Button("Try Again", action: onRetry)
                        .foregroundStyle(Color.accentColor)
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(.secondary)
                }
                .font(.mkBody)
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Small reusable components

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.mkCaption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                )
                .foregroundStyle(isSelected ? .white : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth && rowWidth > 0 {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    PlanGenerationSheet(
        downloads: ModelDownloadManager(),
        inference: InferenceService(),
        allRecipes: []
    )
    .modelContainer(for: [Recipe.self, PlannedMeal.self], inMemory: true)
}
