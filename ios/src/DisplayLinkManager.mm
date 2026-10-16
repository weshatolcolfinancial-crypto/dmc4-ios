#import "DisplayLinkManager.h"
#import <UIKit/UIKit.h>

@interface DisplayLinkManager ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, readwrite) BOOL isProMotionActive;
@property (nonatomic, readwrite) double currentFPS;
@property (nonatomic, readwrite) BOOL isRunning;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CFTimeInterval fpsAccumulator;
@end

@implementation DisplayLinkManager

+ (instancetype)sharedManager {
    static DisplayLinkManager *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[DisplayLinkManager alloc] init];
    });
    return s_instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _targetFPS = 60;
        _isProMotionActive = NO;
        _isRunning = NO;
        _currentFPS = 60.0;
        _lastTimestamp = 0.0;
        _frameCount = 0;
        _fpsAccumulator = 0.0;
    }
    return self;
}

- (void)start {
    if (self.isRunning) return;

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLinkTick:)];

    [self applyFrameRateSettings];

    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.isRunning = YES;
    NSLog(@"[DisplayLinkManager] DisplayLink started with target FPS: %ld (ProMotion: %@)", 
          (long)self.targetFPS, self.isProMotionActive ? @"YES" : @"NO");
}

- (void)applyFrameRateSettings {
    if (!self.displayLink) return;

    if (@available(iOS 15.0, *)) {
        if (self.targetFPS >= 120) {
            // Enable Apple ProMotion 120Hz
            CAFrameRateRange range = CAFrameRateRangeMake(60.0, 120.0, 120.0);
            self.displayLink.preferredFrameRateRange = range;
            self.isProMotionActive = YES;
        } else if (self.targetFPS == 60) {
            CAFrameRateRange range = CAFrameRateRangeMake(30.0, 60.0, 60.0);
            self.displayLink.preferredFrameRateRange = range;
            self.isProMotionActive = NO;
        } else {
            CAFrameRateRange range = CAFrameRateRangeMake(15.0, 30.0, 30.0);
            self.displayLink.preferredFrameRateRange = range;
            self.isProMotionActive = NO;
        }
    } else {
        self.displayLink.preferredFramesPerSecond = self.targetFPS;
        self.isProMotionActive = (self.targetFPS >= 120);
    }
}

- (void)setTargetFramerate:(NSInteger)fps {
    _targetFPS = fps;
    [self applyFrameRateSettings];
    NSLog(@"[DisplayLinkManager] Target framerate changed to %ld FPS", (long)fps);
}

- (void)onDisplayLinkTick:(CADisplayLink *)sender {
    CFTimeInterval currentTimestamp = sender.timestamp;
    if (self.lastTimestamp == 0.0) {
        self.lastTimestamp = currentTimestamp;
        return;
    }

    CFTimeInterval dt = currentTimestamp - self.lastTimestamp;
    self.lastTimestamp = currentTimestamp;

    // Rolling FPS calculation
    self.frameCount++;
    self.fpsAccumulator += dt;
    if (self.fpsAccumulator >= 0.5) {
        self.currentFPS = (double)self.frameCount / self.fpsAccumulator;
        self.frameCount = 0;
        self.fpsAccumulator = 0.0;
    }

    if ([self.delegate respondsToSelector:@selector(displayLinkDidTickWithDeltaTime:currentFPS:)]) {
        [self.delegate displayLinkDidTickWithDeltaTime:dt currentFPS:self.currentFPS];
    }
}

- (void)pause {
    if (self.displayLink) {
        self.displayLink.paused = YES;
    }
}

- (void)resume {
    if (self.displayLink) {
        self.lastTimestamp = 0.0;
        self.displayLink.paused = NO;
    }
}

- (void)stop {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.isRunning = NO;
}

- (void)dealloc {
    [self stop];
}

@end
