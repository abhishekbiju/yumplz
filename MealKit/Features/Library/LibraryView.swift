import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var showingImportSheet = false

    // Services are injected from the app environment.
    var downloads: ModelDownloadManager
    var importService: ImportService

    var body: some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()

                ScrollView {
                    PlaceholderSurface(
                        title: "Library",
                        subtitle: "Collections-first browse with recipe grid. Tap + to import.",
                        systemImage: "books.vertical",
                        progress: "\(recipes.count) recipe(s) · Collections + grid UI pending"
                    )
                }

                // Import FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showingImportSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                        }
                        .buttonStyle(GradientFABStyle())
                        .accessibilityLabel("Import recipe")
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportSheetView(downloads: downloads, importService: importService)
        }
    }
}

#Preview {
    LibraryView(
        downloads: ModelDownloadManager(),
        importService: ImportService(
            downloads: ModelDownloadManager(),
            inference: InferenceService(),
            whisper: WhisperTranscriptionService()
        )
    )
    .modelContainer(for: Recipe.self, inMemory: true)
}
