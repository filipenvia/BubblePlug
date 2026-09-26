import Darwin
import Foundation

public struct VST3ValidationOutcome: Sendable, Equatable {
    public let status: String
    public let details: String

    public init(status: String, details: String) {
        self.status = status
        self.details = details
    }

    public var passed: Bool { status == "passed" }
}

/// Runs the bundled Steinberg validator outside both PlugSpot's and Live's processes.
public enum VST3PluginValidator {
    public static let version = "steinberg-vst3sdk-3.8.1"
    public static let timeout: TimeInterval = 120

    public static func validate(_ target: VST3PluginValidationTarget) async -> VST3ValidationOutcome {
        await Task.detached(priority: .userInitiated) {
            runValidator(bundleURL: target.bundleURL)
        }.value
    }

    private static func runValidator(bundleURL: URL) -> VST3ValidationOutcome {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/PlugSpotVST3Validator")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return VST3ValidationOutcome(status: "unavailable", details: "The bundled VST3 validation helper is missing.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugspot-vst3-validation-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else {
            return VST3ValidationOutcome(status: "unavailable", details: "Could not create a temporary validation log.")
        }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["-q", bundleURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return VST3ValidationOutcome(status: "unavailable", details: "Could not start validator: \(error.localizedDescription)")
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 2) == .timedOut {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
            return VST3ValidationOutcome(status: "timeout", details: "VST3 validation exceeded 120 seconds and was stopped.")
        }

        let outputText = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let details = String(outputText.trimmingCharacters(in: .whitespacesAndNewlines).suffix(4000))
        if process.terminationReason == .uncaughtSignal {
            return VST3ValidationOutcome(
                status: "crashed",
                details: "The VST3 validation helper crashed (signal \(process.terminationStatus)). \(details)"
            )
        }
        if process.terminationStatus == 0 {
            return VST3ValidationOutcome(status: "passed", details: details)
        }
        return VST3ValidationOutcome(
            status: "failed",
            details: "The VST3 validator returned status \(process.terminationStatus). \(details)"
        )
    }
}
