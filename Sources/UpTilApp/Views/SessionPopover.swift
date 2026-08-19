import AppKit
import SwiftUI
import UpTilCore

enum SessionStartChoice: CaseIterable, Equatable, Identifiable {
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

    var accessibilityLabel: String {
        switch self {
        case .fifteenMinutes:
            "Start a 15 minute session"
        case .thirtyMinutes:
            "Start a 30 minute session"
        case .oneHour:
            "Start a 1 hour session"
        case .twoHours:
            "Start a 2 hour session"
        }
    }
}

enum SessionExtensionChoice: CaseIterable, Equatable, Identifiable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour

    var id: Self {
        self
    }

    var duration: TimeInterval {
        switch self {
        case .fiveMinutes:
            5 * 60
        case .fifteenMinutes:
            15 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        }
    }

    var title: String {
        switch self {
        case .fiveMinutes:
            "+5m"
        case .fifteenMinutes:
            "+15m"
        case .thirtyMinutes:
            "+30m"
        case .oneHour:
            "+1h"
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

    var startChoices: [SessionStartChoice] {
        self == .idle ? SessionStartChoice.allCases : []
    }

    var extensionChoices: [SessionExtensionChoice] {
        self == .timed ? SessionExtensionChoice.allCases : []
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppMetadata.displayName)
                .font(.headline)

            switch SessionPresentationState(session: controller.session) {
            case .idle:
                idleContent
            case .timed:
                timedContent
            case .indefinite:
                indefiniteContent
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
        .frame(width: 250)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep your Mac awake")
                .foregroundStyle(.secondary)

            ForEach(SessionStartChoice.allCases) { choice in
                Button(choice.title) {
                    controller.start(for: choice.duration)
                }
                .accessibilityLabel(choice.accessibilityLabel)
            }

            Button("Indefinitely") {
                controller.startIndefinitely()
            }
            .accessibilityLabel("Start an indefinite session")
        }
    }

    private var timedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let deadline = controller.session.deadline {
                Text(EndTimeFormatting.string(for: deadline))
                    .font(.headline)
                    .accessibilityLabel("Session ends at \(EndTimeFormatting.string(for: deadline))")
            }

            TimelineView(.animation(minimumInterval: 1)) { context in
                Text(remainingText(at: context.date))
                    .font(.title2)
                    .monospacedDigit()
                    .accessibilityLabel("\(remainingText(at: context.date)) remaining")
            }

            HStack(spacing: 6) {
                ForEach(SessionExtensionChoice.allCases) { choice in
                    Button(choice.title) {
                        controller.extend(by: choice.duration)
                    }
                    .accessibilityLabel("Extend by \(choice.title.dropFirst())")
                }
            }

            Button("Stop", role: .destructive) {
                controller.stop()
            }
            .accessibilityLabel("Stop the active session")
        }
    }

    private var indefiniteContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("∞  Indefinitely", systemImage: "infinity")
                .font(.headline)
                .accessibilityLabel("Running indefinitely")

            Button("Stop", role: .destructive) {
                controller.stop()
            }
            .accessibilityLabel("Stop the indefinite session")
        }
    }

    private func remainingText(at date: Date) -> String {
        guard let remaining = controller.session.remaining(at: date), remaining > 0 else {
            return "<1m"
        }

        return CompactDurationFormatter.string(remaining: remaining)
    }
}
