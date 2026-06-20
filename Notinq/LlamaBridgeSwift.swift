import Foundation

@_silgen_name("PLLlamaBackendAvailable")
func PLLlamaBackendAvailable() -> Bool

struct PLLlamaParams {
    var n_threads: Int32
    var n_ctx: Int32
    var n_gpu_layers: Int32
    var temperature: Float
    var top_p: Float
    var repeat_penalty: Float
}

@_silgen_name("PLLlamaCreateWithParams")
func PLLlamaCreateWithParams(_ modelPath: UnsafePointer<CChar>?, _ params: PLLlamaParams) -> UnsafeMutableRawPointer?

typealias LlamaTokenCallback = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

@_silgen_name("PLLamaGenerateStream")
func PLLamaGenerateStream(
    _ handle: UnsafeMutableRawPointer?,
    _ prompt: UnsafePointer<CChar>?,
    _ maxTokens: Int32,
    _ callback: LlamaTokenCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Bool

@_silgen_name("PLLamaCancelGeneration")
func PLLamaCancelGeneration(_ handle: UnsafeMutableRawPointer?)

@_silgen_name("PLLlamaDestroy")
func PLLlamaDestroy(_ handle: UnsafeMutableRawPointer?)
