import AppKit
import Foundation

guard
    CommandLine.arguments.count == 2,
    let pid = pid_t(CommandLine.arguments[1]),
    let application = NSRunningApplication(processIdentifier: pid)
else {
    exit(2)
}

guard application.terminate() else {
    exit(3)
}

let deadline = Date().addingTimeInterval(20)
while !application.isTerminated, Date() < deadline {
    _ = RunLoop.current.run(
        mode: .default,
        before: Date().addingTimeInterval(0.05)
    )
}

exit(application.isTerminated ? 0 : 4)
