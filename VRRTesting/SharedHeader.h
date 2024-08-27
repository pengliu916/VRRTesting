//
//  SharedHeader.h
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

#ifndef SharedHeader_h
#define SharedHeader_h

#define VISUAL_None                0
#define VISUAL_UVDelta             1
#define VISUAL_Block               2
#define VISUAL_RowColumn           3

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
    int iVisualMode;
};

#endif /* SharedHeader_h */
