import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// Shader source as a Swift string literal.
//
// Adopted from the working Pac-Man port (docs/METAL-VS-PACMAN.md): no bundle
// resource, no file lookup, no runtime path that can silently load the wrong
// thing. The varyings are deliberately limited to `position`, `color` and `uv`,
// because a larger interpolated struct produced a zero alpha on the fragment
// side on this platform and made straight-alpha blending discard every pixel.
//
// All geometry is triangulated on the CPU by `VertexCanvas`, so the vertex
// function is the simplest possible: transform two floats and pass them through.

public enum MetalShaderSource {
    public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        packed_float2 position;
        packed_float4 color;
        packed_float2 uv;
    };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
        float2 uv;
    };

    struct Uniforms {
        float2 viewportSize;
    };

    vertex VertexOut vertex_main(const device VertexIn *vertices [[buffer(0)]],
                                 constant Uniforms &uniforms [[buffer(1)]],
                                 uint vertexID [[vertex_id]]) {
        VertexIn input = vertices[vertexID];
        float2 ndc = float2((input.position.x / uniforms.viewportSize.x) * 2.0 - 1.0,
                            1.0 - (input.position.y / uniforms.viewportSize.y) * 2.0);
        VertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.color = float4(input.color);
        out.uv = float2(input.uv);
        return out;
    }

    fragment float4 fragment_solid(VertexOut in [[stage_in]]) {
        return in.color;
    }

    fragment float4 fragment_textured(VertexOut in [[stage_in]],
                                      texture2d<float> texture [[texture(0)]]) {
        constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
        return texture.sample(nearest, in.uv) * in.color;
    }
    """
}
