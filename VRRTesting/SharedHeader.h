//
//  SharedHeader.h
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

#ifndef SharedHeader_h
#define SharedHeader_h

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
    float fParam0;
};

#endif /* SharedHeader_h */
