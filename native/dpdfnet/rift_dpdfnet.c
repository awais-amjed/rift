// Ceva's runtime behind the few functions Rift needs of it (rift_dpdfnet.h):
// a model that keeps its own state, opened on the weights in this library.
#include "rift_dpdfnet.h"

#include <stddef.h>
#include <stdlib.h>

#include "dpdfnet.h"

// weights.S: each model's weights, and where they end.
extern const float rift_dpdfnet_weights_2[], rift_dpdfnet_weights_2_end[];
extern const float rift_dpdfnet_weights_8[], rift_dpdfnet_weights_8_end[];

struct rift_dpdfnet_model {
  dpdfnet_model *model;
  dpdfnet_model_id id;
  // Everything the model keeps between frames. Ceva's runtime leaves it with
  // the caller.
  float *state;
};

int rift_dpdfnet_abi(void) { return RIFT_DPDFNET_ABI; }

int rift_dpdfnet_model_supported(void) { return dpdfnet_cpu_supported(); }

rift_dpdfnet_model *rift_dpdfnet_model_open(int size) {
  const float *weights, *end;
  if (size == DPDFNET_MODEL_2) {
    weights = rift_dpdfnet_weights_2;
    end = rift_dpdfnet_weights_2_end;
  } else if (size == DPDFNET_MODEL_8) {
    weights = rift_dpdfnet_weights_8;
    end = rift_dpdfnet_weights_8_end;
  } else {
    return NULL;
  }
  dpdfnet_model_id id = (dpdfnet_model_id)size;
  const dpdfnet_model_info *info = dpdfnet_get_model_info(id);
  // The graph is fixed code that reads the weights by offset: other weights
  // than its own are not a model.
  if (!info || info->spectrum_floats != RIFT_DPDFNET_SPECTRUM ||
      info->weight_floats != (size_t)(end - weights) ||
      !dpdfnet_cpu_supported()) {
    return NULL;
  }
  rift_dpdfnet_model *opened = calloc(1, sizeof(*opened));
  if (!opened) return NULL;
  opened->id = id;
  opened->model = dpdfnet_create(id, weights, info->weight_floats);
  opened->state = malloc(info->state_floats * sizeof(float));
  if (!opened->model || !opened->state ||
      dpdfnet_init_state(id, opened->state) != 0) {
    rift_dpdfnet_model_close(opened);
    return NULL;
  }
  return opened;
}

int rift_dpdfnet_model_run(rift_dpdfnet_model *model, float *spectrum) {
  if (!model || !spectrum) return -1;
  // In place, both: the runtime allows the spectrum and the state each to be
  // their own output.
  return dpdfnet_process(model->model, spectrum, model->state, spectrum,
                         model->state);
}

void rift_dpdfnet_model_reset(rift_dpdfnet_model *model) {
  if (model) dpdfnet_init_state(model->id, model->state);
}

void rift_dpdfnet_model_close(rift_dpdfnet_model *model) {
  if (!model) return;
  dpdfnet_destroy(model->model);
  free(model->state);
  free(model);
}
