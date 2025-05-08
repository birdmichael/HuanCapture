//
//  ViewController.h
//  OC_Demo
//
//  Created by BM on 5/8/25.
//

#import <UIKit/UIKit.h>
#import "OC_Demo-Swift.h" // Import Swift bridging header for EsDevice, delegates

// EsMessengerWrapper and HuanCaptureWrapper are Swift classes exposed to Obj-C via OC_Demo-Swift.h
// EsDevice is also a Swift class from the same header.

@interface ViewController : UIViewController <EsMessengerWrapperDelegate, HuanCaptureWrapperDelegate>

@property (nonatomic, strong) EsMessengerWrapper *esMessengerWrapper;
@property (nonatomic, strong) HuanCaptureWrapper *huanCaptureWrapper;

@property (nonatomic, strong) UIView *capturePreviewViewContainer; // Renamed for clarity, this will hold the preview from HuanCapture
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UITableView *devicesTableView;
@property (nonatomic, strong) NSMutableArray<OCEsDevice *> *discoveredDevices; // Use OCEsDevice from Swift
@property (nonatomic, strong) OCEsDevice *selectedDevice; // To store the selected device

@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIButton *connectDeviceButton; // To connect to the selected device for capture
@property (nonatomic, strong) UIButton *startStopCaptureButton;
@property (nonatomic, strong) UIButton *switchCameraButton;
@property (nonatomic, strong) UIButton *startPublishingButton; // Button to start publishing, appears after device selection
// @property (nonatomic, strong) UISegmentedControl *deviceSelectionSegmentedControl; // Or use UITableView

@end

