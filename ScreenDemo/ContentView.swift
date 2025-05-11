//
//  ContentView.swift
//  ScreenDemo
//
//  Created by BM on 5/11/25.
//

import SwiftUI
import ReplayKit
import HuanCapture
import Combine
import AVFoundation
import WebRTC

struct ContentView: View {
    @StateObject private var captureManager: HuanCaptureManager
    private let externalFrameProvider: ExternalFrameProvider
    private let config: HuanCaptureConfig
    
    private let screenRecorder = RPScreenRecorder.shared()
    @State private var isRecordingScreen = false
    @State private var counter = 0
    // 计时器用于更新屏幕上的计数器，使其在录制时可见内容变化
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()


    init() {
        let efProvider = ExternalFrameProvider.create(isLoggingEnabled: false) // 可以关闭 provider 的日志
        self.externalFrameProvider = efProvider
        // 配置HuanCapture，关闭其内部日志，根据需要设置信令模式
        let localConfig = HuanCaptureConfig(isLoggingEnabled: false, signalingModeInput: .webSocket)
        self.config = localConfig
        _captureManager = StateObject(wrappedValue: HuanCaptureManager(frameProvider: efProvider, config: localConfig))
    }

    var body: some View {
        VStack(spacing: 30) {
            Text("应用内屏幕推流")
                .font(.largeTitle)
                .padding(.top)
            
            Text("\(counter)")
                .font(.system(size: 120, weight: .bold, design: .monospaced))
                .foregroundColor(Color.orange)
                .onReceive(timer) { _ in
                    counter = (counter + 1) % 10000
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(getButtonLabel()) {
                toggleScreenCaptureAndStreaming()
            }
            .padding()
            .font(.title)
            .buttonStyle(.borderedProminent)
            .tint(isRecordingScreen ? .pink : .indigo) // 使用不同的颜色以便区分
        }
        .padding()
        .onDisappear { 
            if isRecordingScreen {
                stopScreenCapture()
            }
            if !captureManager.connectionState.isIdleOrDisconnected {
                captureManager.stopStreaming()
            }
            timer.upstream.connect().cancel()
        }
    }

    func getButtonLabel() -> String {
        return isRecordingScreen ? "停止捕捉和推流" : "开始捕捉并推流"
    }

    func toggleScreenCaptureAndStreaming() {
        if isRecordingScreen {
            stopScreenCapture()
            if !captureManager.connectionState.isIdleOrDisconnected {
                captureManager.stopStreaming()
            }
        } else {
            startScreenCapture()
            if captureManager.connectionState.isIdleOrDisconnected {
                 captureManager.startStreaming()
            }
        }
    }

    func startScreenCapture() {
        guard screenRecorder.isAvailable else {
            // 实际应用中可能需要用户提示
            return
        }

        screenRecorder.startCapture(handler: { (sampleBuffer, bufferType, error) in
            guard error == nil else {
                self.stopScreenCapture()
                if !self.captureManager.connectionState.isIdleOrDisconnected {
                    self.captureManager.stopStreaming()
                }
                return
            }

            if bufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let timestampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000_000
                self.externalFrameProvider.consumePixelBuffer(pixelBuffer, rotation: ._0, timestampNs: Int64(timestampNs))
            }
        }) { (error) in
            if error == nil {
                self.isRecordingScreen = true
            } else {
                self.isRecordingScreen = false
            }
        }
    }

    func stopScreenCapture() {
        screenRecorder.stopCapture { _ in
            self.isRecordingScreen = false
        }
    }
}

extension RTCIceConnectionState {
    var isIdleOrDisconnected: Bool {
        switch self {
        case .new, .disconnected, .failed, .closed:
            return true
        default:
            return false
        }
    }
}

#Preview {
    ContentView()
}
