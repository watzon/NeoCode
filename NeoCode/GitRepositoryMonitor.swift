import Darwin
import Dispatch
import Foundation

nonisolated final class GitRepositoryMonitor: @unchecked Sendable {
    private struct Observation {
        let descriptor: CInt
        let source: DispatchSourceFileSystemObject
    }

    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(label: "tech.watzon.NeoCode.GitRepositoryMonitor")
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void

    private var observations: [Observation] = []
    private var debounceWorkItem: DispatchWorkItem?

    init(debounceInterval: TimeInterval = 0.35, onChange: @escaping @Sendable () -> Void) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func watch(urls: [URL]) {
        stop()

        let uniqueURLs = Array(Set(urls.map { $0.standardizedFileURL }))
            .sorted { $0.path < $1.path }

        var newObservations: [Observation] = []
        newObservations.reserveCapacity(uniqueURLs.count)

        for url in uniqueURLs {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
                queue: callbackQueue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleChangeNotification()
            }
            source.setCancelHandler {
                close(descriptor)
            }

            newObservations.append(Observation(descriptor: descriptor, source: source))
        }

        lock.lock()
        observations = newObservations
        lock.unlock()

        for observation in newObservations {
            observation.source.resume()
        }
    }

    func stop() {
        let activeObservations: [Observation]
        let pendingWorkItem: DispatchWorkItem?

        lock.lock()
        activeObservations = observations
        pendingWorkItem = debounceWorkItem
        observations = []
        debounceWorkItem = nil
        lock.unlock()

        pendingWorkItem?.cancel()
        for observation in activeObservations {
            observation.source.cancel()
        }
    }

    private func scheduleChangeNotification() {
        let workItem = DispatchWorkItem { [onChange] in
            onChange()
        }

        lock.lock()
        let previousWorkItem = debounceWorkItem
        debounceWorkItem = workItem
        lock.unlock()

        previousWorkItem?.cancel()
        callbackQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
