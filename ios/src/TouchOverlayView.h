#pragma once

#import <UIKit/UIKit.h>
#import "virtual_gamepad.h"

@protocol TouchOverlayViewDelegate <NSObject>
- (void)touchOverlayDidChangeGamepadState:(const VirtualGamepadState *)state;
- (void)touchOverlayDidPressPause;
- (void)touchOverlayDidPressSettings;
@end

@interface TouchOverlayView : UIView

@property (nonatomic, weak) id<TouchOverlayViewDelegate> delegate;
@property (nonatomic, assign) BOOL controlsHidden;
@property (nonatomic, assign) CGFloat controlsOpacity; // default 0.85

- (const VirtualGamepadState *)currentGamepadState;
- (void)resetGamepadState;
- (void)updateFPSDisplay:(double)fps isProMotion:(BOOL)isProMotion;

@end
