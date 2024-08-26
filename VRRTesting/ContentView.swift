//
//  ContentView.swift
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            InterfaceView()
                .padding(.all)
                .zIndex(1)
                .background(Color.black)
                .opacity(0.8)
                .allowsHitTesting(true)
            
            VStack {
                MetalKitView()
            }
        }
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea()
    }
}

struct InterfaceView: View {
    @State var blockSize: Float = 8
    @State var useVRR: Bool = true
    @State var visualMode = VISUAL_UVDelta
    private var inst = Renderer.shared
    
    var body: some View {
        HStack {
            Slider(value: $blockSize, in: 1 ... 1024,
                   label: {Text(String(format: "BlockSize: %.0f", blockSize)).frame(width: 120)})
            .onChange(of: blockSize) { new, old in
                blockSize = round(new)
                Renderer.shared.blockSize = Int32(blockSize)
            }
            Picker(selection: $visualMode, label: Text("Visual")) {
                Text("None").tag(VISUAL_None)
                Text("UVDelta").tag(VISUAL_UVDelta)
                Text("Block").tag(VISUAL_Block)
            }
            .frame(width: 240)
            .onChange(of: visualMode) {inst.visualMode = visualMode}
            Toggle("Use VRR", isOn: $useVRR)
                .onChange(of: useVRR) {inst.bUseVRR = useVRR}
        }
        .onAppear {
            inst.blockSize = Int32(blockSize)
            inst.bUseVRR = useVRR
            inst.visualMode = visualMode
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
