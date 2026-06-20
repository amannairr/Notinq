import Foundation

@MainActor
final class AIStreamingBuffer {
    private var chunks: [String] = []
    private var scheduledFlush: DispatchWorkItem?
    private let flushInterval: TimeInterval
    private let onFlush: (String) -> Void

    #if DEBUG
    private var flushCount = 0
    #endif

    init(
        flushInterval: TimeInterval,
        onFlush: @escaping (String) -> Void
    ) {
        self.flushInterval = flushInterval
        self.onFlush = onFlush
    }

    func append(_ token: String) {
        guard !token.isEmpty else { return }
        chunks.append(token)
        scheduleFlushIfNeeded()
    }

    func flushNow() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        flush()
    }

    func cancel() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        chunks.removeAll(keepingCapacity: true)
    }

    private func scheduleFlushIfNeeded() {
        guard scheduledFlush == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.scheduledFlush = nil
                self?.flush()
            }
        }
        scheduledFlush = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + flushInterval, execute: workItem)
    }

    private func flush() {
        guard !chunks.isEmpty else { return }
        let text = chunks.joined()
        chunks.removeAll(keepingCapacity: true)

        #if DEBUG
        flushCount += 1
        if flushCount % 40 == 0 {
            AIPerfLog.debug("stream flushes: \(flushCount)")
        }
        #endif

        onFlush(text)
    }
}
