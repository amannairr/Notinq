#import "LlamaBridge.h"
#import <cstring>
#import <mutex>
#import <string>
#import <vector>

#if defined(LLAMA_BRIDGE_FORCE_ENABLE) && __has_include("llama.h")
#import "llama.h"
#define LLAMA_BRIDGE_ENABLED 1
#elif defined(LLAMA_BRIDGE_FORCE_ENABLE) && __has_include(<llama.h>)
#import <llama.h>
#define LLAMA_BRIDGE_ENABLED 1
#else
#define LLAMA_BRIDGE_ENABLED 0
#endif

#if LLAMA_BRIDGE_ENABLED
struct PLLlamaHandle {
    std::string modelPath;
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    llama_sampler *sampler = nullptr;
    int32_t nCtx = 2048;
    int32_t nBatch = 512;
    std::mutex mutex;
};
#endif

bool PLLlamaBackendAvailable(void) {
#if LLAMA_BRIDGE_ENABLED
    return true;
#else
    return false;
#endif
}

void *PLLlamaCreate(const char *modelPath) {
#if LLAMA_BRIDGE_ENABLED
    if (!modelPath) {
        return nullptr;
    }

    llama_backend_init();

    auto *handle = new PLLlamaHandle();
    handle->modelPath = modelPath;

    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = 999;
    handle->model = llama_model_load_from_file(modelPath, modelParams);
    if (!handle->model) {
        delete handle;
        return nullptr;
    }

    llama_context_params ctxParams = llama_context_default_params();
    const int32_t trainCtx = llama_n_ctx_train(handle->model);
    if (trainCtx > 0) {
        handle->nCtx = trainCtx > 4096 ? 4096 : trainCtx;
    }
    ctxParams.n_ctx = handle->nCtx;
    ctxParams.n_batch = handle->nBatch;
    ctxParams.n_threads = 6;
    ctxParams.n_threads_batch = 6;

    handle->ctx = llama_init_from_model(handle->model, ctxParams);
    if (!handle->ctx) {
        llama_model_free(handle->model);
        handle->model = nullptr;
        delete handle;
        return nullptr;
    }

    llama_sampler_chain_params chainParams = llama_sampler_chain_default_params();
    handle->sampler = llama_sampler_chain_init(chainParams);
    if (!handle->sampler) {
        llama_free(handle->ctx);
        llama_model_free(handle->model);
        handle->ctx = nullptr;
        handle->model = nullptr;
        delete handle;
        return nullptr;
    }

    llama_sampler_chain_add(handle->sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(handle->sampler, llama_sampler_init_top_p(0.88f, 1));
    llama_sampler_chain_add(handle->sampler, llama_sampler_init_penalties(96, 1.24f, 0.0f, 0.0f));
    llama_sampler_chain_add(handle->sampler, llama_sampler_init_temp(0.62f));
    llama_sampler_chain_add(handle->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    return handle;
#else
    (void)modelPath;
    return nullptr;
#endif
}

char *PLLamaGenerate(void *handle, const char *prompt, int maxTokens) {
#if LLAMA_BRIDGE_ENABLED
    std::string generated;
    auto callback = [](const char * token, void * userData) {
        if (!token || !userData) { return; }
        auto *buffer = static_cast<std::string *>(userData);
        buffer->append(token);
    };

    const bool ok = PLLamaGenerateStream(handle, prompt, maxTokens, callback, &generated);
    if (!ok || generated.empty()) {
        return nullptr;
    }

    char *out = (char *)malloc(generated.size() + 1);
    if (!out) {
        return nullptr;
    }
    memcpy(out, generated.c_str(), generated.size() + 1);
    return out;
#else
    (void)handle;
    (void)prompt;
    (void)maxTokens;
    return nullptr;
#endif
}

bool PLLamaGenerateStream(void *handle, const char *prompt, int maxTokens, TokenCallback callback, void *userData) {
#if LLAMA_BRIDGE_ENABLED
    auto *h = static_cast<PLLlamaHandle *>(handle);
    if (!h || !prompt || maxTokens <= 0) {
        return false;
    }

    std::lock_guard<std::mutex> lock(h->mutex);
    if (!h->model || !h->ctx || !h->sampler) {
        return false;
    }

    llama_memory_t memory = llama_get_memory(h->ctx);
    if (memory) {
        llama_memory_clear(memory, true);
    }
    llama_sampler_reset(h->sampler);

    const llama_vocab *vocab = llama_model_get_vocab(h->model);
    if (!vocab) {
        return false;
    }

    std::vector<llama_token> promptTokens(h->nCtx);
    const int32_t promptTokenCount = llama_tokenize(
        vocab,
        prompt,
        (int32_t)strlen(prompt),
        promptTokens.data(),
        (int32_t)promptTokens.size(),
        true,
        true
    );

    if (promptTokenCount <= 0) {
        return false;
    }

    promptTokens.resize(promptTokenCount);
    if (promptTokenCount >= h->nCtx - 1) {
        return false;
    }

    llama_batch batch = llama_batch_init((int32_t)promptTokens.size(), 0, 1);
    for (int32_t i = 0; i < (int32_t)promptTokens.size(); ++i) {
        batch.token[i] = promptTokens[i];
        batch.pos[i] = i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i] = (i == (int32_t)promptTokens.size() - 1);
    }
    batch.n_tokens = (int32_t)promptTokens.size();

    if (llama_decode(h->ctx, batch) != 0) {
        llama_batch_free(batch);
        return false;
    }

    bool emittedToken = false;
    std::string lastPieceNormalized;
    std::string generated;
    int repeatedPieceStreak = 0;
    int32_t curPos = (int32_t)promptTokens.size();

    for (int i = 0; i < maxTokens && curPos < h->nCtx - 1; ++i) {
        const llama_token next = llama_sampler_sample(h->sampler, h->ctx, -1);
        if (next == llama_vocab_eos(vocab)) {
            break;
        }
        llama_sampler_accept(h->sampler, next);

        char piece[256];
        const int pieceLen = llama_token_to_piece(vocab, next, piece, (int)sizeof(piece), 0, true);
        if (pieceLen > 0) {
            const std::string pieceString(piece, pieceLen);
            if (pieceString.find("<|") != std::string::npos || pieceString.find("|>") != std::string::npos) {
                continue;
            }
            std::string normalized = pieceString;
            while (!normalized.empty() && (normalized.front() == ' ' || normalized.front() == '\n' || normalized.front() == '\t')) {
                normalized.erase(normalized.begin());
            }
            while (!normalized.empty() && (normalized.back() == ' ' || normalized.back() == '\n' || normalized.back() == '\t')) {
                normalized.pop_back();
            }
            if (!normalized.empty()) {
                if (normalized == lastPieceNormalized) {
                    repeatedPieceStreak += 1;
                } else {
                    repeatedPieceStreak = 0;
                    lastPieceNormalized = normalized;
                }
                // Prevent runaway loops like "Hello Hello Hello ..." on degenerate inputs.
                if (repeatedPieceStreak >= 24) {
                    break;
                }
            }
            if (callback) {
                callback(pieceString.c_str(), userData);
            }
            generated.append(pieceString);
            emittedToken = true;
        }

        llama_batch nextBatch = llama_batch_init(1, 0, 1);
        nextBatch.token[0] = next;
        nextBatch.pos[0] = curPos;
        nextBatch.n_seq_id[0] = 1;
        nextBatch.seq_id[0][0] = 0;
        nextBatch.logits[0] = true;
        nextBatch.n_tokens = 1;

        const int decodeResult = llama_decode(h->ctx, nextBatch);
        llama_batch_free(nextBatch);
        if (decodeResult != 0) {
            break;
        }
        curPos += 1;

        if (i > 96 && !generated.empty()) {
            const char last = generated.back();
            const bool sentenceEnded = last == '.' || last == '!' || last == '?' || (generated.size() >= 2 && generated.substr(generated.size() - 2) == "\n\n");
            if (sentenceEnded && i > maxTokens * 0.72) {
                break;
            }
        }
    }

    llama_batch_free(batch);
    return emittedToken;
#else
    (void)handle;
    (void)prompt;
    (void)maxTokens;
    (void)callback;
    (void)userData;
    return false;
#endif
}

void PLLlamaDestroy(void *handle) {
#if LLAMA_BRIDGE_ENABLED
    auto *h = static_cast<PLLlamaHandle *>(handle);
    if (!h) {
        return;
    }

    if (h->sampler) {
        llama_sampler_free(h->sampler);
        h->sampler = nullptr;
    }
    if (h->ctx) {
        llama_free(h->ctx);
        h->ctx = nullptr;
    }
    if (h->model) {
        llama_model_free(h->model);
        h->model = nullptr;
    }
    delete h;
#else
    (void)handle;
#endif
}

void PLLlamaFreeCString(char *ptr) {
    if (ptr) {
        free(ptr);
    }
}
