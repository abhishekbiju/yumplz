import SwiftUI
import SwiftData

struct PlanView: View {
    @State private var vm = PlanViewModel()
    @Query(sort: \PlannedMeal.date) private var allMeals: [PlannedMeal]
    @Environment(\.modelContext) private var context

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
                        .padding(.bottom, 32)
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
                    Button {
                        withAnimation(.mkGentle) { vm.nextWeek() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

#Preview {
    PlanView()
        .modelContainer(for: [Recipe.self, PlannedMeal.self], inMemory: true)
}
