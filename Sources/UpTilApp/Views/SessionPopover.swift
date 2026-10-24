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
    /// Turns an indefinite session into a timed one that ends after the chosen duration.
    case limit
    case shorten

    var sign: String {
        switch self {
        case .start, .extend, .limit: "+"
        case .shorten: "−"
        }
    }

    func accessibilityLabel(for choice: QuickDurationChoice) -> String {
        switch self {
        case .start:
            "Start a \(choice.sessionDurationDescription) session"
        case .extend:
            "Extend the session by \(choice.durationDescription)"
        case .limit:
            "End the session in \(choice.durationDescription)"
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
        case .limit:
            session == .indefinite
        case .shorten:
            session.canShorten(by: choice.duration, at: date)
        }
    }

    @discardableResult
    @MainActor
    func perform(choice: QuickDurationChoice, controller: SessionController) -> Bool {
        switch self {
        case .start, .limit:
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
    case paused

    init(session: KeepAwakeSession) {
        switch session {
        case .idle:
            self = .idle
        case .timed:
            self = .timed
        case .indefinite:
            self = .indefinite
        case .paused:
            self = .paused
        }
    }

    /// A paused session keeps the timed rows in place; they stay disabled until it resumes.
    var quickDurationActions: [QuickDurationAction] {
        switch self {
        case .idle:
            [.start, .shorten]
        case .timed, .paused:
            [.extend, .shorten]
        case .indefinite:
            [.limit, .shorten]
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

    var stopAccessibilityLabel: String {
        self == .paused ? "Stop the paused session and discard its remaining time" : "Stop the active session"
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
    static let pausedDescription = "Applies when the session resumes"
    static let accessibilityHint = "Prevents automatic display dimming and sleep only during an active UpTil session"

    @MainActor
    static func perform(isEnabled: Bool, controller: SessionController) {
        controller.setKeepsDisplayAwake(isEnabled)
    }
}

/// Fixed geometry shared by every popover state, so nothing moves under the pointer
/// when a click changes the session.
enum SessionPopoverLayout {
    static let width: CGFloat = 300
    static let heroHeight: CGFloat = 64
    static let heroSpacing: CGFloat = 10
    static let sessionRowHeight: CGFloat = 22
    static let headerHeight = heroHeight + heroSpacing + sessionRowHeight
    static let heroFont = Font.system(size: 32, weight: .light).monospacedDigit()
}

struct SessionPopover: View {
    @Bindable var controller: SessionController

    private var presentationState: SessionPresentationState {
        SessionPresentationState(session: controller.session)
    }

    var body: some View {
        VStack(spacing: 14) {
            sessionHeader
                .frame(height: SessionPopoverLayout.headerHeight)

            VStack(spacing: 8) {
                ForEach(presentationState.quickDurationActions, id: \.self) { action in
                    quickDurationSection(action: action)
                }
            }

            VStack(spacing: 10) {
                Divider()
                footer
            }
        }
        .padding(16)
        .frame(width: SessionPopoverLayout.width)
        .transaction { $0.animation = nil }
    }

    /// Every state fills the same two slots: a hero above one control row. While idle,
    /// Stop's slot holds only preview text, so a repeated click on Stop can never land
    /// on a control that starts a session.
    @ViewBuilder private var sessionHeader: some View {
        switch presentationState {
        case .idle:
            IdleStartControls(controller: controller)
        case .timed, .indefinite, .paused:
            VStack(spacing: SessionPopoverLayout.heroSpacing) {
                activeHero
                    .frame(maxWidth: .infinity)
                    .frame(height: SessionPopoverLayout.heroHeight)

                HStack(spacing: 12) {
                    if let pauseAction = SessionPauseAction(state: presentationState) {
                        pauseButton(pauseAction)
                    }

                    Button("Stop", systemImage: "stop.fill", role: .destructive) {
                        controller.stop()
                    }
                    .accessibilityLabel(presentationState.stopAccessibilityLabel)
                }
                .frame(height: SessionPopoverLayout.sessionRowHeight)
            }
        }
    }

    private func pauseButton(_ action: SessionPauseAction) -> some View {
        Button {
            action.perform(controller: controller)
        } label: {
            // Every title reserves its width, so Stop stays put when Pause turns into Resume.
            ZStack {
                ForEach(SessionPauseAction.allCases, id: \.self) { candidate in
                    Label(candidate.title, systemImage: candidate.systemImage)
                        .hidden()
                }
                Label(action.title, systemImage: action.systemImage)
            }
        }
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHint(action.accessibilityHint)
    }

    @ViewBuilder private var activeHero: some View {
        if let deadline = controller.session.deadline {
            CountdownHero(deadline: deadline)
        } else if case let .paused(remaining) = controller.session {
            PausedCountdownHero(remaining: remaining)
        } else {
            VStack(spacing: 0) {
                Image(systemName: "infinity")
                    .font(SessionPopoverLayout.heroFont)
                    .accessibilityHidden(true)
                Text("No time limit · + sets one")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Awake until stopped. Add time to set an end.")
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

    private var footer: some View {
        HStack(spacing: 8) {
            displayAwakeToggle

            Spacer(minLength: 0)

            Button {
                AppQuitAction.perform(controller: controller) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Quit")
                    Text("⌘Q")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .accessibilityLabel("Quit UpTil")
        }
        .font(.callout)
    }

    private var displayAwakeToggle: some View {
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
            Label(DisplayAwakeTogglePresentation.label, systemImage: DisplayAwakeTogglePresentation.systemImage)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(
            presentationState == .paused
                ? DisplayAwakeTogglePresentation.pausedDescription
                : DisplayAwakeTogglePresentation.description
        )
        .accessibilityLabel("Keep display awake")
        .accessibilityHint(DisplayAwakeTogglePresentation.accessibilityHint)
    }
}

/// The idle header: the start options other than a quick duration. The preview shares
/// the Start button's resolved deadline and sits in the slot Stop takes once a session runs.
struct IdleStartControls: View {
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

            VStack(spacing: SessionPopoverLayout.heroSpacing) {
                VStack(spacing: 6) {
                    Text("Not keeping awake")
                        .font(.title2)

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

                        Button("Start") {
                            if let deadline {
                                _ = startUntil(deadline)
                            }
                        }
                        .disabled(deadline == nil)
                        .accessibilityLabel("Start session until selected time")

                        Button {
                            controller.startIndefinitely()
                        } label: {
                            Image(systemName: "infinity")
                                .accessibilityHidden(true)
                        }
                        .help("Stay awake until stopped")
                        .accessibilityLabel("Start an indefinite session")
                    }
                }
                .frame(height: SessionPopoverLayout.heroHeight)

                Text(deadline.map { UntilDeadlineFormatting.string(for: $0, now: now) } ?? "Invalid end time")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: SessionPopoverLayout.sessionRowHeight)
            }
        }
    }

    func startUntil(_ deadline: Date) -> Bool {
        controller.start(until: deadline)
    }
}
