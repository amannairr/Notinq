import Foundation

final class AIRouter {
    func route(contextLength: Int) -> any GenerationModelProvider {
        _ = contextLength
        return LlamaProvider.shared
    }
}
