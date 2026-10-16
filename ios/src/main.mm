#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "DMCBootTrace.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        // Initialize unbuffered boot.txt and stdout/stderr redirection to dmc4.log
        dmc4::boot::InitializeLogging();
        dmc4::boot::Trace("main(): Initializing UIApplicationMain");

        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
