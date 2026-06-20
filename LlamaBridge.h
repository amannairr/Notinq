#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*TokenCallback)(const char * token, void * userData);

typedef struct PLLlamaParams {
    int32_t n_threads;
    int32_t n_ctx;
    int32_t n_gpu_layers;
    float temperature;
    float top_p;
    float repeat_penalty;
} PLLlamaParams;

bool PLLlamaBackendAvailable(void);
void *PLLlamaCreate(const char *modelPath);
void *PLLlamaCreateWithParams(const char *modelPath, PLLlamaParams params);
char *PLLamaGenerate(void *handle, const char *prompt, int maxTokens);
bool PLLamaGenerateStream(void *handle, const char *prompt, int maxTokens, TokenCallback callback, void *userData);
void PLLamaCancelGeneration(void *handle);
void PLLlamaDestroy(void *handle);
void PLLlamaFreeCString(char *ptr);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
