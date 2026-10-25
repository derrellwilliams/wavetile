import os

/// App-wide loggers (Console: subsystem com.derrellwilliams.wavetile). Error text is redacted
/// in device logs by default, so nothing personal leaves the device unless you're debugging.
enum Log {
    static let library = Logger(subsystem: "com.derrellwilliams.wavetile", category: "library")

    /// For database observations that end with an error: the screen keeps its last values,
    /// but the failure shows up in a sysdiagnose instead of vanishing.
    static func observationFailed(_ error: any Error, file: String = #fileID, line: Int = #line) {
        guard !(error is CancellationError) else { return }
        library.error("Observation failed at \(file, privacy: .public):\(line): \(String(describing: error))")
    }
}
