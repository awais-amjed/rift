// The library as the Rust crate uses it (rift_dpdfnet.h), for test.sh: both
// models open on the weights files given, run, start over on a reset, and on
// Windows hand back the registers a Windows function must keep
// (test_registers.S). On a CPU without AVX2 and FMA it checks only that
// nothing opens, and returns 77.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rift_dpdfnet.h"

#define CHECK(what)                                              \
  do {                                                           \
    if (!(what)) {                                               \
      fprintf(stderr, "test_model.c:%d: %s\n", __LINE__, #what); \
      return 1;                                                  \
    }                                                            \
  } while (0)

enum { kFrames = 300 };

// A steady hiss with a tone moving through it, as a spectrum.
static void spectrum(float *out, int frame) {
  uint32_t random = (uint32_t)frame * 2654435761u + 12345u;
  for (int i = 0; i < RIFT_DPDFNET_SPECTRUM; ++i) {
    random = random * 1664525u + 1013904223u;
    float noise = (float)((int)(random >> 16) - 32768) / 32768.0f;
    out[i] = 2.0f * noise + 30.0f * sinf((float)(i * 5 + frame * 3) * 0.02f);
  }
  out[1] = out[RIFT_DPDFNET_SPECTRUM - 1] = 0.0f;
}

#ifdef _WIN32
unsigned rift_test_call(int (*fn)(void *, void *), void *a, void *b, int *result);
int rift_test_clobber(void *, void *);

static int run_for_call(void *model, void *frame) {
  return rift_dpdfnet_model_run(model, frame);
}
#endif

// A weights.f32, whole, as the Rust crate reads it; NULL if it cannot be.
static float *read_weights(const char *path, size_t *count) {
  FILE *file = fopen(path, "rb");
  if (!file) return NULL;
  float *weights = NULL;
  if (fseek(file, 0, SEEK_END) == 0) {
    long bytes = ftell(file);
    *count = bytes > 0 ? (size_t)bytes / sizeof(float) : 0;
    weights = *count ? malloc(*count * sizeof(float)) : NULL;
    if (weights && (fseek(file, 0, SEEK_SET) != 0 ||
                    fread(weights, sizeof(float), *count, file) != *count)) {
      free(weights);
      weights = NULL;
    }
  }
  fclose(file);
  return weights;
}

static int test(int size, const char *path) {
  size_t count = 0;
  float *weights = read_weights(path, &count);
  CHECK(weights);
  // Weights one float short are not the model's.
  CHECK(!rift_dpdfnet_model_open(size, weights, count - 1));
  CHECK(!rift_dpdfnet_model_open(size, NULL, count));
  rift_dpdfnet_model *model = rift_dpdfnet_model_open(size, weights, count);
  // The library keeps a copy of its own: the caller's may go at once.
  memset(weights, 0, count * sizeof(float));
  rift_dpdfnet_model *other = NULL;
  if (model) {
    free(weights);
    weights = read_weights(path, &count);
    CHECK(weights);
    other = rift_dpdfnet_model_open(size, weights, count);
  }
  free(weights);
  CHECK(model && other);
  static float first[kFrames][RIFT_DPDFNET_SPECTRUM];
  float frame[RIFT_DPDFNET_SPECTRUM], raw[RIFT_DPDFNET_SPECTRUM];
  double in = 0, out = 0;
  for (int i = 0; i < kFrames; ++i) {
    spectrum(raw, i);
    memcpy(frame, raw, sizeof(frame));
#ifdef _WIN32
    int result = -1;
    unsigned changed = rift_test_call(run_for_call, model, frame, &result);
    if (changed) {
      fprintf(stderr, "DPDFNet-%d changed registers Windows keeps: %#x\n", size,
              changed);
      return 1;
    }
    CHECK(result == 0);
#else
    CHECK(rift_dpdfnet_model_run(model, frame) == 0);
#endif
    for (int j = 0; j < RIFT_DPDFNET_SPECTRUM; ++j) {
      CHECK(isfinite(frame[j]));
      in += (double)raw[j] * raw[j];
      out += (double)frame[j] * frame[j];
    }
    memcpy(first[i], frame, sizeof(frame));
    // A second model is its own: the same sound gives it the same answer.
    memcpy(frame, raw, sizeof(frame));
    CHECK(rift_dpdfnet_model_run(other, frame) == 0);
    CHECK(!memcmp(frame, first[i], sizeof(frame)));
  }
  // It is a noise filter: hiss in, much less out.
  CHECK(out < in / 10);
  // After a reset it is as newly opened, to the bit.
  rift_dpdfnet_model_reset(model);
  for (int i = 0; i < kFrames; ++i) {
    spectrum(frame, i);
    CHECK(rift_dpdfnet_model_run(model, frame) == 0);
    CHECK(!memcmp(frame, first[i], sizeof(frame)));
  }
  CHECK(rift_dpdfnet_model_run(NULL, frame) == -1);
  CHECK(rift_dpdfnet_model_run(model, NULL) == -1);
  rift_dpdfnet_model_close(model);
  rift_dpdfnet_model_close(other);
  return 0;
}

// test_model WEIGHTS_2 WEIGHTS_8: each model's weights.f32.
int main(int argc, char **argv) {
  CHECK(argc == 3);
  CHECK(rift_dpdfnet_abi() == RIFT_DPDFNET_ABI);
  float one = 0;
  CHECK(!rift_dpdfnet_model_open(3, &one, 1));
  rift_dpdfnet_model_reset(NULL);
  rift_dpdfnet_model_close(NULL);
  if (!rift_dpdfnet_model_supported()) {
    size_t count = 0;
    float *weights = read_weights(argv[1], &count);
    CHECK(weights);
    CHECK(!rift_dpdfnet_model_open(2, weights, count));
    free(weights);
    fprintf(stderr, "no AVX2 and FMA here: the models were not run\n");
    return 77;
  }
#ifdef _WIN32
  // The check itself: it must see a function that keeps nothing.
  int result = -1;
  CHECK(rift_test_call(rift_test_clobber, NULL, NULL, &result) ==
        (1u << 2 | 1u << 3 | 1u << 8 | 1u << 17));
  CHECK(result == 0);
#endif
  if (test(2, argv[1]) || test(8, argv[2])) return 1;
  printf("both models ran\n");
  return 0;
}
