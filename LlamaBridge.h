#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*TokenCallback)(const char * token, void * userData);

bool PLLlamaBackendAvailable(void);
void *PLLlamaCreate(const char *modelPath);
char *PLLamaGenerate(void *handle, const char *prompt, int maxTokens);
bool PLLamaGenerateStream(void *handle, const char *prompt, int maxTokens, TokenCallback callback, void *userData);
void PLLlamaDestroy(void *handle);
void PLLlamaFreeCString(char *ptr);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
