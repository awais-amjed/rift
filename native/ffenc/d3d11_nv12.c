/* d3d11_nv12.c — a BGRA texture into NV12 on the GPU, for a Windows share.
 *
 * The way of it is Sunshine's (src/platform/windows/display_vram.cpp and its
 * convert_yuv420 shaders, GPL-3.0, read Nov 1 2026 at 68f637a): one pass into the
 * NV12 texture's Y plane through an R8 view, one into its UV plane at half size
 * through an R8G8 view. Written for Rift: the matrix and the four samples of a
 * far scale are nvenc_gl.c's, so a picture has the same colours on every path, and
 * the frames are FFmpeg's, compiled shaders asked of Windows' own compiler as
 * FFmpeg's vsrc_gfxcapture does. No wait on the GPU: the picture is read by this
 * device's own queue, in order, ahead of the encoder, and OBS's winrt-capture.cpp
 * lets a WGC frame go straight after queueing its copy the same way.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#define COBJMACROS
#include "d3d11_nv12.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <d3d11.h>
#include <d3dcompiler.h>
#include <windows.h>

#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
#include <libavutil/log.h>

#include "nvenc_gl_geometry.h"

// More than FFmpeg's pool grows to with one picture in the encoder at a time,
// or two at NVENC's delay of 2 and one kept for a repeat.
#define MAX_TARGETS 8

// At up to 120 pictures a second, about a second's worth, as nvenc_gl.c.
#define MAX_PASSING_FAILURES 120

typedef struct Constants {
  float corners[4][4];
  float spread[2][4];
} Constants;

typedef struct Target {
  ID3D11Texture2D* texture;
  ID3D11RenderTargetView* y;
  ID3D11RenderTargetView* uv;
} Target;

struct D3d11Nv12 {
  int width;
  int height;
  ID3D11Device* device;
  ID3D11DeviceContext* context;
  ID3D11VertexShader* vertex;
  ID3D11PixelShader* pixel_y;
  ID3D11PixelShader* pixel_uv;
  ID3D11SamplerState* sampler;
  ID3D11Buffer* constants;
  Constants written;
  int has_written;
  AVBufferRef* hw_device;
  AVBufferRef* frames;
  Target targets[MAX_TARGETS];
  int next_target;
  int passing_failures;
};

static const char SHADERS[] =
    "cbuffer Place : register(b0) {\n"
    "  float4 corner[4];\n"
    "  float4 spread[2];\n"
    "};\n"
    "Texture2D picture : register(t0);\n"
    "SamplerState linear_clamp : register(s0);\n"
    "struct Out {\n"
    "  float4 position : SV_Position;\n"
    "  float2 uv : TEXCOORD0;\n"
    "};\n"
    "Out main_vs(uint id : SV_VertexID) {\n"
    "  Out o;\n"
    "  o.uv = corner[id].xy;\n"
    "  o.position = float4((id & 1) ? 1.0 : -1.0, (id & 2) ? -1.0 : 1.0, 0.0, "
    "1.0);\n"
    "  return o;\n"
    "}\n"
    "float3 sampled(float2 uv) {\n"
    "  float2 a = spread[0].xy;\n"
    "  float2 b = spread[1].xy;\n"
    "  if (all(a == 0.0) && all(b == 0.0)) {\n"
    "    return picture.SampleLevel(linear_clamp, uv, 0).rgb;\n"
    "  }\n"
    "  return (picture.SampleLevel(linear_clamp, uv - a - b, 0).rgb +\n"
    "          picture.SampleLevel(linear_clamp, uv + a - b, 0).rgb +\n"
    "          picture.SampleLevel(linear_clamp, uv - a + b, 0).rgb +\n"
    "          picture.SampleLevel(linear_clamp, uv + a + b, 0).rgb) / 4.0;\n"
    "}\n"
    // BT.601 in limited range, as libyuv makes it and the encoder's stream
    // says (nvenc_gl.c).
    "float4 main_y(Out i) : SV_Target {\n"
    "  float3 s = sampled(i.uv);\n"
    "  return float4((16.0 + 65.481 * s.r + 128.553 * s.g + 24.966 * s.b) / "
    "255.0, 0.0, 0.0, 1.0);\n"
    "}\n"
    "float4 main_uv(Out i) : SV_Target {\n"
    "  float3 s = sampled(i.uv);\n"
    "  return float4((128.0 - 37.797 * s.r - 74.203 * s.g + 112.0 * s.b) / "
    "255.0,\n"
    "                (128.0 + 112.0 * s.r - 93.786 * s.g - 18.214 * s.b) / "
    "255.0, 0.0, 1.0);\n"
    "}\n";

static void fail(char* error, size_t error_len, const char* format, ...) {
  if (!error || error_len == 0) return;
  va_list args;
  va_start(args, format);
  vsnprintf(error, error_len, format, args);
  va_end(args);
}

typedef HRESULT(WINAPI* D3DCompileFn)(LPCVOID, SIZE_T, LPCSTR,
                                      const D3D_SHADER_MACRO*, ID3DInclude*,
                                      LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**,
                                      ID3DBlob**);

static ID3DBlob* compile(D3DCompileFn compiler, const char* entry,
                         const char* profile, char* error, size_t error_len) {
  ID3DBlob* code = NULL;
  ID3DBlob* message = NULL;
  HRESULT hr =
      compiler(SHADERS, sizeof(SHADERS) - 1, NULL, NULL, NULL, entry, profile,
               D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &message);
  if (FAILED(hr)) {
    fail(error, error_len, "shader %s: 0x%08lx %s", entry, hr,
         message ? (const char*)ID3D10Blob_GetBufferPointer(message) : "");
  }
  if (message) ID3D10Blob_Release(message);
  return code;
}

static int open_shaders(D3d11Nv12* path, char* error, size_t error_len) {
  // Kept loaded: only ever one, from Windows' own folder.
  static HMODULE module;
  if (!module) {
    module = LoadLibraryExW(L"d3dcompiler_47.dll", NULL,
                            LOAD_LIBRARY_SEARCH_SYSTEM32);
  }
  D3DCompileFn compiler =
      module ? (D3DCompileFn)(void*)GetProcAddress(module, "D3DCompile") : NULL;
  if (!compiler) {
    fail(error, error_len, "no D3DCompile");
    return -1;
  }
  ID3DBlob* vertex = compile(compiler, "main_vs", "vs_4_0", error, error_len);
  ID3DBlob* y = compile(compiler, "main_y", "ps_4_0", error, error_len);
  ID3DBlob* uv = compile(compiler, "main_uv", "ps_4_0", error, error_len);
  int result = -1;
  if (vertex && y && uv &&
      SUCCEEDED(ID3D11Device_CreateVertexShader(
          path->device, ID3D10Blob_GetBufferPointer(vertex),
          ID3D10Blob_GetBufferSize(vertex), NULL, &path->vertex)) &&
      SUCCEEDED(ID3D11Device_CreatePixelShader(
          path->device, ID3D10Blob_GetBufferPointer(y),
          ID3D10Blob_GetBufferSize(y), NULL, &path->pixel_y)) &&
      SUCCEEDED(ID3D11Device_CreatePixelShader(
          path->device, ID3D10Blob_GetBufferPointer(uv),
          ID3D10Blob_GetBufferSize(uv), NULL, &path->pixel_uv))) {
    result = 0;
  } else if (error && !error[0]) {
    fail(error, error_len, "the shaders did not load");
  }
  if (vertex) ID3D10Blob_Release(vertex);
  if (y) ID3D10Blob_Release(y);
  if (uv) ID3D10Blob_Release(uv);
  return result;
}

// FFmpeg's device and NV12 frames on the caller's device. A pool size of 0 has
// FFmpeg make one texture a frame as they are wanted, and use them again:
// creating an array with a render target's flags failed on both GPUs of an Iris
// Xe and RTX 3070 Ti laptop (E_INVALIDARG, Nov 1 2026, scale_d3d11).
static int open_frames(D3d11Nv12* path, char* error, size_t error_len) {
  path->hw_device = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_D3D11VA);
  if (!path->hw_device) {
    fail(error, error_len, "no D3D11 device for FFmpeg");
    return -1;
  }
  AVHWDeviceContext* device = (AVHWDeviceContext*)path->hw_device->data;
  AVD3D11VADeviceContext* hw = device->hwctx;
  hw->device = path->device;
  ID3D11Device_AddRef(path->device);
  int err = av_hwdevice_ctx_init(path->hw_device);
  if (err < 0) {
    fail(error, error_len, "FFmpeg refused the D3D11 device (%d)", err);
    return err;
  }
  path->frames = av_hwframe_ctx_alloc(path->hw_device);
  if (!path->frames) {
    fail(error, error_len, "no NV12 frames");
    return -1;
  }
  AVHWFramesContext* frames = (AVHWFramesContext*)path->frames->data;
  frames->format = AV_PIX_FMT_D3D11;
  frames->sw_format = AV_PIX_FMT_NV12;
  frames->width = path->width;
  frames->height = path->height;
  frames->initial_pool_size = 0;
  AVD3D11VAFramesContext* hw_frames = frames->hwctx;
  hw_frames->BindFlags = D3D11_BIND_RENDER_TARGET;
  err = av_hwframe_ctx_init(path->frames);
  if (err < 0) {
    fail(error, error_len, "FFmpeg made no NV12 frames that size (%d)", err);
  }
  return err;
}

D3d11Nv12* d3d11_nv12_open(void* device, int width, int height, char* error,
                           size_t error_len) {
  D3d11Nv12* path = calloc(1, sizeof(*path));
  if (!path) {
    fail(error, error_len, "out of memory");
    return NULL;
  }
  path->width = width;
  path->height = height;
  path->device = device;
  ID3D11Device_AddRef(path->device);
  ID3D11Device_GetImmediateContext(path->device, &path->context);

  D3D11_SAMPLER_DESC sampler = {
      .Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR,
      .AddressU = D3D11_TEXTURE_ADDRESS_CLAMP,
      .AddressV = D3D11_TEXTURE_ADDRESS_CLAMP,
      .AddressW = D3D11_TEXTURE_ADDRESS_CLAMP,
      .ComparisonFunc = D3D11_COMPARISON_NEVER,
      .MaxLOD = D3D11_FLOAT32_MAX,
  };
  D3D11_BUFFER_DESC constants = {
      .ByteWidth = sizeof(Constants),
      .Usage = D3D11_USAGE_DYNAMIC,
      .BindFlags = D3D11_BIND_CONSTANT_BUFFER,
      .CPUAccessFlags = D3D11_CPU_ACCESS_WRITE,
  };
  if (open_shaders(path, error, error_len) < 0 ||
      FAILED(ID3D11Device_CreateSamplerState(path->device, &sampler,
                                             &path->sampler)) ||
      FAILED(ID3D11Device_CreateBuffer(path->device, &constants, NULL,
                                       &path->constants)) ||
      open_frames(path, error, error_len) < 0) {
    if (error && !error[0]) fail(error, error_len, "D3D11 refused a resource");
    d3d11_nv12_free(&path);
    return NULL;
  }
  return path;
}

AVBufferRef* d3d11_nv12_frames(D3d11Nv12* path) { return path->frames; }

// The two views of one of FFmpeg's textures, kept: it hands the same few back
// for the whole share.
static Target* target_of(D3d11Nv12* path, ID3D11Texture2D* texture) {
  for (int i = 0; i < MAX_TARGETS; i++) {
    if (path->targets[i].texture == texture) return &path->targets[i];
  }
  Target* target = &path->targets[path->next_target];
  path->next_target = (path->next_target + 1) % MAX_TARGETS;
  if (target->y) ID3D11RenderTargetView_Release(target->y);
  if (target->uv) ID3D11RenderTargetView_Release(target->uv);
  memset(target, 0, sizeof(*target));

  D3D11_RENDER_TARGET_VIEW_DESC view = {
      .Format = DXGI_FORMAT_R8_UNORM,
      .ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D,
  };
  ID3D11RenderTargetView* y = NULL;
  ID3D11RenderTargetView* uv = NULL;
  if (FAILED(ID3D11Device_CreateRenderTargetView(
          path->device, (ID3D11Resource*)texture, &view, &y))) {
    return NULL;
  }
  view.Format = DXGI_FORMAT_R8G8_UNORM;
  if (FAILED(ID3D11Device_CreateRenderTargetView(
          path->device, (ID3D11Resource*)texture, &view, &uv))) {
    ID3D11RenderTargetView_Release(y);
    return NULL;
  }
  target->texture = texture;
  target->y = y;
  target->uv = uv;
  return target;
}

static int write_constants(D3d11Nv12* path, const Constants* constants) {
  if (path->has_written &&
      memcmp(&path->written, constants, sizeof(*constants)) == 0) {
    return 0;
  }
  D3D11_MAPPED_SUBRESOURCE mapped;
  if (FAILED(ID3D11DeviceContext_Map(path->context,
                                     (ID3D11Resource*)path->constants, 0,
                                     D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
    return -1;
  }
  memcpy(mapped.pData, constants, sizeof(*constants));
  ID3D11DeviceContext_Unmap(path->context, (ID3D11Resource*)path->constants, 0);
  path->written = *constants;
  path->has_written = 1;
  return 0;
}

static void draw_plane(D3d11Nv12* path, ID3D11RenderTargetView* view,
                       ID3D11PixelShader* shader, RiftRect rect) {
  D3D11_VIEWPORT viewport = {
      .TopLeftX = (float)rect.x,
      .TopLeftY = (float)rect.y,
      .Width = (float)rect.width,
      .Height = (float)rect.height,
      .MaxDepth = 1.0f,
  };
  ID3D11DeviceContext_RSSetViewports(path->context, 1, &viewport);
  ID3D11DeviceContext_OMSetRenderTargets(path->context, 1, &view, NULL);
  ID3D11DeviceContext_PSSetShader(path->context, shader, NULL, 0);
  ID3D11DeviceContext_Draw(path->context, 4, 0);
}

// Draws the picture into `frame`. 0, or the D3D11 result that stopped it.
static HRESULT draw(D3d11Nv12* path, ID3D11Texture2D* texture, int source_width,
                    int source_height, const RiftRect* place, AVFrame* frame) {
  D3D11_TEXTURE2D_DESC desc;
  ID3D11Texture2D_GetDesc(texture, &desc);
  float u = (float)source_width / (float)desc.Width;
  float v = (float)source_height / (float)desc.Height;
  if (u > 1.0f) u = 1.0f;
  if (v > 1.0f) v = 1.0f;
  int place_width = place ? place->width : path->width;
  int place_height = place ? place->height : path->height;
  float corners[4][2] = {{0, 0}, {u, 0}, {0, v}, {u, v}};
  int scale_far = source_width > place_width * 2 || source_height > place_height * 2;
  float offsets[2][2];
  nvenc_gl_spread(corners, place_width, place_height, scale_far, offsets);
  Constants constants;
  memset(&constants, 0, sizeof(constants));
  for (int i = 0; i < 4; i++) {
    constants.corners[i][0] = corners[i][0];
    constants.corners[i][1] = corners[i][1];
  }
  for (int i = 0; i < 2; i++) {
    constants.spread[i][0] = offsets[i][0];
    constants.spread[i][1] = offsets[i][1];
  }

  Target* target = target_of(path, (ID3D11Texture2D*)frame->data[0]);
  if (!target) return E_FAIL;
  ID3D11ShaderResourceView* source = NULL;
  HRESULT hr = ID3D11Device_CreateShaderResourceView(
      path->device, (ID3D11Resource*)texture, NULL, &source);
  if (FAILED(hr)) return hr;
  if (write_constants(path, &constants) < 0) {
    ID3D11ShaderResourceView_Release(source);
    return E_FAIL;
  }

  if (place) {
    static const float BLACK_Y[4] = {16.0f / 255.0f, 0, 0, 1};
    static const float BLACK_UV[4] = {128.0f / 255.0f, 128.0f / 255.0f, 0, 1};
    ID3D11DeviceContext_ClearRenderTargetView(path->context, target->y, BLACK_Y);
    ID3D11DeviceContext_ClearRenderTargetView(path->context, target->uv,
                                              BLACK_UV);
  }
  ID3D11DeviceContext* c = path->context;
  ID3D11DeviceContext_IASetInputLayout(c, NULL);
  ID3D11DeviceContext_IASetPrimitiveTopology(
      c, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
  ID3D11DeviceContext_VSSetShader(c, path->vertex, NULL, 0);
  ID3D11DeviceContext_VSSetConstantBuffers(c, 0, 1, &path->constants);
  ID3D11DeviceContext_PSSetConstantBuffers(c, 0, 1, &path->constants);
  ID3D11DeviceContext_PSSetSamplers(c, 0, 1, &path->sampler);
  ID3D11DeviceContext_PSSetShaderResources(c, 0, 1, &source);

  draw_plane(path, target->y, path->pixel_y,
             nvenc_gl_plane_rect(place, path->width, path->height, 0));
  draw_plane(path, target->uv, path->pixel_uv,
             nvenc_gl_plane_rect(place, path->width, path->height, 1));

  // Let go of both, so neither is bound when the encoder takes the frame.
  ID3D11ShaderResourceView* no_source = NULL;
  ID3D11DeviceContext_PSSetShaderResources(c, 0, 1, &no_source);
  ID3D11DeviceContext_OMSetRenderTargets(c, 0, NULL, NULL);
  ID3D11DeviceContext_Flush(c);
  ID3D11ShaderResourceView_Release(source);
  return ID3D11Device_GetDeviceRemovedReason(path->device);
}

int d3d11_nv12_run(D3d11Nv12* path, void* texture, int source_width,
                   int source_height, const RiftRect* place, AVFrame* frame) {
  int err = av_hwframe_get_buffer(path->frames, frame, 0);
  if (err < 0) return err;
  HRESULT hr = draw(path, texture, source_width, source_height, place, frame);
  if (SUCCEEDED(hr)) {
    path->passing_failures = 0;
    return 0;
  }
  av_frame_unref(frame);
  HRESULT removed = ID3D11Device_GetDeviceRemovedReason(path->device);
  if (FAILED(removed)) {
    av_log(NULL, AV_LOG_WARNING, "d3d11: the GPU is gone: 0x%08lx\n", removed);
    return AVERROR_EXTERNAL;
  }
  if (++path->passing_failures > MAX_PASSING_FAILURES) {
    av_log(NULL, AV_LOG_WARNING, "d3d11: pictures keep failing: 0x%08lx\n", hr);
    return AVERROR_EXTERNAL;
  }
  return AVERROR(EAGAIN);
}

void d3d11_nv12_free(D3d11Nv12** at) {
  D3d11Nv12* path = *at;
  if (!path) return;
  *at = NULL;
  for (int i = 0; i < MAX_TARGETS; i++) {
    if (path->targets[i].y) ID3D11RenderTargetView_Release(path->targets[i].y);
    if (path->targets[i].uv) {
      ID3D11RenderTargetView_Release(path->targets[i].uv);
    }
  }
  av_buffer_unref(&path->frames);
  av_buffer_unref(&path->hw_device);
  if (path->constants) ID3D11Buffer_Release(path->constants);
  if (path->sampler) ID3D11SamplerState_Release(path->sampler);
  if (path->pixel_uv) ID3D11PixelShader_Release(path->pixel_uv);
  if (path->pixel_y) ID3D11PixelShader_Release(path->pixel_y);
  if (path->vertex) ID3D11VertexShader_Release(path->vertex);
  if (path->context) ID3D11DeviceContext_Release(path->context);
  if (path->device) ID3D11Device_Release(path->device);
  free(path);
}
