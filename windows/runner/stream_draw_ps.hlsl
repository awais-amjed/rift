// The picture's colour from I420's three planes (StreamDraw), by the matrix and
// range it was coded with: Y, U and V less black's, each times what it adds to
// red, green and blue. The sums are linux/runner/stream_texture.cc's Colour.
Texture2D ty : register(t0);
Texture2D tu : register(t1);
Texture2D tv : register(t2);
SamplerState linear_clamp : register(s0);

cbuffer Colour : register(b0) {
  float4 from_y;
  float4 from_u;
  float4 from_v;
  float4 black;
};

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD) : SV_Target {
  float3 yuv = float3(ty.Sample(linear_clamp, uv).r,
                      tu.Sample(linear_clamp, uv).r,
                      tv.Sample(linear_clamp, uv).r) - black.rgb;
  float3 rgb = from_y.rgb * yuv.x + from_u.rgb * yuv.y + from_v.rgb * yuv.z;
  return float4(saturate(rgb), 1);
}
