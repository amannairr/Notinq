import Foundation

protocol AIProvider {
    func run(prompt: String, completion: @escaping (String) -> Void)
}
