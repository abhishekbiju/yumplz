import SwiftUI
import SwiftData
import UserNotifications

struct CookModeView: View {
    @State private var viewModel: CookModeViewModel
    @State private var showingMiseEnPlace = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    init(recipe: Recipe) {
        _viewModel = State(wrappedValue: CookModeViewModel(recipe: recipe))
    }

    var body: some View {
        ZStack {
            WarmGlassBackground()

            VStack(spacing: 0) {
                progressHeader

                Spacer()

                if !viewModel.cookableSteps.isEmpty {
                    stepContent
                }

                Spacer()

                if !viewModel.timers.isEmpty {
                    CookModeTimerTray(viewModel: viewModel)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                navigationFooter
            }
        }
        .gesture(swipeGesture)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingMiseEnPlace = true
                } label: {
                    Label("Mise en Place", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .sheet(isPresented: $showingMiseEnPlace) {
            MiseEnPlaceView(viewModel: viewModel.miseEnPlace)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.invalidateTimers()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sub-views

    private var progressHeader: some View {
        VStack(spacing: 6) {
            ProgressView(value: viewModel.progressFraction)
                .tint(.accentColor)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text("Step \(viewModel.currentStepIndex + 1) of \(viewModel.cookableSteps.count)")
                .font(.mkCaption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var stepContent: some View {
        let step = viewModel.cookableSteps[viewModel.currentStepIndex]
        return VStack(spacing: 16) {
            Text(step.text)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 20)
                .padding(.horizontal, 20)
                .animation(.mkSnap, value: viewModel.currentStepIndex)

            if let timerSeconds = step.timerSeconds {
                timerChip(for: step, at: viewModel.currentStepIndex, duration: timerSeconds)
            }
        }
    }

    private var navigationFooter: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation(.mkSnap) { viewModel.goPrev() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .glassCard(cornerRadius: 16)
            }
            .disabled(viewModel.isFirstStep)
            .opacity(viewModel.isFirstStep ? 0.35 : 1)
            .accessibilityLabel("Previous step")

            Spacer()

            if viewModel.isLastStep {
                Button {
                    viewModel.finishCooking(context: modelContext)
                    dismiss()
                } label: {
                    Text("Finish Cooking")
                        .font(.mkBody.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(height: 56)
                        .background(Capsule().fill(Color.mkGreen))
                }
            } else {
                Button {
                    withAnimation(.mkSnap) { viewModel.goNext() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .glassCard(cornerRadius: 16)
                }
                .accessibilityLabel("Next step")
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    // MARK: - Timer chip

    @ViewBuilder
    private func timerChip(for step: Step, at index: Int, duration: Int) -> some View {
        let existingTimer = viewModel.timers.first(where: { $0.stepIndex == index })

        Group {
            if let timer = existingTimer {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.caption)
                    Text(timerChipLabel(timer))
                        .font(.mkCaption)
                        .monospacedDigit()

                    if timer.state == .running {
                        Button { timer.pause() } label: {
                            Image(systemName: "pause.fill").font(.caption2)
                        }
                    } else if timer.state == .paused {
                        Button { timer.resume() } label: {
                            Image(systemName: "play.fill").font(.caption2)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassCard(cornerRadius: 12)
            } else {
                Button {
                    viewModel.startTimer(for: step, at: index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text(formatSeconds(duration))
                            .font(.mkCaption)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassCard(cornerRadius: 12)
                }
            }
        }
    }

    private func timerChipLabel(_ timer: CookModeTimer) -> String {
        switch timer.state {
        case .idle: return formatSeconds(timer.totalSeconds)
        case .running, .paused: return formatSeconds(timer.remainingSeconds)
        case .finished: return "Done ✓"
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Swipe gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                if value.translation.width < -40 {
                    withAnimation(.mkSnap) { viewModel.goNext() }
                } else if value.translation.width > 40 {
                    withAnimation(.mkSnap) { viewModel.goPrev() }
                }
            }
    }
}
