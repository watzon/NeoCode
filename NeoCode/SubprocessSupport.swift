import Darwin
import Foundation

struct SubprocessResult: Sendable {
    let output: String
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
}

nonisolated final class ManagedProcessRegistry {
    static let shared = ManagedProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    private nonisolated init() {}

    nonisolated func register(_ process: Process) {
        lock.withLock {
            processes[ObjectIdentifier(process)] = process
        }
    }

    nonisolated func unregister(_ process: Process) {
        lock.withLock {
            _ = processes.removeValue(forKey: ObjectIdentifier(process))
        }
    }

    nonisolated func terminate(_ process: Process) {
        unregister(process)
        Self.terminateProcessTree(rootPID: process.processIdentifier)
    }

    nonisolated func terminateAll() {
        let runningProcesses = lock.withLock {
            let snapshot = Array(processes.values)
            processes.removeAll()
            return snapshot
        }

        for process in runningProcesses {
            Self.terminateProcessTree(rootPID: process.processIdentifier)
        }
    }

    nonisolated static func isProcessAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private nonisolated static func terminateProcessTree(rootPID: pid_t) {
        guard rootPID > 0 else { return }

        let descendants = descendantProcessIdentifiers(of: rootPID)
        let orderedPIDs = descendants + [rootPID]

        send(signal: SIGTERM, to: orderedPIDs)
        waitForExit(of: orderedPIDs, timeout: 0.75)

        let remainingPIDs = orderedPIDs.filter(isProcessAlive)
        guard !remainingPIDs.isEmpty else { return }

        send(signal: SIGKILL, to: remainingPIDs)
    }

    private nonisolated static func send(signal: Int32, to processIdentifiers: [pid_t]) {
        for pid in processIdentifiers where pid > 0 {
            _ = Darwin.kill(pid, signal)
        }
    }

    private nonisolated static func waitForExit(of processIdentifiers: [pid_t], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if processIdentifiers.allSatisfy({ !isProcessAlive($0) }) {
                return
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private nonisolated static func descendantProcessIdentifiers(of parentPID: pid_t) -> [pid_t] {
        let children = childProcessIdentifiers(of: parentPID)
        guard !children.isEmpty else { return [] }

        var descendants: [pid_t] = []
        descendants.reserveCapacity(children.count)

        for childPID in children {
            descendants.append(contentsOf: descendantProcessIdentifiers(of: childPID))
            descendants.append(childPID)
        }

        return descendants
    }

    private nonisolated static func childProcessIdentifiers(of parentPID: pid_t) -> [pid_t] {
        let bufferByteCount = proc_listchildpids(parentPID, nil, 0)
        guard bufferByteCount > 0 else { return [] }

        let count = Int(bufferByteCount) / MemoryLayout<pid_t>.stride
        guard count > 0 else { return [] }

        let buffer = UnsafeMutablePointer<pid_t>.allocate(capacity: count)
        defer { buffer.deallocate() }

        let filledByteCount = proc_listchildpids(parentPID, buffer, Int32(bufferByteCount))
        guard filledByteCount > 0 else { return [] }

        let filledCount = Int(filledByteCount) / MemoryLayout<pid_t>.stride
        return (0..<filledCount)
            .map { buffer[$0] }
            .filter { $0 > 0 }
    }
}

nonisolated final class SubprocessRunner: @unchecked Sendable {
    private let process: Process
    private let outputPipe = Pipe()
    private let lock = NSLock()

    private var outputData = Data()
    private var continuation: CheckedContinuation<SubprocessResult, Error>?
    private var hasFinished = false
    private var didStart = false

    nonisolated init(process: Process) {
        self.process = process
        process.standardOutput = outputPipe
        process.standardError = outputPipe
    }

    nonisolated convenience init(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil
    ) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        self.init(process: process)
    }

    nonisolated var processIdentifier: pid_t? {
        lock.withLock {
            didStart ? process.processIdentifier : nil
        }
    }

    nonisolated func run() async throws -> SubprocessResult {
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(with: continuation)
            }
        } onCancel: {
            terminate()
        }

        try Task.checkCancellation()
        return result
    }

    nonisolated func terminate() {
        ManagedProcessRegistry.shared.terminate(process)
    }

    private nonisolated func start(with continuation: CheckedContinuation<SubprocessResult, Error>) {
        lock.withLock {
            self.continuation = continuation
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeOutput(handle.availableData)
        }

        process.terminationHandler = { [weak self] process in
            self?.finish(process: process)
        }

        do {
            try process.run()
            lock.withLock {
                didStart = true
            }
            ManagedProcessRegistry.shared.register(process)
        } catch {
            cleanupIO()
            resume(with: .failure(error))
        }
    }

    private nonisolated func consumeOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            outputData.append(data)
        }
    }

    private nonisolated func finish(process: Process) {
        ManagedProcessRegistry.shared.unregister(process)

        cleanupIO()
        consumeOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())

        let output = lock.withLock {
            String(data: outputData, encoding: .utf8) ?? ""
        }

        resume(with: .success(SubprocessResult(
            output: output,
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason
        )))
    }

    private nonisolated func cleanupIO() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
    }

    private nonisolated func resume(with result: Result<SubprocessResult, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<SubprocessResult, Error>? in
            guard !hasFinished else { return nil }
            hasFinished = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else { return }

        switch result {
        case .success(let output):
            continuation.resume(returning: output)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private extension NSLock {
    nonisolated func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
