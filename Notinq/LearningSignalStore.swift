import Foundation

final class LearningSignalStore {
    static let shared = LearningSignalStore()

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "notinq.learning.signals.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    @discardableResult
    func append(_ signal: LearningSignal) -> Bool {
        var stored = allSignals()
        guard !stored.contains(where: { $0.proposalID == signal.proposalID && $0.signalType == signal.signalType }) else {
            return false
        }
        stored.append(signal)
        save(stored)
        return true
    }

    func allSignals() -> [LearningSignal] {
        guard let data = defaults.data(forKey: storageKey),
              let signals = try? JSONDecoder().decode([LearningSignal].self, from: data) else {
            return []
        }
        return signals
    }

    func signals(for proposalID: UUID) -> [LearningSignal] {
        allSignals().filter { $0.proposalID == proposalID }
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    private func save(_ signals: [LearningSignal]) {
        guard let data = try? JSONEncoder().encode(signals) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
