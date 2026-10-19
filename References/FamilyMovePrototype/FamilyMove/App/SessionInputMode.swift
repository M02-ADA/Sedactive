import Foundation

enum SessionInputMode {
    case camera, simulator, automatedTest

    @MainActor static var current: Self {
        if UITestPoseSource.enabled { return .automatedTest }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulator-controls") { return .simulator }
        #endif
        return .camera
    }
    var usesCamera: Bool { self == .camera }

    @MainActor static var roundDuration: TimeInterval? {
        if current == .automatedTest { return UITestPoseSource.roundDuration }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if current == .simulator && args.contains("--ui-testing") && args.contains("--short-round") { return 20 }
        #endif
        return nil
    }
}
