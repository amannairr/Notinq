import Foundation

final class AIRouter {
    func route(contextLength: Int) -> AIProvider {
        if contextLength < 500 {
            return LlamaProvider.shared
        } else {
            return LlamaProvider.shared
        }
    }
}
