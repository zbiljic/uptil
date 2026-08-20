import AppKit
import SwiftUI
import UpTilCore

enum QuickDurationChoice: CaseIterable, Equatable, Identifiable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours

    var id: Self {
        self
    }

    var duration: TimeInterval {
        switch self {
        case .fifteenMinutes:
            15 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        case .twoHours:
            120 * 60
        }
    }

    var title: String {
        switch self {
        case .fifteenMinutes:
            "15m"
        case .thirtyMinutes:
            "30m"
        case .oneHour:
            "1h"
        case .twoHours:
            "2h"
        }
    }

    var sessionDurationDescription: String {
        switch self {
        case .fifteenMinutes:
            "15 minute"
        case .thirtyMinutes:
            "30 minute"
        case .oneHour:
            "1 hour"
        case .twoHours:
            "2 hour"
        }
    }

    var durationDescription: String {
        switch self {
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .oneHour:
            "1 hour"
        case .twoHours:
            "2 hours"
        }
    }
}

enum QuickDurationAction: Equatable {
    case start
    case extend

    func title(for choice: QuickDurationChoice) -> String {
        switch self {
        case .start:
            choice.title
        case .extend:
            "+\(choice.title)"
        }
    }

    func accessibilityLabel(for choice: QuickDurationChoice) -> String {
        switch self {
        case .start:
            "Start a \(choice.sessionDurationDescription) session"
        case .extend:
            "Extend the session by \(choice.durationDescription)"
        }
    }

    @discardableResult
    @MainActor
    func perform(choice: QuickDurationChoice, controller: SessionController) -> Bool {
        switch self {
        case .start:
            controller.start(for: choice.duration)
        case .extend:
            controller.extend(by: choice.duration)
        }
    }
}

enum SessionPresentationState: Equatable {
    case idle
    case timed
    case indefinite

    init(session: KeepAwakeSession) {
        switch session {
        case .idle:
            self = .idle
        case .timed:
            self = .timed
        case .indefinite:
            self = .indefinite
        }
    }

    var quickDurationAction: QuickDurationAction? {
        switch self {
        case .idle:
            .start
        case .timed:
            .extend
        case .indefinite:
            nil
        }
    }

    var quickDurationChoices: [QuickDurationChoice] {
        quickDurationAction == nil ? [] : QuickDurationChoice.allCases
    }

    var canStartUntil: Bool {
        self == .idle
    }

    var canStop: Bool {
        self != .idle
    }
}

enum AppQuitAction {
    @MainActor
    static func perform(controller: SessionController, terminate: () -> Void) {
        controller.shutdown()
        terminate()
    }
}

struct SessionPopover: View {
    @Bindable var controller: SessionController

    private var presentationState: SessionPresentationState {
        SessionPresentationState(session: controller.session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppMetadata.displayName)
                .font(.headline)

            statusContent

            if let action = presentationState.quickDurationAction {
                quickDurationControls(action: action)
            }

            switch presentationState {
            case .idle:
                idleSecondaryControls
            case .timed, .indefinite:
                stopControl
            }

            Divider()

            Button("Quit UpTil", role: .destructive) {
                AppQuitAction.perform(controller: controller) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q")
            .accessibilityLabel("Quit UpTil")
        }
        .padding(16)
        .frame(width: 300)
    }

    private var statusContent: some View {
        Group {
            switch presentationState {
            case .idle:
                idleStatus
            case .timed:
                timedStatus
            case .indefinite:
                indefiniteStatus
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
    }

    private var idleStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keep your Mac awake")
                .font(.title2)

            Text("Choose a duration to begin")
                .foregroundStyle(.secondary)
        }
    }

    private var timedStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.animation(minimumInterval: 1)) { context in
                Text(remainingText(at: context.date))
                    .font(.title2)
                    .monospacedDigit()
                    .accessibilityLabel("\(remainingText(at: context.date)) remaining")
            }

            if let deadline = controller.session.deadline {
                Text(EndTimeFormatting.string(for: deadline))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Session ends at \(EndTimeFormatting.string(for: deadline))")
            }
        }
    }

    private var indefiniteStatus: some View {
        Label("∞  Indefinitely", systemImage: "infinity")
            .font(.title2)
            .accessibilityLabel("Running indefinitely")
    }

    private func quickDurationControls(action: QuickDurationAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action == .start ? "Start for" : "Add time")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(presentationState.quickDurationChoices) { choice in
                    Button {
                        action.perform(choice: choice, controller: controller)
                    } label: {
                        Text(action.title(for: choice))
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel(action.accessibilityLabel(for: choice))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var idleSecondaryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            UntilStartControl(controller: controller)

            Button("Indefinitely") {
                controller.startIndefinitely()
            }
            .accessibilityLabel("Start an indefinite session")
        }
    }

    @ViewBuilder private var stopControl: some View {
        if presentationState.canStop {
            Button("Stop", role: .destructive) {
                controller.stop()
            }
            .accessibilityLabel("Stop the active session")
        }
    }

    private func remainingText(at date: Date) -> String {
        guard let remaining = controller.session.remaining(at: date), remaining > 0 else {
            return "<1m"
        }

        return CompactDurationFormatter.string(remaining: remaining)
    }
}

private struct UntilStartControl: View {
    @Bindable var controller: SessionController
    @State private var selectedTime = Date().addingTimeInterval(60 * 60)

    var body: some View {
        let now = Date()
        let deadline = WallClockDeadline.nextOccurrence(
            of: selectedTime,
            after: now,
            calendar: .current
        )

        VStack(alignment: .leading, spacing: 4) {
            Text("Until")
                .font(.subheadline)

            DatePicker(
                "Choose session end time",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .accessibilityLabel("Choose session end time")

            if let deadline {
                Text(UntilDeadlineFormatting.string(for: deadline, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Start Until") {
                    startUntil()
                }
                .accessibilityLabel("Start session until selected time")
            } else {
                Text("Invalid end time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Start Until") {}
                    .disabled(true)
                    .accessibilityLabel("Start session until selected time")
            }
        }
    }

    private func startUntil() {
        let currentTime = Date()
        guard
            let deadline = WallClockDeadline.nextOccurrence(
                of: selectedTime,
                after: currentTime,
                calendar: .current
            )
        else {
            return
        }

        controller.start(until: deadline)
    }
}
