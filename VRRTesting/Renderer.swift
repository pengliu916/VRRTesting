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
    var visualMode = VISUAL_None
    var texRTWidth = 256 {didSet{bRecreateResouce = true}}
    var texRTHeight = 256 {didSet{bRecreateResouce = true}}
    var blockSize: Int32 = 16
    var viewAspectRatio: CGFloat = 1.0
    var bDebugOutput = true
    var bRecreateResouce = true
    
    unowned var dev: MTLDevice
    let cmdQueue: MTLCommandQueue
    var psoGFX: MTLRenderPipelineState!
    var psoTileStat: MTLRenderPipelineState!
    var psoGFX_VRR: MTLRenderPipelineState
    var rpdRT: MTLRenderPassDescriptor!
    let vs: MTLFunction
    let ps: MTLFunction
    let cs_tile: MTLFunction
    let semaphore = DispatchSemaphore(value: frameBufCnt)
    var bufConst = ConstBuf()
    var texRT: MTLTexture!
    
    var bUseVRR = true
    var rateMap: MTLRasterizationRateMap!
    var rpdVRR: MTLRenderPassDescriptor!
    var bufVRR: MTLBuffer!
    var texVRR: MTLTexture!
    var texVRRWidth: Int = 16
    var texVRRHeight: Int = 16

    private var preFrameTimeStamp: CFTimeInterval = 0.0
    private var curFrameTimeStamp: CFTimeInterval = 0.0
    private var startFrameTimeStamp: CFTimeInterval = 0.0
    private var deltaTime: CFTimeInterval = 0.0
    private var elapsedTime: CFTimeInterval = 0.0
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private init() {
        guard let _dev = MTLCreateSystemDefaultDevice() else {fatalError("Failed to create MTLDevice")}
        dev = _dev
        
        if !dev.supportsRasterizationRateMap(layerCount: 1) {fatalError("Current GPU doesn't support VRR")}
        
        guard let _queue = dev.makeCommandQueue() else {fatalError("Failed to make queue")}
        cmdQueue = _queue

        guard let lib = dev.makeDefaultLibrary() else {fatalError("Failed to make lib")}
        
        vs = Renderer.makeGPUFunc(lib, name: "vs_quad")!
        ps = Renderer.makeGPUFunc(lib, name: "ps_quad")!
        cs_tile = Renderer.makeGPUFunc(lib, name: "cs_tileStat")!

        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.label = "texRT PSO"
        psoDesc.rasterSampleCount = 1
        psoDesc.vertexFunction = Renderer.makeGPUFunc(lib, name: "vs_quadGen")
        psoDesc.fragmentFunction = Renderer.makeGPUFunc(lib, name: "ps_quadGen")
        psoDesc.colorAttachments[0].pixelFormat = pixelFormat
        guard let pso = try? dev.makeRenderPipelineState(descriptor: psoDesc)
        else {fatalError("Failed to create PSO \(String(describing: psoDesc.label))")}
        psoGFX_VRR = pso
        
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
    
    private func createResource() {
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: texRTWidth, height: texRTHeight, mipmapped: false);
        texDesc.usage = [.shaderRead, .renderTarget]
        texRT = dev.makeTexture(descriptor: texDesc)!
        bufConst.i2texRTSize = vector_int2(Int32(texRTWidth), Int32(texRTHeight))
        
        rpdRT = MTLRenderPassDescriptor()
        rpdRT.colorAttachments[0].loadAction = .dontCare
        rpdRT.colorAttachments[0].storeAction = .store
        rpdRT.colorAttachments[0].texture = texRT
        
        createVRRResource()
        bDebugOutput = true
        bRecreateResouce = false
    }
    
    private func createVRRResource() {
        let vrrDesc = MTLRasterizationRateMapDescriptor()
        vrrDesc.label = "VRR Test"
        vrrDesc.screenSize = MTLSizeMake(texRTWidth, texRTHeight, 0)
        
        let zoneCounts = MTLSizeMake(4, 4, 1)
        let layerDesc = MTLRasterizationRateLayerDescriptor(sampleCount: zoneCounts)
        for row in 0..<zoneCounts.height {
            layerDesc.vertical[row] = 1.0
        }
        for column in 0..<zoneCounts.width {
            layerDesc.horizontal[column] = 1.0
        }
        layerDesc.horizontal[0] = 0.25
        layerDesc.horizontal[3] = 0.25
        layerDesc.vertical[0] = 0.25
        layerDesc.vertical[3] = 0.25

        vrrDesc.setLayer(layerDesc, at: 0)
        rateMap = dev.makeRasterizationRateMap(descriptor: vrrDesc)
        
        let texVRRSize = rateMap.physicalSize(layer: 0)
        let texDesc = MTLTextureDescriptor()
        texDesc.width = texVRRSize.width
        texDesc.height = texVRRSize.height
        texDesc.pixelFormat = pixelFormat
        texDesc.mipmapLevelCount = 1
        texDesc.usage = [.renderTarget, .shaderRead]
        texVRR = dev.makeTexture(descriptor: texDesc)
        texVRRWidth = texVRRSize.width
        texVRRHeight = texVRRSize.height
        
        bufConst.i2texVRRPhysical = SIMD2<Int32>(Int32(texDesc.width), Int32(texDesc.height))
        
        rpdVRR = MTLRenderPassDescriptor()
        rpdVRR.rasterizationRateMap = rateMap
        rpdVRR.colorAttachments[0].texture = texVRR
        rpdVRR.colorAttachments[0].loadAction = .clear
        rpdVRR.colorAttachments[0].storeAction = .store
        
        let bufSize = rateMap.parameterDataSizeAndAlign
        guard let _buf = dev.makeBuffer(length: bufSize.size, options: .storageModeShared)
        else {fatalError("Failed to create VRR buffer")}
        bufVRR = _buf
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
    
    private func makeGFXPSOs(framePixFormat: MTLPixelFormat, sampleCnt: Int) {
        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.label = "Quad GFX"
        psoDesc.rasterSampleCount = sampleCnt
        psoDesc.vertexFunction = vs
        psoDesc.fragmentFunction = ps
        psoDesc.colorAttachments[0].pixelFormat = framePixFormat
        guard let pso = try? dev.makeRenderPipelineState(descriptor: psoDesc)
        else {fatalError("Failed to create PSO Quad GFX")}
        log.info("PSO: Quad GFX created")
        psoGFX = pso
        
        let psoTileDesc = MTLTileRenderPipelineDescriptor()
        psoTileDesc.label = "Quad Tile"
        psoTileDesc.colorAttachments[0].pixelFormat = framePixFormat
        psoTileDesc.rasterSampleCount = sampleCnt
        psoTileDesc.tileFunction = cs_tile
        guard let psoTile = try? dev.makeRenderPipelineState(tileDescriptor: psoTileDesc, options: .init(rawValue: 0), reflection: nil)
        else {fatalError("Failed to create PSO Quad Tile")}
        log.info("PSO: Quad Tile created")
        psoTileStat = psoTile
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        bufConst.fViewAspectRatio = Float(size.width/size.height)
        if psoGFX == nil {
            makeGFXPSOs(framePixFormat: view.colorPixelFormat, sampleCnt: view.sampleCount)
            bDebugOutput = true
        }
    }
    
    func draw(in view: MTKView) {
        if bRecreateResouce {
            createResource()
        }
        let _useVRR = bUseVRR
        preFrameTimeStamp = curFrameTimeStamp
        curFrameTimeStamp = CACurrentMediaTime()
        deltaTime = curFrameTimeStamp - preFrameTimeStamp
        elapsedTime = curFrameTimeStamp - startFrameTimeStamp
        
        bufConst.iBlockSize = Int32(blockSize)
        bufConst.fTime = Float(elapsedTime)
        bufConst.iVisualMode = visualMode
#if os(iOS)
        bufConst.fEDR = Float((window?.screen.potentialEDRHeadroom)!)
#endif
        
        _ = semaphore.wait(timeout: .distantFuture)
        guard let cmdBuf = cmdQueue.makeCommandBuffer() else {log.error("Faild to get cmdBuf"); return}
        let semaphore = semaphore
        cmdBuf.addCompletedHandler{ [weak self] cmdBuf in
            semaphore.signal()
            guard let h = self else {return}
            if h.bDebugOutput {
                log.info("screen reso: \(h.texRTWidth)x\(h.texRTHeight) physical reso: \(h.texVRRWidth)x\(h.texVRRHeight)")
                h.bDebugOutput = false
            }
        }
        
        guard let rceRT = cmdBuf.makeRenderCommandEncoder(descriptor: _useVRR ? rpdVRR : rpdRT)
        else {log.error("Failed to get encoder from rpdVRR"); semaphore.signal(); return}

        rceRT.setRenderPipelineState(psoGFX_VRR)
        rceRT.setVertexBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rceRT.setFragmentBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rceRT.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        rceRT.setRenderPipelineState(psoTileStat)
        rceRT.dispatchThreadsPerTile(MTLSize(width: 10, height: 10, depth: 1))
        rceRT.endEncoding()
        
        guard let rpd = view.currentRenderPassDescriptor
        else {log.error("Failed to get view's rpd"); semaphore.signal(); return}
        
        guard let rce = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else {log.error("Failed to get encoder"); semaphore.signal(); return}
        
        rce.setRenderPipelineState(psoGFX)
        rce.setVertexBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rce.setFragmentBytes(&bufConst, length: MemoryLayout<ConstBuf>.size, index: 0)
        rce.setFragmentBuffer(bufVRR, offset: 0, index: 1)
        rce.setFragmentTexture(_useVRR ? texVRR : texRT, index: 0)
        rce.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        rce.endEncoding()
        
        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
        }
        
        cmdBuf.commit()
    }
}
