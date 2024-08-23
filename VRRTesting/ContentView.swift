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
    
    var body: some View {
        HStack {
            Slider(value: $blockSize, in: 2 ... 64,
                   label: {Text(String(format: "BlockSize: %.0f", blockSize)).frame(width: 120)})
            .onChange(of: blockSize) { new, old in
                blockSize = round(new)
                Renderer.shared.blockSize = Int(blockSize)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
