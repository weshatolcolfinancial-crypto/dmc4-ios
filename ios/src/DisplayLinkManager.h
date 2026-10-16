#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@protocol DisplayLinkManagerDelegate <NSObject>
- (void)displayLinkDidTickWithDeltaTime:(CFTimeInterval)dt currentFPS:(double)fps;
@end

@interface DisplayLinkManager : NSObject

@property (nonatomic, weak) id<DisplayLinkManagerDelegate> delegate;
@property (nonatomic, assign) NSInteger targetFPS; // 30, 60, or 120 (ProMotion)
@property (nonatomic, readonly) BOOL isProMotionActive;
@property (nonatomic, readonly) double currentFPS;
@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedManager;

- (void)start;
- (void)stop;
- (void)pause;
- (void)resume;

- (void)setTargetFramerate:(NSInteger)fps;

@end
