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
    @State var param0: Float = 0.5
    
    var body: some View {
        HStack {
            Slider(value: $param0, in: 0.2 ... 1.0,
                   label: {Text(String(format: "Param0: %.2f", param0)).frame(width: 120)})
            .onChange(of: param0) { new, old in
                Renderer.shared.param0 = new
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
