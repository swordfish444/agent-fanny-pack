import Foundation

public struct CommandSpec: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(executable: String, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ProcessRunning {
    func run(_ spec: CommandSpec, standardInput: String?, timeout: TimeInterval) throws -> CommandResult
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ spec: CommandSpec, standardInput: String? = nil, timeout: TimeInterval = 5) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.executable)
        process.arguments = spec.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(spec.environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        try process.run()
        if let standardInput {
            stdin.fileHandleForWriting.write(Data(standardInput.utf8))
        }
        try? stdin.fileHandleForWriting.close()

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            throw FannyPackError.timedOut(spec.arguments.first ?? spec.executable)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)
    }
}
