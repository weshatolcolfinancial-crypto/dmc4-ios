#import "AppDelegate.h"
#import "GameViewController.h"
#import "DisplayLinkManager.h"
#import <AVFoundation/AVFoundation.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Configure iOS Audio Session for Game Audio
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"[AppDelegate] AudioSession setup error: %@", error.localizedDescription);
    }

    // 2. Initialize UIWindow
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    GameViewController *rootVC = [[GameViewController alloc] init];
    self.window.rootViewController = rootVC;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [[DisplayLinkManager sharedManager] pause];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [[DisplayLinkManager sharedManager] resume];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [[DisplayLinkManager sharedManager] pause];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [[DisplayLinkManager sharedManager] resume];
}

@end
