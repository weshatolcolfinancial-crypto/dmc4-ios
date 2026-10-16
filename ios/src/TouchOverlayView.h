#pragma once

#import <UIKit/UIKit.h>

// Xbox 360 Virtual Controller State
struct VirtualGamepadState {
    uint16_t buttons;       // Bitmask of XINPUT_GAMEPAD_* buttons
    uint8_t leftTrigger;    // 0 to 255
    uint8_t rightTrigger;   // 0 to 255
    int16_t thumbLX;        // -32768 to 32767
    int16_t thumbLY;        // -32768 to 32767
    int16_t thumbRX;        // -32768 to 32767
    int16_t thumbRY;        // -32768 to 32767
};

// XInput Button Bitmasks
#define XINPUT_GAMEPAD_DPAD_UP          0x0001
#define XINPUT_GAMEPAD_DPAD_DOWN        0x0002
#define XINPUT_GAMEPAD_DPAD_LEFT        0x0004
#define XINPUT_GAMEPAD_DPAD_RIGHT       0x0008
#define XINPUT_GAMEPAD_START            0x0010
#define XINPUT_GAMEPAD_BACK             0x0020
#define XINPUT_GAMEPAD_LEFT_THUMB       0x0040
#define XINPUT_GAMEPAD_RIGHT_THUMB      0x0080
#define XINPUT_GAMEPAD_LEFT_SHOULDER    0x0100
#define XINPUT_GAMEPAD_RIGHT_SHOULDER   0x0200
#define XINPUT_GAMEPAD_A                0x1000
#define XINPUT_GAMEPAD_B                0x2000
#define XINPUT_GAMEPAD_X                0x4000
#define XINPUT_GAMEPAD_Y                0x8000

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
