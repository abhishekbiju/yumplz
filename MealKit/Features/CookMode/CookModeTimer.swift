import Foundation
import Observation
import UIKit
import UserNotifications

enum TimerState: Equatable {
    case idle, running, paused, finished
}

@MainActor
@Observable
final class CookModeTimer {
    let stepIndex: Int
    let totalSeconds: Int
    private(set) var remainingSeconds: Int
    private(set) var state: TimerState = .idle

    private var tickTask: Task<Void, Never>?

    init(stepIndex: Int, totalSeconds: Int) {
        self.stepIndex = stepIndex
        self.totalSeconds = totalSeconds
        self.remainingSeconds = totalSeconds
    }

    func start() {
        state = .running
        startTicking()
    }

    func pause() {
        state = .paused
        tickTask?.cancel()
        tickTask = nil
    }

    func resume() {
        state = .running
        startTicking()
    }

    func cancel() {
        tickTask?.cancel()
        tickTask = nil
        state = .idle
        remainingSeconds = totalSeconds
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            guard let self else { return }
            while self.remainingSeconds > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.remainingSeconds -= 1
            }
            self.state = .finished
            self.fireHaptic()
            await self.scheduleNotification()
        }
    }

    private func fireHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func scheduleNotification() async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Timer Finished"
        content.body = "Step \(stepIndex + 1) timer is done!"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
