import WebRTC
import AVFoundation
import UIKit

public protocol VideoFrameProviderDelegate: AnyObject {
    func videoFrameProvider(_ provider: VideoFrameProvider, didCapture videoFrame: RTCVideoFrame)
    func videoFrameProvider(_ provider: VideoFrameProvider, didEncounterError error: Error)
    func videoFrameProvider(_ provider: VideoFrameProvider, didUpdateCameraPosition position: AVCaptureDevice.Position)
    func videoFrameProvider(_ provider: VideoFrameProvider, didUpdateCameraType type: CameraType)
    func videoFrameProvider(_ provider: VideoFrameProvider, didUpdateAvailableBackCameraTypes types: [CameraType])
    func videoFrameProvider(_ provider: VideoFrameProvider, didUpdatePreviewMirrored mirrored: Bool)
}

public protocol VideoFrameProvider: AnyObject {
    var delegate: VideoFrameProviderDelegate? { get set }
    var isRunning: Bool { get }

    func startProviding()
    func stopProviding()
}

public protocol CameraControlProvider: VideoFrameProvider {
    var currentCameraPosition: AVCaptureDevice.Position { get }
    var currentCameraType: CameraType { get }
    var availableBackCameraTypes: [CameraType] { get }
    var deviceOrientation: UIDeviceOrientation { get set }
    var isPreviewMirrored: Bool { get }

    func switchCamera()
    func switchToBackCameraType(_ type: CameraType) -> CameraType?
    func switchBackCameraType() -> CameraType?
    func setPreviewMirrored(_ mirrored: Bool)
} 