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

enum QuickDurationAction: Hashable {
    case start
    case extend
    case shorten

    var sectionTitle: String {
        switch self {
        case .start, .extend:
            "Add time"
        case .shorten:
            "Remove time"
        }
    }

    var sign: String {
        switch self {
        case .start, .extend: "+"
        case .shorten: "−"
        }
    }

    func accessibilityLabel(for choice: QuickDurationChoice) -> String {
        switch self {
        case .start:
            "Start a \(choice.sessionDurationDescription) session"
        case .extend:
            "Extend the session by \(choice.durationDescription)"
        case .shorten:
            "Shorten the session by \(choice.durationDescription)"
        }
    }

    func isEnabled(
        for choice: QuickDurationChoice,
        session: KeepAwakeSession,
        at date: Date
    ) -> Bool {
        switch self {
        case .start:
            session == .idle
        case .extend:
            session.deadline != nil
        case .shorten:
            session.canShorten(by: choice.duration, at: date)
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
        case .shorten:
            controller.shorten(by: choice.duration)
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

    var quickDurationActions: [QuickDurationAction] {
        switch self {
        case .idle:
            [.start, .shorten]
        case .timed, .indefinite:
            [.extend, .shorten]
        }
    }

    var quickDurationChoices: [QuickDurationChoice] {
        QuickDurationChoice.allCases
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

enum DisplayAwakeTogglePresentation {
    static let label = "Keep display awake"
    static let systemImage = "display"
    static let description = "During sessions only"
    static let accessibilityHint = "Prevents automatic display dimming and sleep only during an active UpTil session"

    @MainActor
    static func perform(isEnabled: Bool, controller: SessionController) {
        controller.setKeepsDisplayAwake(isEnabled)
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

            displayAwakeToggle

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ForEach(presentationState.quickDurationActions, id: \.self) { action in
                    quickDurationSection(action: action)
                }

                Spacer(minLength: 0)

                switch presentationState {
                case .idle:
                    idleSecondaryControls
                case .timed, .indefinite:
                    stopControl
                }
            }
            .frame(height: 224, alignment: .topLeading)

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
        .transaction { $0.animation = nil }
    }

    private var displayAwakeToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: {
                    controller.keepsDisplayAwake
                },
                set: { enabled in
                    DisplayAwakeTogglePresentation.perform(
                        isEnabled: enabled,
                        controller: controller
                    )
                }
            )) {
                Label(DisplayAwakeTogglePresentation.label, systemImage: "display")
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Keep display awake")
            .accessibilityHint(DisplayAwakeTogglePresentation.accessibilityHint)

            Text(DisplayAwakeTogglePresentation.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 54, alignment: .topLeading)
    }

    private var idleStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No active session")
                .font(.title2)

            Text("Choose a duration to stay awake")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var timedStatus: some View {
        if let deadline = controller.session.deadline {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(timerInterval: min(context.date, deadline) ... deadline, showsHours: true)
                            .font(.title2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: 100, alignment: .leading)
                        Text("remaining")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    Text("Until \(EndTimeFormatting.string(for: deadline, now: context.date))")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(
                            "Session ends \(EndTimeFormatting.string(for: deadline, now: context.date))"
                        )
                }
            }
        }
    }

    private var indefiniteStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Awake until stopped", systemImage: "infinity")
                .font(.title2)
            Text("Stop the session to allow sleep")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func quickDurationSection(action: QuickDurationAction) -> some View {
        if action == .shorten, presentationState == .timed {
            TimelineView(.animation(minimumInterval: 1)) { context in
                quickDurationControls(action: action, at: context.date)
            }
        } else {
            quickDurationControls(action: action, at: Date())
        }
    }

    private func quickDurationControls(action: QuickDurationAction, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.sectionTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(presentationState.quickDurationChoices) { choice in
                    let isEnabled = action.isEnabled(for: choice, session: controller.session, at: date)
                    Button {
                        action.perform(choice: choice, controller: controller)
                    } label: {
                        HStack(spacing: 0) {
                            Text(action.sign)
                                .frame(width: 8)
                            Text(choice.title)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isEnabled ? (action == .shorten ? .secondary : .primary) : .tertiary)
                    }
                    .accessibilityLabel(action.accessibilityLabel(for: choice))
                    .disabled(!isEnabled)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var idleSecondaryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            UntilStartControl(controller: controller)

            Button("Indefinitely", systemImage: "infinity") {
                controller.startIndefinitely()
            }
            .accessibilityLabel("Start an indefinite session")
        }
    }

    @ViewBuilder private var stopControl: some View {
        if presentationState.canStop {
            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                controller.stop()
            }
            .accessibilityLabel("Stop the active session")
        }
    }
}

struct UntilStartControl: View {
    @Bindable var controller: SessionController
    @State private var selectedTime = Date().addingTimeInterval(60 * 60)

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let now = Date()
            let deadline = WallClockDeadline.nextOccurrence(
                of: selectedTime,
                after: now,
                calendar: .current
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Until", systemImage: "clock")
                        .font(.subheadline)

                    DatePicker(
                        "Choose session end time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .accessibilityLabel("Choose session end time")

                    Spacer(minLength: 0)

                    Button("Start") {
                        if let deadline {
                            _ = startUntil(deadline)
                        }
                    }
                    .disabled(deadline == nil)
                    .accessibilityLabel("Start session until selected time")
                }

                Text(deadline.map { UntilDeadlineFormatting.string(for: $0, now: now) } ?? "Invalid end time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    func startUntil(_ deadline: Date) -> Bool {
        controller.start(until: deadline)
    }
}
