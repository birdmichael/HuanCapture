import Foundation
import es_cast_client_ios
import HuanCapture
import UIKit

@objc public class OCEsDevice: NSObject {
    @objc public let deviceName: String
    @objc public let deviceIp: String
    let originalDevice: EsDevice

    init(esDevice: EsDevice) {
        self.deviceName = esDevice.deviceName
        self.deviceIp = esDevice.deviceIp
        self.originalDevice = esDevice
        super.init()
    }
}

@objc public class OCEsEvent: NSObject {
    let originalEvent: EsEvent

    init(esEvent: EsEvent) {
        self.originalEvent = esEvent
        super.init()
    }
}

@objc public protocol EsMessengerWrapperDelegate: AnyObject {
    func onFindDevice(_ device: OCEsDevice)
    func onReceiveEvent(_ event: OCEsEvent)
}

@objc public class EsMessengerWrapper: NSObject, MessengerCallback {

    @objc public weak var delegate: EsMessengerWrapperDelegate?

    @objc public override init() {
        super.init()
        EsMessenger.shared.addDelegate(self)
    }

    deinit {
        EsMessenger.shared.removeDelegate(self)
    }

    // MARK: - MessengerCallback Conformance

    public func onFindDevice(_ device: EsDevice) {
        let ocDevice = OCEsDevice(esDevice: device)
        delegate?.onFindDevice(ocDevice)
    }

    public func onReceiveEvent(_ event: EsEvent) {
        let ocEvent = OCEsEvent(esEvent: event)
        self.delegate?.onReceiveEvent(ocEvent)
    }

    @objc public func startDiscovery() {
        EsMessenger.shared.startDeviceSearch()
    }

    @objc public func stopDiscovery() {
        EsMessenger.shared.stop()
    }

    @objc public func sendCommand(toDevice ocDevice: OCEsDevice, actionName: String, args: [String: Any]?) {
        let esAction = EsAction.makeCustom(name: actionName)
        if let arguments = args {
            esAction.args(arguments)
        }
        EsMessenger.shared.sendDeviceCommand(device: ocDevice.originalDevice, action: esAction)
    }
}


@objc public protocol HuanCaptureWrapperDelegate: AnyObject {
    func huanCaptureWrapperDidStartStreaming()
    func huanCaptureWrapperDidStopStreaming()
    func huanCaptureWrapperDidFail(withError error: Error)
    func huanCaptureWrapper(didUpdateConnectionState state: String) 
}

@objc public class HuanCaptureWrapper: NSObject {
    private var huanCaptureManager: HuanCaptureManager?
    @objc public weak var delegate: HuanCaptureWrapperDelegate?

    @objc public override init() {
        super.init()
    }

    deinit {
        huanCaptureManager?.stopStreaming()
        huanCaptureManager = nil
    }
    @objc public func createCaptureManager(targetOCDevice: OCEsDevice) {
        if huanCaptureManager != nil {
            huanCaptureManager?.stopStreaming()
            huanCaptureManager = nil
        }
        self.huanCaptureManager = HuanCaptureManager(config: .init(signalingModeInput: .esMessenger(targetOCDevice.originalDevice)))
    }

    @objc public func startPublishing() {
        huanCaptureManager!.startStreaming()
    }

    @objc public func stopPublishing() {
        guard let manager = huanCaptureManager else {
            return
        }
        manager.stopStreaming()
    }

    @objc public func getPreviewView() -> UIView? {
        guard let manager = huanCaptureManager else {
            return nil
        }
        return manager.previewView
    }
}
