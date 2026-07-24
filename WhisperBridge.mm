#import "WhisperBridge.h"
#import <vector>
#import <mutex>
#import <string>

extern "C" __attribute__((weak)) void *ggml_backend_blas_reg(void) {
    return nullptr;
}

extern "C" __attribute__((weak)) void *ggml_backend_metal_reg(void) {
    return nullptr;
}

#if __has_include("whisper.h")
#import "whisper.h"
#define WHISPER_BRIDGE_ENABLED 1
#elif __has_include(<whisper.h>)
#import <whisper.h>
#define WHISPER_BRIDGE_ENABLED 1
#elif __has_include("ThirdParty/whisper.cpp/include/whisper.h")
#import "ThirdParty/whisper.cpp/include/whisper.h"
#define WHISPER_BRIDGE_ENABLED 1
#else
#define WHISPER_BRIDGE_ENABLED 0
#endif

#if WHISPER_BRIDGE_ENABLED
struct PLWhisperHandle {
    whisper_context *ctx = nullptr;
    int threads = 1;
    std::mutex mutex;
};
#endif

extern "C" {
    bool PLWhisperBackendAvailable(void);
    void *PLWhisperCreate(const char *modelPath, int threads);
    bool PLWhisperIsReady(void *handle);
    char *PLWhisperTranscribe(void *handle, const float *pcm, int nSamples);
    void PLWhisperDestroy(void *handle);
    void PLWhisperFreeCString(char *ptr);
}

bool PLWhisperBackendAvailable(void) {
#if WHISPER_BRIDGE_ENABLED
    return true;
#else
    return false;
#endif
}

void *PLWhisperCreate(const char *modelPath, int threads) {
#if WHISPER_BRIDGE_ENABLED
    if (!modelPath) { return nullptr; }
    auto *handle = new PLWhisperHandle();
    handle->threads = threads > 0 ? threads : 1;
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    handle->ctx = whisper_init_from_file(modelPath);
    #pragma clang diagnostic pop
    if (!handle->ctx) {
        delete handle;
        return nullptr;
    }
    return handle;
#else
    (void)modelPath;
    (void)threads;
    return nullptr;
#endif
}

bool PLWhisperIsReady(void *handle) {
#if WHISPER_BRIDGE_ENABLED
    auto *h = static_cast<PLWhisperHandle *>(handle);
    return h && h->ctx;
#else
    (void)handle;
    return false;
#endif
}

char *PLWhisperTranscribe(void *handle, const float *pcm, int nSamples) {
#if WHISPER_BRIDGE_ENABLED
    auto *h = static_cast<PLWhisperHandle *>(handle);
    if (!h || !h->ctx || !pcm || nSamples <= 0) { return nullptr; }

    std::lock_guard<std::mutex> lock(h->mutex);

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.no_timestamps = true;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.no_context = false;
    params.single_segment = true;
    params.language = "en";
    params.n_threads = h->threads;

    if (whisper_full(h->ctx, params, pcm, nSamples) != 0) {
        return nullptr;
    }

    const int segments = whisper_full_n_segments(h->ctx);
    std::string joined;
    for (int i = 0; i < segments; ++i) {
        const char *text = whisper_full_get_segment_text(h->ctx, i);
        if (text) {
            joined += text;
        }
    }

    while (!joined.empty() && (joined.back() == ' ' || joined.back() == '\n' || joined.back() == '\t')) {
        joined.pop_back();
    }

    char *out = (char *)malloc(joined.size() + 1);
    if (!out) { return nullptr; }
    memcpy(out, joined.c_str(), joined.size() + 1);
    return out;
#else
    (void)handle;
    (void)pcm;
    (void)nSamples;
    return nullptr;
#endif
}

void PLWhisperDestroy(void *handle) {
#if WHISPER_BRIDGE_ENABLED
    auto *h = static_cast<PLWhisperHandle *>(handle);
    if (!h) { return; }
    {
        std::lock_guard<std::mutex> lock(h->mutex);
        if (h->ctx) {
            whisper_free(h->ctx);
            h->ctx = nullptr;
        }
    }
    delete h;
#else
    (void)handle;
#endif
}

void PLWhisperFreeCString(char *ptr) {
    if (ptr) {
        free(ptr);
    }
}

@interface WhisperBridge () {
#if WHISPER_BRIDGE_ENABLED
    struct whisper_context *_ctx;
    std::mutex _whisperMutex;
#endif
    NSInteger _threads;
}
@end

@implementation WhisperBridge

- (nullable instancetype)initWithModelPath:(NSString *)modelPath threads:(NSInteger)threads {
    self = [super init];
    if (!self) { return nil; }

    _threads = MAX(1, threads);
#if WHISPER_BRIDGE_ENABLED
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    _ctx = whisper_init_from_file([modelPath UTF8String]);
    #pragma clang diagnostic pop
    if (!_ctx) {
        return nil;
    }
#else
    return nil;
#endif
    return self;
}

- (nullable NSString *)transcribePCMData:(NSData *)pcmData {
#if WHISPER_BRIDGE_ENABLED
    if (!_ctx || pcmData.length == 0) { return @""; }

    const float *pcm = (const float *)pcmData.bytes;
    const int nSamples = (int)(pcmData.length / sizeof(float));
    if (!pcm || nSamples <= 0) { return @""; }

    std::lock_guard<std::mutex> lock(_whisperMutex);

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.no_timestamps = true;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.no_context = false;
    params.single_segment = true;
    params.language = "en";
    params.n_threads = (int)_threads;

    if (whisper_full(_ctx, params, pcm, nSamples) != 0) {
        return nil;
    }

    const int segments = whisper_full_n_segments(_ctx);
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < segments; i++) {
        const char *text = whisper_full_get_segment_text(_ctx, i);
        if (text) {
            [result appendString:[NSString stringWithUTF8String:text]];
        }
    }
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
#else
    (void)pcmData;
    return @"";
#endif
}

- (BOOL)isReady {
#if WHISPER_BRIDGE_ENABLED
    return _ctx != nullptr;
#else
    return NO;
#endif
}

- (NSNumber *)readyValue {
    return @([self isReady]);
}

- (void)resetTimings {
#if WHISPER_BRIDGE_ENABLED
    std::lock_guard<std::mutex> lock(_whisperMutex);
    if (_ctx) {
        whisper_reset_timings(_ctx);
    }
#endif
}

- (void)shutdown {
#if WHISPER_BRIDGE_ENABLED
    std::lock_guard<std::mutex> lock(_whisperMutex);
    if (_ctx) {
        whisper_free(_ctx);
        _ctx = nullptr;
    }
#endif
}

- (void)dealloc {
    [self shutdown];
}

@end
