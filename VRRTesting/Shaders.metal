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
    
    float4 f4Col = 0.0;
    switch (cb.iVisualMode) {
        case VISUAL_UVDelta: {
            float2 f2PixelPos = in.f2UV * float2(cb.i2texRTSize);
            float2 f2Rate = float2(dfdx(f2PixelPos.x), dfdy(f2PixelPos.y));
            f4Col.rg = f2Rate;
        }; break;
        case VISUAL_Block: {
            uint2 ui2BlockID = uint2(in.f2UV * float2(cb.i2texRTSize)) / cb.iBlockSize;
            if (ui2BlockID.x % 2 == ui2BlockID.y % 2)
                f4Col = 0.6;
        }; break;
        case VISUAL_RowColumn: {
            float2 f2ColRow = in.f2UV * float2(cb.i2texRTSize) + 0.5;
            float2 f2Rate = float2(dfdx(f2ColRow.x), dfdy(f2ColRow.y));
            f4Col = float4(f2Rate, float2(f2ColRow));
        }; break;
    }
    
    return float4(f4Col);
}

//====================================================================
// tile shaders for stats
//====================================================================
struct ColorData {
    float4 f4RGB [[color(0)]];
};

kernel void
cs_tileStat(imageblock<ColorData, imageblock_layout_implicit> imgblk,
            constant ConstBuf& cb [[buffer(0)]],
            constant rasterization_rate_map_data &vrrData [[buffer(1)]],
            device atomic_float* afpOutput [[buffer(2)]],
            threadgroup atomic_uint* tgauipOutput [[threadgroup(0)]],
            threadgroup float2* tgf2pTemp [[threadgroup(1)]],
            ushort usThreadID_TG [[thread_index_in_threadgroup]],
            ushort2 us2ThreadID_TG [[thread_position_in_threadgroup]],
            uint2 ui2GridID [[thread_position_in_grid]])
{
    bool bActive = all(ui2GridID < uint2(cb.i2ActiveSize));
    
    if (cb.bVRR) {
        // compute the vrr mapping from one thread in each threadgroup
        if (usThreadID_TG == 0) {
            rasterization_rate_map_decoder decoder(vrrData);
            tgf2pTemp[0] = decoder.map_physical_to_screen_coordinates(cb.f2DebugInput * float2(cb.i2ActiveSize));
            atomic_store_explicit(&afpOutput[BufIDX_Debug0], tgf2pTemp[0].x, memory_order_relaxed);
            atomic_store_explicit(&afpOutput[BufIDX_Debug1], tgf2pTemp[0].y, memory_order_relaxed);
        }
        
        if (usThreadID_TG < BufOutput_ElementCnt)
            atomic_store_explicit(&tgauipOutput[usThreadID_TG], 0, memory_order_relaxed);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        
        // debug visual write
        ColorData colData = imgblk.read(us2ThreadID_TG);
        float2 f2UV = float2(ui2GridID) / float2(cb.i2ActiveSize);
        float2 f2UV_VRR = float2(tgf2pTemp[0]) / float2(cb.i2texRTSize);
        if (distance(cb.f2DebugInput, f2UV) < 0.005) colData.f4RGB = float4(1, 0, 0, 0);
        if (distance(f2UV_VRR, f2UV) < 0.005) colData.f4RGB = float4(0, 1, 0, 0);
        imgblk.write(colData, us2ThreadID_TG);
    }
    
    // gather data in threadgroup(tile)
    if (bActive) {
        if (ui2GridID.y == 0) {
            atomic_fetch_add_explicit(&tgauipOutput[BufIDX_TotalPhysicalRow], 1, memory_order_relaxed);
        }
        if (ui2GridID.x == 0) {
            atomic_fetch_add_explicit(&tgauipOutput[BufIDX_TotalPhysicalCol], 1, memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&tgauipOutput[BufIDX_SumPhysicalPixel], 1, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // gather data cross threadgroup(tile)
    if (usThreadID_TG < BufOutput_ElementCnt) {
        uint uiVal = atomic_load_explicit(&tgauipOutput[usThreadID_TG], memory_order_relaxed);
        atomic_fetch_add_explicit(&afpOutput[usThreadID_TG], uiVal, memory_order_relaxed);
    }
}
