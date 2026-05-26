import Foundation
import Observation

@MainActor
@Observable
final class PlanViewModel {
    var currentWeekStart: Date
    var selectedDate: Date

    init() {
        let today = Date()
        let monday = Self.mondayOfWeek(containing: today)
        self.currentWeekStart = monday
        self.selectedDate = Calendar.current.startOfDay(for: today)
    }

    private static func mondayOfWeek(containing date: Date) -> Date {
        let calendar = Calendar.current
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7  // 0=Mon, 1=Tue, ..., 6=Sun
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
        return calendar.startOfDay(for: monday)
    }

    func nextWeek() {
        currentWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart)
            ?? currentWeekStart
    }

    func prevWeek() {
        currentWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: currentWeekStart)
            ?? currentWeekStart
    }

    var daysInCurrentWeek: [Date] {
        (0..<7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: currentWeekStart)
        }
    }

    func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func isSelectedDate(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    func isPastDay(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }
}
