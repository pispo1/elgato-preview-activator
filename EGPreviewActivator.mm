#import <Cocoa/Cocoa.h>
#include <dispatch/dispatch.h>
#import <os/log.h>  // Import logging framework
#include "ElgatoUVCDevice.h"


//#define LogError(msg, ...) os_log_error(OS_LOG_DEFAULT, "%{public}@", [NSString stringWithFormat:msg, ##__VA_ARGS__])
//#define LogInfo(msg, ...) os_log_info(OS_LOG_DEFAULT, "%{public}@", [NSString stringWithFormat:msg, ##__VA_ARGS__])
//#define LogDebug(msg, ...) os_log_debug(OS_LOG_DEFAULT, "%{public}@", [NSString stringWithFormat:msg, ##__VA_ARGS__])

#define LogError(fmt, ...) NSLog(@"ERROR: " fmt, ##__VA_ARGS__)
#define LogInfo(fmt, ...) NSLog(@"INFO: " fmt, ##__VA_ARGS__)
#define LogDebug(fmt, ...) NSLog(@"DEBUG: " fmt, ##__VA_ARGS__)

// Global variables
unsigned int width;
unsigned int height;
unsigned int rate;
NSTask *taskVideoAudio;
ElgatoUVCDevice* device  = nullptr;;

// Check if AVICapture is running
int is_avicapture_running() {
    return taskVideoAudio != nil;
}

// Launch AVI Capture
void launchAVICapture() {
    taskVideoAudio = [[NSTask alloc] init];
    taskVideoAudio.launchPath = @"./AVICapture";  // Ensure correct path to main

    NSString *videoSize = [NSString stringWithFormat:@"%ldx%ld", (long)width, (long)height];

    // Set the arguments for main
    taskVideoAudio.arguments = @[
        @"-framerate", [NSString stringWithFormat:@"%u", rate],
        @"-video_size", videoSize,
        @"-iv", @"Game Capture HD60 X", 
        @"-ia", @"Game Capture HD60 X", // Input device or stream (e.g., device number for AVFoundation)
        @"-fs" // Fullscreen
    ];
    
    // Set a termination handler
    taskVideoAudio.terminationHandler = ^(NSTask *task) {
        if (task.terminationStatus == 15) {
            // Handle the case where you explicitly terminated the task
            LogInfo(@"avicapture was terminated by the program with status 15.");
        } else {
            // Handle other termination statuses
            LogError(@"avicapture was terminated with status: %d", task.terminationStatus);
            // If task was not killed by your program, relaunch it
            LogInfo(@"Relaunching avicapture...");
            launchAVICapture(); // Recursively relaunch avicapture
        }
    };
    
    // Launch the task
    [taskVideoAudio launch];
}

void cleanupTask() {
    if (taskVideoAudio) {
        [taskVideoAudio terminate];
        taskVideoAudio = nil;  // Make sure to nil out the task after termination
    }
}

// Signal handler function
void signalHandler(int signal) {
    // Log the signal received
    LogInfo(@"Received signal %d, cleaning up...", signal);

    if(is_avicapture_running()){
        cleanupTask();
    }
    // Exit the program gracefully
    exit(signal);  // Exit the program with the same signal code
}



void executeMainTask() {
	bool active = false;
    VIDEO_STREAM_INFO videoInfo{};
	memset(&videoInfo, 0, sizeof(videoInfo));
    EGAVResult res = device->GetVideoStreamInfo(videoInfo);
    if (res.Succeeded())
    {
        if (videoInfo.vRes == 0 || videoInfo.hRes == 0) {
            if (is_avicapture_running()) {
                LogInfo(@"Killing avicapture...");
                cleanupTask();
            }
        } else {    
            if (!is_avicapture_running()) {
                LogInfo(@"Launching avicapture...");
                launchAVICapture();
            }
        }
    }
}

void setupPeriodicTask() {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              10 * NSEC_PER_SEC, // Execute every 60 seconds
                              1 * NSEC_PER_SEC); // Allow a 1-second leeway

    dispatch_source_set_event_handler(timer, ^{
        executeMainTask();
    });

    dispatch_resume(timer);
}

int main() {
    @autoreleasepool {
        // Register signal handler for SIGINT (Ctrl+C) and SIGTERM
        signal(SIGINT, signalHandler);  // Handle Ctrl+C
        signal(SIGTERM, signalHandler); // Handle termination request
        LogInfo(@"Application starting...");

        width = 2560;   // Desired resolution width
        height = 1440;  // Desired resolution height
        rate = 60;

        const EGAVDeviceID& selectedDeviceID = deviceIDHD60X; 
        std::shared_ptr<EGAVHIDInterface> hid = std::make_shared<EGAVHID>();
        EGAVResult res = hid->InitHIDInterface(selectedDeviceID);
        if (res.Failed())
        {
            LogError(@"InitHIDInterface() failed. Do you have the correct device connected?");
        }
        else
        {
            device = new ElgatoUVCDevice(hid, IsNewDeviceType(selectedDeviceID));
            
            // Set up periodic task
            setupPeriodicTask();

            // Keep the application running to respond to events
            [[NSRunLoop currentRunLoop] run];
        }
        

    }

    return 0;
}
