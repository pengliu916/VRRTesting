//
//  Shaders.metal
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

#include <metal_stdlib>
#include <simd/simd.h>

#include "SharedHeader.h"

using namespace metal;

constexpr sampler smpLinear(mip_filter::linear,
                            mag_filter::linear,
                            min_filter::linear,
                            s_address::clamp_to_zero,
                            t_address::clamp_to_zero,
                            r_address::clamp_to_zero);

typedef struct
{
    float4 f4Pos [[position]];
    float2 f2UV;
} ColorInOut;

//====================================================================
// shaders for mono quad rendering
//====================================================================
vertex ColorInOut vs_quad(uint uVertID [[vertex_id]],
                          constant ConstBuf& cParams [[buffer(0)]])
{
    ColorInOut out;
    out.f2UV = float2(uint2(uVertID, uVertID << 1) & 2);
    out.f4Pos = float4(mix(float2(-1,1), float2(1,-1), out.f2UV), 0, 1);
    out.f4Pos.y *= cParams.fViewAspectRatio;
    out.f4Pos.y /= float(cParams.i2texRTSize.x) / float(cParams.i2texRTSize.y);
    return out;
}

fragment float4 ps_quad(ColorInOut in [[stage_in]],
                        texture2d<float, access::sample> texRT [[texture(0)]],
                        constant ConstBuf& cParams [[buffer(0)]])
{
    if (any(in.f2UV >= 1.0)) { return 0.0;} // outside of the image, set to black
    return pow(texRT.sample(smpLinear, in.f2UV), 2.2);
}


//====================================================================
// shaders for generate the source texture
//====================================================================
vertex ColorInOut vs_quadGen(uint uVertID [[vertex_id]],
                             constant ConstBuf& cParams [[buffer(0)]])
{
    ColorInOut out;
    out.f2UV = float2(uint2(uVertID, uVertID << 1) & 2);
    out.f4Pos = float4(mix(float2(-1,1), float2(1,-1), out.f2UV), 0, 1);
    return out;
}

fragment float4 ps_quadGen(ColorInOut in [[stage_in]],
                           constant ConstBuf& cb [[buffer(0)]],
                           constant rasterization_rate_map_data &vrrData [[buffer(1)]])
{
//    uint2 ui2XY = uint2(round(in.f2UV * float2(cb.i2texVRRPhysical)));
//    rasterization_rate_map_decoder decoder(vrrData);
//    ui2XY = decoder.map_screen_to_physical_coordinates(ui2XY, 0);
    
    float3 f3Col = 0.0;
    switch (cb.iVisualMode) {
        case VISUAL_UVDelta: {
            float2 f2PixelPos = in.f2UV * float2(cb.i2texRTSize);
            float2 f2Rate = float2(dfdx(f2PixelPos.x), dfdy(f2PixelPos.y));
            f3Col.rg = f2Rate;
        }; break;
        case VISUAL_Block: {
            uint2 ui2BlockID = uint2(in.f2UV * float2(cb.i2texRTSize)) / cb.iBlockSize;
            if (ui2BlockID.x % 2 == ui2BlockID.y % 2)
                f3Col = 0.6;
        }
    }
    
    return float4(f3Col, 1.0);
}
