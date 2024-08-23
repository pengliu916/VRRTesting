//
//  VRRTestingApp.swift
//  VRRTesting
//
//  Created by Peng Liu on 8/23/24.
//

import SwiftUI

@main
struct VRRTestingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
#if os(macOS)
                .onDisappear{NSApplication.shared.terminate(self)}
#else
                .onAppear{UIApplication.shared.isIdleTimerDisabled = true}
#endif
        }
#if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
#endif
    }
}
