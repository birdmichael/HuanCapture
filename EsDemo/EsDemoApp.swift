//
//  EsDemoApp.swift
//  EsDemo
//
//  Created by BM on 4/28/25.
//

import es_cast_client_ios
import HuanCapture
import SwiftUI

@main
struct EsDemoApp: App {
    @ObservedObject var store = Store()
    var body: some Scene {
        WindowGroup {
            Group {
                DeviceView()
            }.environmentObject(store)
        }
    }
}
