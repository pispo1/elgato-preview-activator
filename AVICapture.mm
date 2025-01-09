#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#include <iostream>

IOPMAssertionID assertionID = 0;

// Prevent Sleep
void preventSleep() {
    IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, CFSTR("AVICapture Preventing Sleep"), &assertionID);
}

// Allow Sleep
void allowSleep() {
    IOPMAssertionRelease(assertionID);
}

// Delegate interface for application and window management
@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTimer *hideCursorTimer;

@property NSInteger framerate;
@property (strong) NSString *videoSize;
@property (strong) NSString *inputVideoDevice;
@property (strong) NSString *inputAudioDevice;
@property BOOL fullscreen;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect screenFrame = [[NSScreen mainScreen] frame];

    // Create the main application window
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1920, 1080)
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:@"Video and Audio Capture"];
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    [self.window setDelegate:self];
    [self.window setFrame:screenFrame display:YES];

    // Create and assign the window controller
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:self.window];
    [windowController showWindow:self.window];

    // Set up the capture session
    BOOL setupResult = [self setupCaptureSessionWithFramerate:self.framerate
                                  videoSize:self.videoSize
                           inputVideoDevice:self.inputVideoDevice
                           inputAudioDevice:self.inputAudioDevice];

    if(!setupResult){
        [NSApplication.sharedApplication terminate:nil];  
    }

    // Enter fullscreen mode if requested
    if (self.fullscreen) {
        [self.window toggleFullScreen:nil];
    }
}

- (void)viewDidMoveToWindow {
    [self resetTrackingArea];
}

- (void)windowDidResize:(NSNotification *)notification {
    [self resetTrackingArea];
}

- (void)resetTrackingArea {
    for (NSTrackingArea *area in self.window.contentView.trackingAreas) {
        [self.window.contentView removeTrackingArea:area];
    }
    
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.window.contentView.bounds
                                                                options:(NSTrackingActiveAlways |
                                                                         NSTrackingMouseMoved |
                                                                         NSTrackingInVisibleRect)
                                                                  owner:self
                                                               userInfo:nil];
    [self.window.contentView addTrackingArea:trackingArea];
}

// Method triggered when the mouse moves
- (void)mouseMoved:(NSEvent *)event {
    [NSCursor unhide]; // Show the mouse pointer
    [self resetCursorHideTimer];
}

- (void)mouseEntered:(NSEvent *)event {
}

- (void)mouseExited:(NSEvent *)event {
}

// Reset the timer to hide the mouse cursor
- (void)resetCursorHideTimer {
    if (self.hideCursorTimer) {
        [self.hideCursorTimer invalidate];
    }
    self.hideCursorTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 // 3 seconds of inactivity
                                                            target:self
                                                          selector:@selector(hideCursor)
                                                          userInfo:nil
                                                           repeats:NO];
}

// Hide the mouse pointer
- (void)hideCursor {
    [NSCursor hide];
}

// Clean up resources when the window closes
- (void)windowWillClose:(NSNotification *)notification {
    [self.hideCursorTimer invalidate];
    self.hideCursorTimer = nil;
    [NSCursor unhide]; // Ensure the cursor is visible when the app exits
}


- (void)sessionRuntimeError:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog(@"Capture session runtime error: %@", error.localizedDescription);

    [NSApplication.sharedApplication terminate:nil];  
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    // Optionally perform any cleanup before the window closes
    [NSApplication.sharedApplication terminate:nil];  // Close the app when the window is closed
    return YES;  // Allow the window to close
}

// Method to set up the capture session with given parameters
- (BOOL)setupCaptureSessionWithFramerate:(NSInteger)framerate
                                videoSize:(NSString *)videoSize
                         inputVideoDevice:(NSString *)inputVideoDevice
                         inputAudioDevice:(NSString *)inputAudioDevice {

    NSInteger width;
    NSInteger height;
    NSArray *components = [videoSize componentsSeparatedByString:@"x"];

    if (components.count == 2) {
        width = [components[0] integerValue];
        height = [components[1] integerValue];
    } else {
        std::cerr << "Invalid resolution format: " << videoSize << std::endl;
        return FALSE;
    }

    // Initialize a capture session
    NSString *desiredVideoDeviceName = inputVideoDevice;
    NSString *desiredAudioDeviceName = inputAudioDevice;

    // Initialize a capture session
    AVCaptureSession *captureSession = [[AVCaptureSession alloc] init];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(sessionRuntimeError:)
                                             name:AVCaptureSessionRuntimeErrorNotification
                                           object:captureSession];

    // List all available video capture devices
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    if (videoDevices.count == 0) {
        std::cerr << "No video capture devices found!" << std::endl;
        return FALSE;
    }

    AVCaptureDevice *videoDevice = nil;
    
    // Iterate over the devices and find the one with the matching name
    for (AVCaptureDevice *device in videoDevices) {
        NSString *deviceName = device.localizedName;
        if ([deviceName isEqualToString:desiredVideoDeviceName]) {
            videoDevice = device;
            NSLog(@"Found video device: %@", deviceName);
            break;
        }
    }
    
    // Check if the device was found
    if (!videoDevice) {
        std::cerr << "Video device not found: " << desiredVideoDeviceName << std::endl;
        return FALSE;
    }

    // Set the resolution and frame rate
    NSError* error = nil;
    if ([videoDevice lockForConfiguration:&error]) {
        // Set the resolution (e.g., 1920x1080)
        NSArray *formats = videoDevice.formats;
        for (AVCaptureDeviceFormat *format in formats) {
            CMFormatDescriptionRef formatDescription = format.formatDescription;
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            FourCharCode pixelFormat = CMFormatDescriptionGetMediaSubType(formatDescription);
            
            if (dimensions.width == width && dimensions.height == height && pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                NSLog(@"Choosing format:  %@", videoSize);
                [videoDevice setActiveFormat:format];
                break;
            }
        }

        // Set the frame rate to 25
        CMTime preferredRate = CMTimeMake(1, 60); // 25
        
        // Check if the frame rate is supported on the selected format
        for (AVCaptureDeviceFormat *format in videoDevice.formats) {
            NSArray *frameRates = format.videoSupportedFrameRateRanges;
            for (AVFrameRateRange *range in frameRates) {
                if (CMTIME_COMPARE_INLINE(preferredRate, >=, range.minFrameDuration) &&
                    CMTIME_COMPARE_INLINE(preferredRate, <=, range.maxFrameDuration)) {
                    [videoDevice setActiveVideoMinFrameDuration:preferredRate];
                    [videoDevice setActiveVideoMaxFrameDuration:preferredRate];
                    break;
                }
            }
        }

        [videoDevice unlockForConfiguration];
    } else {
        std::cerr << "Failed to lock video device configuration." << std::endl;
        return FALSE;
    }

    // Set up the video input
    AVCaptureDeviceInput* videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error) {
        std::cerr << "Failed to get video device input: " << error.localizedDescription.UTF8String << std::endl;
        return FALSE;
    }

    if (![captureSession canAddInput:videoInput]) {
        std::cerr << "Cannot add video input to capture session." << std::endl;
        return FALSE;
    }
    [captureSession addInput:videoInput];

    // List available audio devices
    NSArray *audioDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if (audioDevices.count == 0) {
        std::cerr << "No audio capture devices found!" << std::endl;
        return FALSE;
    }

    AVCaptureDevice *audioDevice = nil;

    for (AVCaptureDevice *device in audioDevices) {
        if ([device.localizedName isEqualToString:desiredAudioDeviceName]) {
            audioDevice = device;
            NSLog(@"Found audio device: %@", device.localizedName);
            break;
        }
    }

    if (!audioDevice) {
        std::cerr <<  "Audio device not found: " << desiredAudioDeviceName << std::endl;
        return FALSE;
    }

    AVCaptureDeviceInput* audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if (error || ![captureSession canAddInput:audioInput]) {
        std::cerr << "Failed to set up audio input: " << (error ? error.localizedDescription.UTF8String : "Unknown error") << std::endl;
        return FALSE;
    }
    [captureSession addInput:audioInput];

    // Configure the video output for NV12 partial range and Rec. 709
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.videoSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)//,
        //(NSString *)kCVImageBufferYCbCrMatrixKey : (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
    };
    
    if ([captureSession canAddOutput:videoOutput]) {
        [captureSession addOutput:videoOutput];
    } else {
        NSLog(@"Cannot add video output.");
        return FALSE;
    }
    
    [captureSession commitConfiguration];

    // Configure video preview
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    // Attach the preview layer to the window's content view
    NSView *contentView = [self.window contentView];
    [previewLayer setFrame:contentView.bounds];
    [contentView setLayer:previewLayer];
    [contentView setWantsLayer:YES];

    // Start the capture session
    [captureSession startRunning];
    return TRUE;
}

@end

// Command-line argument parsing
void captureAndPreviewVideoAndAudio(NSInteger framerate, NSString *videoSize, NSString *inputVideoDevice, NSString *inputAudioDevice, BOOL fullscreen) {
    NSApplication *app = [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    delegate.framerate = framerate;
    delegate.videoSize = videoSize;
    delegate.inputVideoDevice = inputVideoDevice;
    delegate.inputAudioDevice = inputAudioDevice;
    delegate.fullscreen = fullscreen;
    [app setDelegate:delegate];
    [app run];
}

int main(int argc, const char * argv[]) {
    preventSleep();

    NSInteger framerate = 25;
    NSString *videoSize = @"1920x1080";
    NSString *inputVideoDevice = @"Game Capture HD60 X";
    NSString *inputAudioDevice = @"Game Capture HD60 X";
    BOOL fullscreen = NO;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-framerate") == 0 && i + 1 < argc) {
            framerate = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-video_size") == 0 && i + 1 < argc) {
            videoSize = [NSString stringWithUTF8String:argv[++i]];
        } else if (strcmp(argv[i], "-iv") == 0 && i + 1 < argc) {
            inputVideoDevice = [NSString stringWithUTF8String:argv[++i]];
        } else if (strcmp(argv[i], "-ia") == 0 && i + 1 < argc) {
            inputAudioDevice = [NSString stringWithUTF8String:argv[++i]];
        } else if (strcmp(argv[i], "-fs") == 0) {
            fullscreen = YES;
        }
    }

    captureAndPreviewVideoAndAudio(framerate, videoSize, inputVideoDevice, inputAudioDevice, fullscreen);

    allowSleep();
    return 0;
}
