// 把一張像素圖畫成畫面上的一個長方形，放大時取最近的像素，不做平滑處理。
#include <metal_stdlib>
using namespace metal;

/// 和 Swift 的 `SpriteQuad` 對應：單位都是螢幕實體像素，左上角為原點。
struct SpriteQuad {
    float2 origin;
    float2 size;
    float2 viewport;
};

struct SpriteVertexOut {
    float4 position [[position]];
    float2 uv;
};

/// 四個角依序是左上、右上、左下、右下，用三角形帶畫成長方形。
vertex SpriteVertexOut spriteVertex(uint vid [[vertex_id]], constant SpriteQuad &quad [[buffer(0)]]) {
    float2 corner = float2(float(vid & 1), float(vid >> 1));
    float2 pixel = quad.origin + corner * quad.size;
    float2 ndc = float2(pixel.x / quad.viewport.x * 2.0 - 1.0, 1.0 - pixel.y / quad.viewport.y * 2.0);
    SpriteVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = corner;
    return out;
}

fragment float4 spriteFragment(SpriteVertexOut in [[stage_in]],
                               texture2d<float> image [[texture(0)]],
                               sampler nearest [[sampler(0)]]) {
    return image.sample(nearest, in.uv);
}
