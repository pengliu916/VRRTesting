//
//  Renderer.swift
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

import MetalKit
import SwiftUI
import OSLog

fileprivate let log = Logger(subsystem: "Render", category: "VRRTesting")
fileprivate let frameBufCnt = 3
fileprivate let pixelFormat = MTLPixelFormat.rgba16Float

class Renderer: MTKView, MTKViewDelegate {
    static let shared = Renderer()
    var texRTWidth = 1024
    var texRTHeight = 1024
    var blockSize: Int = 16
    var viewAspectRatio: CGFloat = 1.0
    
    unowned var dev: MTLDevice
    let cmdQueue: MTLCommandQueue
    var psoGFX: MTLRenderPipelineState!
    var psoGFX_VRR: MTLRenderPipelineState
    var rpdVRR: MTLRenderPassDescriptor
    let vs: MTLFunction
    let ps: MTLFunction
    let semaphore = DispatchSemaphore(value: frameBufCnt)
    var bufConst = ConstBuf()
    var texRT: MTLTexture
    
    private var preFrameTimeStamp: CFTimeInterval = 0.0
    private var curFrameTimeStamp: CFTimeInterval = 0.0
    private var startFrameTimeStamp: CFTimeInterval = 0.0
    private var deltaTime: CFTimeInterval = 0.0
    private var elapsedTime: CFTimeInterval = 0.0
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private init() {
        guard let _dev = MTLCreateSystemDefaultDevice() else {fatalError("failed to create MTLDevice")}
        dev = _dev
        
        guard let _queue = dev.makeCommandQueue() else {fatalError("failed to make queue")}
        cmdQueue = _queue

        guard let lib = dev.makeDefaultLibrary() else {fatalError("failed to make lib")}
        
        vs = Renderer.makeGPUFunc(lib, name: "vs_quad")!
        ps = Renderer.makeGPUFunc(lib, name: "ps_quad")!

        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.label = "texRT PSO"
        psoDesc.rasterSampleCount = 1
        psoDesc.vertexFunction = Renderer.makeGPUFunc(lib, name: "vs_quadGen")
        psoDesc.fragmentFunction = Renderer.makeGPUFunc(lib, name: "ps_quadGen")
        psoDesc.colorAttachments[0].pixelFormat = pixelFormat
        guard let pso = try? dev.makeRenderPipelineState(descriptor: psoDesc)
        else {fatalError("Failed to create PSO \(String(describing: psoDesc.label))")}
        psoGFX_VRR = pso
        
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: texRTWidth, height: texRTHeight, mipmapped: false);
        texDesc.usage = [.shaderRead, .renderTarget]
        texRT = dev.makeTexture(descriptor: texDesc)!
        bufConst.ui2texRTSize = vector_uint2(UInt32(texRTWidth), UInt32(texRTHeight))
        
        rpdVRR = MTLRenderPassDescriptor()
        rpdVRR.colorAttachments[0].loadAction = .dontCare
        rpdVRR.colorAttachments[0].storeAction = .store
        rpdVRR.colorAttachments[0].texture = texRT
        
        super.init(frame: CGRect(), device: dev)
        
        self.delegate = self
        self.device = dev
        self.colorPixelFormat = pixelFormat
        
        // enable EDR support
        let caMtlLayer = self.layer as! CAMetalLayer
        caMtlLayer.wantsExtendedDynamicRangeContent = true
        caMtlLayer.pixelFormat = pixelFormat
        let name =  CGColorSpace.extendedLinearDisplayP3
        let colorSpace = CGColorSpace(name: name)
        caMtlLayer.colorspace = colorSpace
        
        startFrameTimeStamp = CACurrentMediaTime()
#if os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(self.updateEDR), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.updateEDR), name: NSWindow.didMoveNotification, object: nil)
#endif
        
    }
    
#if os(macOS)
    @objc
    func updateEDR(_ notification: Notification) {
        bufConst.fEDR = Float(NSApplication.shared.mainWindow?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0)
    }
#endif
    
    private static func makeGPUFunc(_ lib: MTLLibrary, name: String) -> MTLFunction? {
        guard let bolb = lib.makeFunction(name: name)
        else {log.error("Failed to create \(name)"); return nil}
        log.info("MTLFunction \(name) created")
        return bolb
    }
    
    private func makeGFXPSO(label: String,
                            vs: MTLFunction, ps: MTLFunction,
                            framePixFormat: MTLPixelFormat, sampleCnt: Int) -> MTLRenderPipelineState {
        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.label = label
        psoDesc.rasterSampleCount = sampleCnt
        psoDesc.vertexFunction = vs
        psoDesc.fragmentFunction = ps
        psoDesc.colorAttachments[0].pixelFormat = framePixFormat
        guard let pso = try? dev.makeRenderPipelineState(descriptor: psoDesc)
        else {fatalError("Failed to create PSO \(label)")}
        log.info("PSO: \(label) created")
        return pso
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        bufConst.fViewAspectRatio = Float(size.width/size.height)
        if psoGFX == nil {
            psoGFX = makeGFXPSO(label: "Quad", vs: vs, ps: ps, framePixFormat: view.colorPixelFormat, sampleCnt: view.sampleCount)
        }
    }
    
    func draw(in view: MTKView) {
        preFrameTimeStamp = curFrameTimeStamp
        curFrameTimeStamp = CACurrentMediaTime()
        deltaTime = curFrameTimeStamp - preFrameTimeStamp
        elapsedTime = curFrameTimeStamp - startFrameTimeStamp
        
        bufConst.uiBlockSize = uint(blockSize)
        bufConst.fTime = Float(elapsedTime)
#if os(iOS)
        bufConst.fEDR = Float((window?.screen.potentialEDRHeadroom)!)
#endif
        
        _ = semaphore.wait(timeout: .distantFuture)
        guard let cmdBuf = cmdQueue.makeCommandBuffer() else {log.error("Faild to get cmdBuf"); return}
        let semaphore = semaphore
        cmdBuf.addCompletedHandler{ cmdBuf in
            semaphore.signal()
        }
        
        guard let rceRT = cmdBuf.makeRenderCommandEncoder(descriptor: rpdVRR)
        else {log.error("Failed to get encoder from rpdVRR"); semaphore.signal(); return}

        rceRT.setRenderPipelineState(psoGFX_VRR)
        rceRT.setVertexBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rceRT.setFragmentBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rceRT.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        rceRT.endEncoding()
        
        guard let rpd = view.currentRenderPassDescriptor
        else {log.error("Failed to get view's rpd"); semaphore.signal(); return}
        
        guard let rce = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else {log.error("Failed to get encoder"); semaphore.signal(); return}
        
        rce.setRenderPipelineState(psoGFX)
        rce.setVertexBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rce.setFragmentBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rce.setFragmentTexture(texRT, index: 0)
        rce.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        rce.endEncoding()
        
        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
        }
        
        cmdBuf.commit()
    }
}
