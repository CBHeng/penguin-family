// 箱庭的兩種畫法（ADR 0007）：
// - 貼圖：一張圖貼到畫面上的四個角（可以轉動、縮放）。向量部件用線性取樣加 mipmap，像素圖取最近的像素。
// - 多邊形：箱庭的牆、地板、家具，頂點自帶顏色；邊緣靠多重取樣抗鋸齒。
#include <metal_stdlib>
using namespace metal;

/// 和 Swift 的 `QuadUniforms` 對應：四個角依序是左上、右上、左下、右下，單位是螢幕實體像素，左上角為原點。
struct QuadUniforms {
    float2 corners[4];
    float2 viewport;
};

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

static float4 toClip(float2 pixel, float2 viewport) {
    return float4(pixel.x / viewport.x * 2.0 - 1.0, 1.0 - pixel.y / viewport.y * 2.0, 0.0, 1.0);
}

/// 用三角形帶畫成四邊形。
vertex QuadOut quadVertex(uint vid [[vertex_id]], constant QuadUniforms &quad [[buffer(0)]]) {
    QuadOut out;
    out.position = toClip(quad.corners[vid], quad.viewport);
    out.uv = float2(float(vid & 1), float(vid >> 1));
    return out;
}

/// 圖的顏色已經乘過透明度。
fragment float4 quadFragment(QuadOut in [[stage_in]],
                             texture2d<float> image [[texture(0)]],
                             sampler imageSampler [[sampler(0)]]) {
    return image.sample(imageSampler, in.uv);
}

/// 和 Swift 的 `PolygonVertex` 對應：位置是箱庭的單位，顏色已經乘過透明度。
struct PolygonVertex {
    float2 position;
    float4 color;
};

/// 和 Swift 的 `PolygonUniforms` 對應：畫面左上角對著箱庭哪一點（單位）、畫面大小（實體像素）、每單位幾個實體像素。
struct PolygonUniforms {
    float2 topLeft;
    float2 viewport;
    float devicePerUnit;
};

struct PolygonOut {
    float4 position [[position]];
    float4 color;
};

vertex PolygonOut polygonVertex(uint vid [[vertex_id]],
                                const device PolygonVertex *vertices [[buffer(0)]],
                                constant PolygonUniforms &u [[buffer(1)]]) {
    PolygonOut out;
    out.position = toClip((vertices[vid].position - u.topLeft) * u.devicePerUnit, u.viewport);
    out.color = vertices[vid].color;
    return out;
}

fragment float4 polygonFragment(PolygonOut in [[stage_in]]) {
    return in.color;
}
