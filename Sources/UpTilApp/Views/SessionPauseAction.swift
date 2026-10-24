import Foundation

/// Pause and Resume share one slot beside Stop, so a session can be paused and resumed without moving the pointer.
enum SessionPauseAction: CaseIterable {
    case pause
    case resume

    init?(state: SessionPresentationState) {
        switch state {
        case .timed:
            self = .pause
        case .paused:
            self = .resume
        case .idle, .indefinite:
            return nil
        }
    }

    var title: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        }
    }

    var systemImage: String {
        switch self {
        case .pause: "pause.fill"
        case .resume: "play.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pause: "Pause the session"
        case .resume: "Resume the session"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .pause: "Lets the Mac sleep and keeps the remaining time"
        case .resume: "Keeps the Mac awake again for the remaining time"
        }
    }

    @discardableResult
    @MainActor
    func perform(controller: SessionController) -> Bool {
        switch self {
        case .pause:
            controller.pause()
        case .resume:
            controller.resume()
        }
    }
}
