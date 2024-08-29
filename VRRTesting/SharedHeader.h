//
//  SharedHeader.h
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

#ifndef SharedHeader_h
#define SharedHeader_h

#define VISUAL_None                 0
#define VISUAL_UVDelta              1
#define VISUAL_Block                2
#define VISUAL_RowColumn            3

#define BufIDX_TotalPhysicalRow     0
#define BufIDX_TotalPhysicalCol     1
#define BufIDX_TotalScreenRow       2
#define BufIDX_TotalScreenCol       3
#define BufIDX_SumScreenPixel       4
#define BufIDX_SumPhysicalPixel     5
#define BufIDX_Debug0               6
#define BufIDX_Debug1               7
#define BufOutput_ElementCnt        8 // this must be multiple of 4

#define AtomicUintScaler            1000

#ifdef __METAL_VERSION__
#define CONST constant const
#else
#import <Foundation/Foundation.h>

#define CONST const
#endif

#include <simd/simd.h>

struct ConstBuf {
    float fViewAspectRatio;
    float fTime;
    float fEDR;
    int iBlockSize;
    
    vector_int2 i2texRTSize;
    vector_int2 i2texVRRPhysical;
    vector_int2 i2ActiveSize;
    vector_float2 f2DebugInput;
    
    int iVisualMode;
    bool bVRR;
};

#endif /* SharedHeader_h */
