import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @Environment(UserPreferencesStore.self) private var prefs
    @State private var notificationsDenied = false

    private static let notificationID = "com.abhishekbiju.mealkit.mealReminder"

    // Synthesised Date binding so DatePicker can edit hour+minute atomically.
    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: prefs.mealReminderHour,
                minute: prefs.mealReminderMinute,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            prefs.mealReminderHour   = comps.hour   ?? prefs.mealReminderHour
            prefs.mealReminderMinute = comps.minute ?? prefs.mealReminderMinute
            if prefs.mealReminderEnabled { scheduleNotification() }
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Daily meal reminder", isOn: Binding(
                    get: { prefs.mealReminderEnabled },
                    set: { enabled in
                        prefs.mealReminderEnabled = enabled
                        if enabled {
                            Task { await requestAndSchedule() }
                        } else {
                            removeNotification()
                        }
                    }
                ))

                if prefs.mealReminderEnabled {
                    DatePicker(
                        "Reminder time",
                        selection: reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            if notificationsDenied {
                Section {
                    // swiftlint:disable:next force_unwrapping
                    Link(
                        "Open Settings to enable notifications",
                        destination: URL(string: UIApplication.openSettingsURLString)!
                    )
                    .foregroundStyle(.tint)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkNotificationStatus() }
    }

    // MARK: - Private helpers

    private func requestAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if granted {
                notificationsDenied = false
                scheduleNotification()
            } else {
                notificationsDenied = true
                prefs.mealReminderEnabled = false
            }
        } catch {
            prefs.mealReminderEnabled = false
        }
    }

    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])

        let content = UNMutableNotificationContent()
        content.title = "MealKit"
        content.body  = "Time to check your meal plan!"
        content.sound = .default

        var components      = DateComponents()
        components.hour     = prefs.mealReminderHour
        components.minute   = prefs.mealReminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func removeNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }
}
