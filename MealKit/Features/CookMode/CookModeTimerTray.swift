import SwiftUI

struct CookModeTimerTray: View {
    let viewModel: CookModeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timers")
                .font(.mkCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(viewModel.timers, id: \.stepIndex) { timer in
                TimerRow(timer: timer, onRemove: { viewModel.removeTimer(timer) })
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }
}

private struct TimerRow: View {
    let timer: CookModeTimer
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(timer.stepIndex + 1)")
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
                Text(formattedTime)
                    .font(.mkBody.monospacedDigit())
                    .foregroundStyle(timer.state == .finished ? Color.mkGreen : .primary)
            }

            Spacer()

            if timer.state == .running {
                Button {
                    timer.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.caption)
                        .frame(width: 32, height: 32)
                        .glassCard(cornerRadius: 8)
                }
                .accessibilityLabel("Pause timer")
            } else if timer.state == .paused {
                Button {
                    timer.resume()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .frame(width: 32, height: 32)
                        .glassCard(cornerRadius: 8)
                }
                .accessibilityLabel("Resume timer")
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .frame(width: 32, height: 32)
                    .glassCard(cornerRadius: 8)
            }
            .accessibilityLabel("Cancel timer")
        }
    }

    private var formattedTime: String {
        switch timer.state {
        case .idle:
            return formatSeconds(timer.totalSeconds)
        case .running, .paused:
            return formatSeconds(timer.remainingSeconds)
        case .finished:
            return "Done ✓"
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
