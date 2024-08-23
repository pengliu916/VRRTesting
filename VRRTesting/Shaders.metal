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
    return out;
}

fragment float4 ps_quad(ColorInOut in [[stage_in]],
                        constant ConstBuf& cParams [[buffer(0)]])
{
    if (any(in.f2UV >= 1.0)) { return 0.0;} // outside of the image, set to black
    float3 f3Col = 0.5 + 0.5 * cos(cParams.fTime + in.f2UV.xyx + float3(0, 2, 4) * cParams.fParam0);
    return float4(f3Col * cParams.fEDR, 1.0);
}
