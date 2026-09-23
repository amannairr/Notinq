import Foundation

final class AIRouter {
    func route(contextLength: Int) -> any AIProviderProtocol {
        _ = contextLength
        return InferenceEngine.shared.activeProvider
    }
}
