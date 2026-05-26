import SwiftUI
import SwiftData

struct PlanView: View {
    let downloads: ModelDownloadManager
    let inference: InferenceService

    @State private var vm = PlanViewModel()
    @Query(sort: \PlannedMeal.date) private var allMeals: [PlannedMeal]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Environment(\.modelContext) private var context
    @State private var showGenerationSheet = false

    private var mealsOnSelectedDay: [PlannedMeal] {
        allMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: vm.selectedDate) }
    }

    private var weekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: vm.currentWeekStart) ?? vm.currentWeekStart
        return "\(f.string(from: vm.currentWeekStart)) – \(f.string(from: end))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()

                VStack(spacing: 0) {
                    // Week strip
                    WeekCalendarView(vm: vm)
                        .padding(.top, 4)

                    Divider()
                        .padding(.horizontal)
                        .padding(.vertical, 4)

                    // Slot list
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Slot.allCases) { slot in
                                PlanSlotView(
                                    slot: slot,
                                    date: vm.selectedDate,
                                    meals: mealsOnSelectedDay.filter { $0.slot == slot },
                                    isPastDay: vm.isPastDay(vm.selectedDate)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle(weekLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.mkGentle) { vm.prevWeek() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(weekLabel)
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.mkGentle) { vm.nextWeek() }
                        } label: {
                            Image(systemName: "chevron.right")
                                .fontWeight(.semibold)
                        }
                        Button {
                            showGenerationSheet = true
                        } label: {
                            Image(systemName: "sparkles")
                                .fontWeight(.semibold)
                        }
                        .accessibilityLabel("Generate AI plan")
                    }
                }
            }
            .sheet(isPresented: $showGenerationSheet) {
                PlanGenerationSheet(
                    downloads: downloads,
                    inference: inference,
                    allRecipes: allRecipes
                )
                .presentationDetents([.large])
            }
        }
    }
}

#Preview {
    PlanView(downloads: ModelDownloadManager(), inference: InferenceService())
        .modelContainer(for: [Recipe.self, PlannedMeal.self], inMemory: true)
}
