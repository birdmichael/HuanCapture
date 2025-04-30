//
//  EsDemoApp.swift
//  EsDemo
//
//  Created by BM on 4/28/25.
//

import SwiftUI
import es_cast_client_ios

@main
struct EsDemoApp: App {
    @ObservedObject var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.showCapture {
                    ContentView(config: .init(signalingModeInput: .esMessenger(store.selectDeive!)))
                } else {
                    DeviceView()
                }
            }.environmentObject(store)
            
        }
        
    }
}

