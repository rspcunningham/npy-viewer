#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
    float2 texCoord;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             constant Vertex *vertices [[buffer(0)]]) {
    VertexOut out;
    out.position = float4(vertices[vertexID].position, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> image [[texture(0)]],
                              texture2d<float> colorMaps [[texture(1)]],
                              constant uint &mode [[buffer(0)]],
                              constant uint &colorMap [[buffer(1)]],
                              constant float2 &windowLevel [[buffer(2)]]) {
    constexpr sampler imageSampler(address::clamp_to_edge, filter::linear);
    constexpr sampler colorMapSampler(address::clamp_to_edge, filter::linear);

    float4 sample = image.sample(imageSampler, in.texCoord);
    float value = sample.r;

    if (mode == 1) {
        value = length(sample.rg);
    } else if (mode == 2) {
        constexpr float pi = 3.14159265358979323846;
        value = (atan2(sample.g, sample.r) + pi) / (2.0 * pi);
    } else if (mode == 3) {
        value = sample.r;
    } else if (mode == 4) {
        value = sample.g;
    } else if (mode == 5) {
        value = dot(sample.rg, sample.rg);
    }

    float window = max(windowLevel.x, 0.01);
    float level = windowLevel.y;
    value = (value - (level - window * 0.5)) / window;
    value = clamp(value, 0.0, 1.0);

    uint rowCount = colorMaps.get_height();
    uint row = min(colorMap, rowCount - 1);
    float rowCoord = (float(row) + 0.5) / float(rowCount);
    float3 color = colorMaps.sample(colorMapSampler, float2(value, rowCoord)).rgb;
    return float4(color, 1.0);
}
