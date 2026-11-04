// One triangle over the whole target (StreamDraw), with the picture's
// coordinates: (0, 0) at the top left, so row 0 of the planes is the top of
// the texture, which is how Flutter reads a D3D texture.
struct Out {
  float4 position : SV_Position;
  float2 uv : TEXCOORD;
};

Out main(uint id : SV_VertexID) {
  Out o;
  o.uv = float2((id << 1) & 2, id & 2);
  o.position = float4(o.uv * float2(2, -2) + float2(-1, 1), 0, 1);
  return o;
}
