// The picture's colour from one slice of a GPU decoder's NV12 texture array
// (StreamDraw, phase B), drawn where it lies: Y through an R8 view of the
// slice, interleaved U and V through an R8G8 view of the same slice. The
// colour sums are stream_draw_ps.hlsl's, by the matrix and range the stream
// says.
Texture2DArray ty : register(t0);
Texture2DArray tuv : register(t1);
SamplerState linear_clamp : register(s0);

cbuffer Colour : register(b0) {
  float4 from_y;
  float4 from_u;
  float4 from_v;
  float4 black;
};

// The picture's part of the slice, which the decoder codes larger (1088 lines
// for 1080): xy scales the target's coordinates into it, and zw is as far as
// a chroma sample may reach, so the coded rows past the picture never bleed
// into its last row.
cbuffer Place : register(b1) {
  float4 place;
};

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD) : SV_Target {
  float2 at = uv * place.xy;
  float y = ty.Sample(linear_clamp, float3(at, 0)).r;
  float2 c = tuv.Sample(linear_clamp, float3(min(at, place.zw), 0)).rg;
  float3 yuv = float3(y, c) - black.rgb;
  float3 rgb = from_y.rgb * yuv.x + from_u.rgb * yuv.y + from_v.rgb * yuv.z;
  return float4(saturate(rgb), 1);
}
