//
//  ViewController.m
//  OC_Demo
//
//  Created by BM on 5/8/25.
//

#import "ViewController.h"
#import "OC_Demo-Swift.h" // Import the auto-generated Swift header

@interface ViewController () <UITableViewDataSource, UITableViewDelegate, EsMessengerWrapperDelegate, HuanCaptureWrapperDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.discoveredDevices = [NSMutableArray array];

    self.esMessengerWrapper = [[EsMessengerWrapper alloc] init];
    self.esMessengerWrapper.delegate = self; // Set delegate
    self.huanCaptureWrapper = [[HuanCaptureWrapper alloc] init];
    self.huanCaptureWrapper.delegate = self; // Set delegate

    [self setupUI];
    [self logMessage:@"ViewController initialized. Set EsMessengerWrapper and HuanCaptureWrapper delegates."];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat contentWidth = self.view.bounds.size.width - 40;
    CGFloat currentY = CGRectGetMaxY(self.devicesTableView.frame) + 10;

    if (self.startPublishingButton.superview && !self.startPublishingButton.hidden) {
        self.startPublishingButton.frame = CGRectMake(20, currentY, contentWidth, 40);
        currentY = CGRectGetMaxY(self.startPublishingButton.frame) + 10;
    }

    if (self.capturePreviewViewContainer.superview) {
        self.capturePreviewViewContainer.frame = CGRectMake(20, currentY, contentWidth, 200);
        UIView *preview = [self.huanCaptureWrapper getPreviewView];
        if (preview && preview.superview == self.capturePreviewViewContainer) {
            preview.frame = self.capturePreviewViewContainer.bounds;
        }
        currentY = CGRectGetMaxY(self.capturePreviewViewContainer.frame) + 10;

        if (self.switchCameraButton.superview && !self.switchCameraButton.hidden) {
            self.switchCameraButton.frame = CGRectMake(20, currentY, contentWidth, 40);
        }
    }
}

- (void)dealloc {
    [self.esMessengerWrapper stopDiscovery];
    [self.huanCaptureWrapper stopPublishing];
    NSLog(@"ViewController deallocated.");
}

- (void)setupUI {
    // Log Text View
    self.logTextView = [[UITextView alloc] initWithFrame:CGRectMake(20, 50, self.view.bounds.size.width - 40, 100)];
    self.logTextView.editable = NO;
    self.logTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.logTextView.layer.borderWidth = 1.0;
    [self.view addSubview:self.logTextView];

    // Search Button
    self.searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.searchButton.frame = CGRectMake(20, CGRectGetMaxY(self.logTextView.frame) + 10, self.view.bounds.size.width - 40, 40);
    [self.searchButton setTitle:@"Search Devices" forState:UIControlStateNormal];
    [self.searchButton addTarget:self action:@selector(searchDevicesTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.searchButton];

    // Devices Table View
    self.devicesTableView = [[UITableView alloc] initWithFrame:CGRectMake(20, CGRectGetMaxY(self.searchButton.frame) + 10, self.view.bounds.size.width - 40, 120) style:UITableViewStylePlain];
    self.devicesTableView.dataSource = self;
    self.devicesTableView.delegate = self;
    [self.devicesTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DeviceCell"];
    [self.view addSubview:self.devicesTableView];

    self.startPublishingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startPublishingButton setTitle:@"Start Publishing" forState:UIControlStateNormal];
    [self.startPublishingButton addTarget:self action:@selector(startPublishingTapped) forControlEvents:UIControlEventTouchUpInside];
    self.startPublishingButton.hidden = YES; // Initially hidden
    [self.view addSubview:self.startPublishingButton];

    self.capturePreviewViewContainer = [[UIView alloc] init];
    self.capturePreviewViewContainer.backgroundColor = [UIColor darkGrayColor];
    self.capturePreviewViewContainer.clipsToBounds = YES;
    self.capturePreviewViewContainer.frame = CGRectMake(20, 0, self.view.bounds.size.width - 40, 200);
    [self.view addSubview:self.capturePreviewViewContainer];

    [self.connectDeviceButton removeFromSuperview];
    self.connectDeviceButton = nil;
    [self.startStopCaptureButton removeFromSuperview];
    self.startStopCaptureButton = nil;

    self.switchCameraButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.switchCameraButton setTitle:@"Switch Camera" forState:UIControlStateNormal];
    [self.switchCameraButton addTarget:self action:@selector(switchCameraTapped) forControlEvents:UIControlEventTouchUpInside];
    self.switchCameraButton.hidden = YES;
    [self.view addSubview:self.switchCameraButton];
}


- (void)logMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentLog = self.logTextView.text;
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        self.logTextView.text = [NSString stringWithFormat:@"%@: %@\n%@", timestamp, message, currentLog];
    });
}

// MARK: - Actions

- (void)searchDevicesTapped {
    [self logMessage:@"Starting device discovery..."];
    [self.discoveredDevices removeAllObjects];
    [self.devicesTableView reloadData];
    self.selectedDevice = nil;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.startPublishingButton.hidden = YES;
        [self.startPublishingButton setTitle:@"Start Publishing" forState:UIControlStateNormal];
        self.switchCameraButton.hidden = YES;
        
        UIView *preview = [self.huanCaptureWrapper getPreviewView];
        [preview removeFromSuperview];
        CGRect currentPreviewFrame = self.capturePreviewViewContainer.frame;
        self.capturePreviewViewContainer.frame = CGRectMake(currentPreviewFrame.origin.x, currentPreviewFrame.origin.y, currentPreviewFrame.size.width, 0);

        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    });

    [self.esMessengerWrapper stopDiscovery];
    [self.esMessengerWrapper startDiscovery];
}

- (void)startPublishingTapped {
    if (!self.selectedDevice) {
        [self logMessage:@"No device selected."];
        return;
    }
    
    [self logMessage:@"Starting publishing..."];
    [self.huanCaptureWrapper createCaptureManagerWithTargetOCDevice:self.selectedDevice];
    
    // 立即获取并显示previewView
    UIView *preview = [self.huanCaptureWrapper getPreviewView];
    if (preview) {
        [self logMessage:@"Preview view obtained successfully."];
        [self.capturePreviewViewContainer addSubview:preview];
        preview.frame = self.capturePreviewViewContainer.bounds;
        self.switchCameraButton.hidden = NO;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    } else {
        [self logMessage:@"Failed to get preview view."];
    }
    
    [self.huanCaptureWrapper startPublishing];
    
    // 添加调试信息
    [self logMessage:@"AVCaptureSession started."];
    [self logMessage:@"WebRTC setup complete."];
}

- (void)switchCameraTapped {
    [self logMessage:@"Switching camera..."];
    [self logMessage:@"Switch camera functionality to be confirmed/implemented in HuanCaptureWrapper."];
}

// MARK: - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.discoveredDevices.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeviceCell" forIndexPath:indexPath];
    OCEsDevice *device = self.discoveredDevices[indexPath.row]; // Use OCEsDevice from Swift
    cell.textLabel.text = [NSString stringWithFormat:@"%@ (%@)", device.deviceName, device.deviceIp];
    return cell;
}

// MARK: - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.discoveredDevices.count) {
        self.selectedDevice = self.discoveredDevices[indexPath.row];
        [self logMessage:[NSString stringWithFormat:@"Device selected: %@ (%@)", self.selectedDevice.deviceName, self.selectedDevice.deviceIp]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.startPublishingButton.hidden = NO;
            [self.view setNeedsLayout]; 
            [self.view layoutIfNeeded];
        });
    } else {
        self.selectedDevice = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.startPublishingButton.hidden = YES;
            self.switchCameraButton.hidden = YES;
            // Also hide preview if a row is deselected (though typically not possible if count > 0)
            UIView *preview = [self.huanCaptureWrapper getPreviewView];
            [preview removeFromSuperview];
            CGRect currentPreviewFrame = self.capturePreviewViewContainer.frame;
            self.capturePreviewViewContainer.frame = CGRectMake(currentPreviewFrame.origin.x, currentPreviewFrame.origin.y, currentPreviewFrame.size.width, 0);
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
        });
    }
}

// MARK: - EsMessengerWrapperDelegate

- (void)onFindDevice:(OCEsDevice *)device {
    [self logMessage:[NSString stringWithFormat:@"Found device: %@ (%@)", device.deviceName, device.deviceIp]];
    BOOL deviceExists = NO;
    for (OCEsDevice *existingDevice in self.discoveredDevices) {
        if ([existingDevice.deviceIp isEqualToString:device.deviceIp] && [existingDevice.deviceName isEqualToString:device.deviceName]) {
            deviceExists = YES;
            break;
        }
    }
    if (!deviceExists) {
        [self.discoveredDevices addObject:device];
        [self.devicesTableView reloadData];
    }
}

- (void)onReceiveEvent:(OCEsEvent *)event {
}

// MARK: - HuanCaptureWrapperDelegate

- (void)huanCaptureWrapperDidStartStreaming {
    [self logMessage:@"HuanCaptureWrapper: Did start streaming."];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.startPublishingButton setTitle:@"Stop Publishing" forState:UIControlStateNormal];
        
        UIView *preview = [self.huanCaptureWrapper getPreviewView];
        if (preview) {
            [self.capturePreviewViewContainer addSubview:preview];
            self.switchCameraButton.hidden = NO;
        } else {
            [self logMessage:@"HuanCaptureWrapper: Preview view is nil after starting stream."];
            CGRect currentPreviewFrame = self.capturePreviewViewContainer.frame;
            self.capturePreviewViewContainer.frame = CGRectMake(currentPreviewFrame.origin.x, currentPreviewFrame.origin.y, currentPreviewFrame.size.width, 0);
            self.switchCameraButton.hidden = YES;
        }
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    });
}

- (void)huanCaptureWrapperDidStopStreaming {
    [self logMessage:@"HuanCaptureWrapper: Did stop streaming."];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.startPublishingButton setTitle:@"Start Publishing" forState:UIControlStateNormal];
        
        UIView *preview = [self.huanCaptureWrapper getPreviewView];
        [preview removeFromSuperview];
        
        CGRect currentPreviewFrame = self.capturePreviewViewContainer.frame;
        self.capturePreviewViewContainer.frame = CGRectMake(currentPreviewFrame.origin.x, currentPreviewFrame.origin.y, currentPreviewFrame.size.width, 0);
        self.switchCameraButton.hidden = YES;
        
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    });
}

- (void)huanCaptureWrapperDidFailWithError:(NSError *)error {
    [self logMessage:[NSString stringWithFormat:@"HuanCaptureWrapper: Did fail with error: %@", error.localizedDescription]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.startPublishingButton setTitle:@"Start Publishing" forState:UIControlStateNormal];

        UIView *preview = [self.huanCaptureWrapper getPreviewView];
        [preview removeFromSuperview];

        CGRect currentPreviewFrame = self.capturePreviewViewContainer.frame;
        self.capturePreviewViewContainer.frame = CGRectMake(currentPreviewFrame.origin.x, currentPreviewFrame.origin.y, currentPreviewFrame.size.width, 0);
        self.switchCameraButton.hidden = YES;

        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    });
}

- (void)huanCaptureWrapper:(HuanCaptureWrapper *)wrapper didUpdateConnectionState:(NSString *)state {
    [self logMessage:[NSString stringWithFormat:@"HuanCaptureWrapper: Connection state updated to: %@", state]];
}

@end
