//
//  MetalKitView.swift
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

import SwiftUI
import MetalKit

struct MetalKitView {
    func makeCoordinator() -> Renderer {
        return Renderer.shared
    }
    
    func makeMTKView(_ context: MetalKitView.Context) -> MTKView {
        return Renderer.shared
    }
}

#if os(macOS)
extension MetalKitView : NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        return makeMTKView(context)
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
    }
}
#endif

#if os(iOS)
extension MetalKitView : UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        return makeMTKView(context)
    }
    
    func updateUIView(_ nsView: MTKView, context: Context) {
    }
}
#endif
