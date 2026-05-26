import SwiftUI

struct WeekCalendarView: View {
    let vm: PlanViewModel

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f
    }()

    private let numberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.daysInCurrentWeek, id: \.self) { day in
                    DayCell(
                        dayLabel: dayFormatter.string(from: day),
                        numberLabel: numberFormatter.string(from: day),
                        isSelected: vm.isSelectedDate(day),
                        isToday: vm.isToday(day)
                    ) {
                        vm.selectedDate = day
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

private struct DayCell: View {
    let dayLabel: String
    let numberLabel: String
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(dayLabel)
                    .font(.mkCaption)
                    .foregroundStyle(isSelected ? .white : .secondary)

                Text(numberLabel)
                    .font(.mkBody.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(
                                isSelected
                                    ? Color.accentColor
                                    : (isToday ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                    )
            }
            .frame(width: 44)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.mkSnap, value: isSelected)
    }
}
