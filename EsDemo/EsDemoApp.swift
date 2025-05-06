//
//  EsDemoApp.swift
//  EsDemo
//
//  Created by BM on 4/28/25.
//

import SwiftUI
import es_cast_client_ios
import HuanCapture

@main
struct EsDemoApp: App {
    @ObservedObject var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.showCapture {
                    ContentView(device: store.selectDeive!)
                } else {
                    DeviceView()
                }
            }.environmentObject(store)
            
        }
        
    }
}

