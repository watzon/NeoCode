import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct RuntimeTests {
        @Test func runtimeCapsStartupOutputBufferToRecentTail() {
            let existing = String(repeating: "a", count: 8)
            let chunk = String(repeating: "b", count: 8)
    
            let result = OpenCodeRuntime.cappedOutputBuffer(existing, appending: chunk, limit: 10)
    
            #expect(result.count == 10)
            #expect(result == "aabbbbbbbb")
        }

        @Test func runtimeUsesTrimmedRecentOutputSnippet() {
            let snippet = OpenCodeRuntime.recentOutputSnippet(from: "\n\n  hello world  \n", limit: 5)
    
            #expect(snippet == "world")
        }

        @Test func runtimeFormatsStartupLogOutputAsSingleTrimmedLine() {
            let formatted = OpenCodeRuntime.startupLogOutput("\n  booting  \n\n listening on 127.0.0.1  \n")
    
            #expect(formatted == "booting | listening on 127.0.0.1")
        }

        @Test func runtimeFormatsEmptyStartupLogOutputWithPlaceholder() {
            let formatted = OpenCodeRuntime.startupLogOutput("\n   \n")
    
            #expect(formatted == "<none>")
        }

        @Test func runtimeDetectsListeningURLFromAlternateLogFormats() throws {
            let url = try #require(
                OpenCodeRuntime.detectedServerURL(
                    in: "[server] ready for connections at http://localhost:43123/global/health\n"
                )
            )
    
            #expect(url.absoluteString == "http://localhost:43123")
        }

        @Test func runtimeDetectsListeningHostPortWithoutSchemeAndNormalizesWildcardHost() throws {
            let url = try #require(
                OpenCodeRuntime.detectedServerURL(
                    in: "Listening on 0.0.0.0:54321\n"
                )
            )
    
            #expect(url.absoluteString == "http://127.0.0.1:54321")
        }

        @Test func runtimeResolvesExecutableFromPATH() throws {
            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }
    
            let executableName = "neocode-test-binary-\(UUID().uuidString)"
            let executableURL = tempDirectory.appendingPathComponent(executableName)
            try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    
            let resolvedURL = try OpenCodeRuntime.resolveExecutableURL(
                named: executableName,
                environment: ["PATH": tempDirectory.path]
            )
    
            #expect(resolvedURL.path == executableURL.path)
        }

        @Test func runtimeResolvesExplicitExecutablePath() throws {
            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDirectory) }
    
            let executableURL = tempDirectory.appendingPathComponent("opencode")
            try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    
            let resolvedURL = try OpenCodeRuntime.resolveExecutableURL(at: executableURL.path)
    
            #expect(resolvedURL.path == executableURL.path)
        }

        @Test func runtimeEnhancedPATHPrependsCommonLocationsWithoutDroppingExistingEntries() {
            let path = OpenCodeRuntime.enhancedPATH(from: "/custom/bin:/usr/local/bin")
            let entries = path.split(separator: ":").map(String.init)
    
            #expect(entries.first == NSHomeDirectory() + "/.bun/bin")
            #expect(entries.contains("/custom/bin"))
            #expect(entries.filter { $0 == "/usr/local/bin" }.count == 1)
        }

        @Test func runtimeNormalizedExecutablePathTreatsBlankInputAsNil() {
            #expect(OpenCodeRuntime.normalizedExecutablePath(nil) == nil)
            #expect(OpenCodeRuntime.normalizedExecutablePath("   ") == nil)
            #expect(OpenCodeRuntime.normalizedExecutablePath("  /tmp/opencode  ") == "/tmp/opencode")
        }

        @MainActor
        @Test func runtimeFailureStateStaysScopedToTheProjectThatFailed() async {
            let runtime = OpenCodeRuntime()
            runtime.preferredExecutablePath = "/definitely/missing/opencode"
    
            await runtime.ensureRunning(for: "/tmp/NeoCode-A")
    
            #expect(runtime.failureMessage(for: "/tmp/NeoCode-A")?.contains("Could not find the OpenCode CLI") == true)
            #expect(runtime.failureMessage(for: "/tmp/NeoCode-B") == nil)
            #expect(runtime.detailLabel(for: "/tmp/NeoCode-B") == "Select a project")
        }

        @Test func subprocessRunnerCancelsProcessTree() async throws {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
    
            let childPIDFile = tempDirectory.appendingPathComponent("child.pid")
            let runner = SubprocessRunner(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 30 & echo $! > \"\(childPIDFile.path)\" && wait"]
            )
    
            let task = Task {
                try await runner.run()
            }
    
            let rootPID = try await waitForProcessIdentifier(from: runner)
            let childPID = try await waitForChildProcessIdentifier(at: childPIDFile)
    
            task.cancel()
    
            do {
                _ = try await task.value
                Issue.record("Expected subprocess cancellation to throw")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected CancellationError, got \(error.localizedDescription)")
            }
    
            try await waitForProcessExit(rootPID)
            try await waitForProcessExit(childPID)
            #expect(!ManagedProcessRegistry.isProcessAlive(rootPID))
            #expect(!ManagedProcessRegistry.isProcessAlive(childPID))
        }

        @Test func managedProcessRegistryTerminateAllSweepsTrackedProcesses() async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 30"]
    
            try process.run()
            ManagedProcessRegistry.shared.register(process)
    
            ManagedProcessRegistry.shared.terminateAll()
    
            try await waitForProcessToStop(process)
            #expect(process.isRunning == false)
        }

        @MainActor
        @Test func persistedRuntimeProcessStoreSweepsRecordedProcesses() async throws {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
    
            let cacheURL = tempDirectory.appendingPathComponent("runtime-processes.json")
            let store = PersistedRuntimeProcessStore(cacheURL: cacheURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 30"]
    
            try process.run()
            let pid = process.processIdentifier
            store.record(projectPath: tempDirectory.path, pid: pid)
    
            let result = store.sweepTrackedProcesses()
            let secondPass = store.sweepTrackedProcesses()
    
            try await waitForProcessExit(pid)
            #expect(result.totalCount == 1)
            #expect(result.terminatedCount == 1)
            #expect(result.survivingCount == 0)
            #expect(secondPass.totalCount == 0)
        }
}
