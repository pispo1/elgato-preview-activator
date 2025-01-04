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
NSTask *task;
ElgatoUVCDevice* device  = nullptr;;

// Check if FFPlay is running
int is_ffplay_running() {
    return task != nil;
}

// Launch FFPlay
void launchFFPlay() {
    task = [[NSTask alloc] init];
    task.launchPath = @"./ffplay";  // Ensure correct path to ffplay

    NSString *videoSize = [NSString stringWithFormat:@"%ldx%ld", (long)width, (long)height];

    // Set the arguments for ffplay
    task.arguments = @[
        @"-f", @"avfoundation",
        @"-framerate", @"60",
        @"-video_size", videoSize,
        @"-pixel_format", @"nv12",
        @"-fast",
        @"-i", @"1", // Input device or stream (e.g., device number for AVFoundation)
        @"-noautorotate",
        @"-an",
        @"-avioflags", @"direct",
        @"-fflags", @"nobuffer",
        @"-flags", @"low_delay",
        @"-sync", @"ext",
        @"-vf", @"setpts=0",
        @"-tune", @"zerolatency",
        @"-v", @"quiet",
        @"-fs" // Fullscreen
    ];
    
    // Set a termination handler
    task.terminationHandler = ^(NSTask *task) {
        if (task.terminationStatus == 123) {
            // Handle the case where you explicitly terminated the task
            LogInfo(@"ffplay was terminated by the program with status 123.");
        } else {
            // Handle other termination statuses
            LogError(@"ffplay was terminated with status: %d", task.terminationStatus);
            // If task was not killed by your program, relaunch it
            LogInfo(@"Relaunching ffplay...");
            launchFFPlay(); // Recursively relaunch ffplay
        }
    };
    
    // Launch the task
    [task launch];
}

void cleanupTask() {
    if (task) {
        [task terminate];
        task = nil;  // Make sure to nil out the task after termination
    }
}

// Signal handler function
void signalHandler(int signal) {
    // Log the signal received
    LogInfo(@"Received signal %d, cleaning up...", signal);

    if(is_ffplay_running()){
        cleanupTask();
    }
    // Exit the program gracefully
    exit(signal);  // Exit the program with the same signal code
}



void executeMainTask() {
	bool active = false;
    EGAVResult res = device->IsInputActive(&active);
    if (res.Succeeded())
    {
        if (!active) {
            LogDebug(@"NOT Active");

            if (is_ffplay_running()) {
                cleanupTask();
            }
        } else {    
            LogDebug(@"ACTIVE");

            if (!is_ffplay_running()) {
                LogInfo(@"Launching ffplay...");
                launchFFPlay();
            }
        }
    }
}

void setupPeriodicTask() {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              60 * NSEC_PER_SEC, // Execute every 60 seconds
                              1 * NSEC_PER_SEC); // Allow a 1-second leeway

    dispatch_source_set_event_handler(timer, ^{
        LogDebug(@"Execute Main (TIMER)");
        executeMainTask();
    });

    dispatch_resume(timer);
}

static void wakeNotificationCallback(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    LogDebug(@"Execute Main (WAKEUP)");
    executeMainTask(); // Call your existing task function
}

void setupWakeNotification() {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
                                    NULL,
                                    wakeNotificationCallback,
                                    CFSTR("com.apple.screensaver.didWake"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

int main() {
    @autoreleasepool {
        // Register signal handler for SIGINT (Ctrl+C) and SIGTERM
        signal(SIGINT, signalHandler);  // Handle Ctrl+C
        signal(SIGTERM, signalHandler); // Handle termination request
        LogInfo(@"Application starting...");

        width = 2560;   // Desired resolution width
        height = 1440;  // Desired resolution height

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
            
            // Set up wake notification and periodic task
            setupWakeNotification();
            setupPeriodicTask();

            // Keep the application running to respond to events
            [[NSRunLoop currentRunLoop] run];
        }
        

    }

    return 0;
}
