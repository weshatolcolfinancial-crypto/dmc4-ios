#import "TouchOverlayView.h"

typedef NS_ENUM(NSInteger, TouchElement) {
    TouchElementNone = 0,
    TouchElementLeftStick,
    TouchElementRightStick,
    TouchElementBtnA,
    TouchElementBtnB,
    TouchElementBtnX,
    TouchElementBtnY,
    TouchElementBtnLB,
    TouchElementBtnRB,
    TouchElementBtnLT,
    TouchElementBtnRT,
    TouchElementBtnL3,
    TouchElementBtnR3,
    TouchElementDpadUp,
    TouchElementDpadDown,
    TouchElementDpadLeft,
    TouchElementDpadRight,
    TouchElementBtnPause,
    TouchElementBtnSettings
};

@interface TouchOverlayView () {
    VirtualGamepadState _state;
    NSMutableDictionary<NSValue *, NSNumber *> *_activeTouches;
    UIImpactFeedbackGenerator *_hapticFeedback;
    
    // Joystick positioning
    CGPoint _defaultLeftStickCenter;
    CGPoint _leftStickCenter;
    CGFloat _leftStickRadius;
    CGPoint _leftStickThumbPos;
    BOOL _isLeftStickActive;
    
    CGPoint _rightStickCenter;
    CGFloat _rightStickRadius;
    CGPoint _rightStickThumbPos;
    BOOL _isRightStickActive;
    
    // Action button frames
    CGRect _btnAFrame;
    CGRect _btnBFrame;
    CGRect _btnXFrame;
    CGRect _btnYFrame;
    
    // Shoulders & Triggers
    CGRect _btnRBFrame; // Lock-On
    CGRect _btnLBFrame; // Devil Trigger
    CGRect _btnRTFrame;
    CGRect _btnLTFrame;
    CGRect _btnL3Frame;
    CGRect _btnR3Frame;
    
    // D-Pad
    CGRect _dpadBounds;
    CGRect _dpadUpFrame;
    CGRect _dpadDownFrame;
    CGRect _dpadLeftFrame;
    CGRect _dpadRightFrame;
    
    // Utilities
    CGRect _fpsBadgeFrame;
    CGRect _btnPauseFrame;
    CGRect _btnSettingsFrame;
    
    NSString *_fpsText;
    BOOL _isProMotion;
}
@end

@implementation TouchOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.multipleTouchEnabled = YES;
        self.userInteractionEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        _activeTouches = [[NSMutableDictionary alloc] init];
        _hapticFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [_hapticFeedback prepare];
        
        _controlsOpacity = 0.90;
        _controlsHidden = NO;
        _floatingJoystickEnabled = YES;
        _fpsText = @"60 FPS";
        _isProMotion = NO;
        
        [self resetGamepadState];
        [self calculateLayout];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self calculateLayout];
    [self setNeedsDisplay];
}

- (void)calculateLayout {
    CGSize s = self.bounds.size;
    CGFloat w = s.width;
    CGFloat h = s.height;
    if (w < 100 || h < 100) return;

    // Safe margins for iPhone notch & home indicator
    CGFloat bottomMargin = 25.0;
    CGFloat sideMargin = 35.0;

    // 1. Left Analog Stick (Bottom Left)
    _leftStickRadius = 65.0;
    _defaultLeftStickCenter = CGPointMake(sideMargin + _leftStickRadius + 15.0, h - bottomMargin - _leftStickRadius - 10.0);
    if (!_isLeftStickActive) {
        _leftStickCenter = _defaultLeftStickCenter;
        _leftStickThumbPos = _leftStickCenter;
    }

    // 2. D-Pad (Left side, directly above analog stick)
    CGFloat dpadCenterY = h - bottomMargin - _leftStickRadius * 2.0 - 75.0;
    CGFloat dpadCenterX = sideMargin + 65.0;
    CGFloat dpadArmSize = 36.0;
    CGFloat dpadSpan = 110.0;
    _dpadBounds = CGRectMake(dpadCenterX - dpadSpan/2.0, dpadCenterY - dpadSpan/2.0, dpadSpan, dpadSpan);
    _dpadUpFrame    = CGRectMake(dpadCenterX - dpadArmSize/2.0, dpadCenterY - dpadSpan/2.0, dpadArmSize, dpadArmSize);
    _dpadDownFrame  = CGRectMake(dpadCenterX - dpadArmSize/2.0, dpadCenterY + dpadSpan/2.0 - dpadArmSize, dpadArmSize, dpadArmSize);
    _dpadLeftFrame  = CGRectMake(dpadCenterX - dpadSpan/2.0, dpadCenterY - dpadArmSize/2.0, dpadArmSize, dpadArmSize);
    _dpadRightFrame = CGRectMake(dpadCenterX + dpadSpan/2.0 - dpadArmSize, dpadCenterY - dpadArmSize/2.0, dpadArmSize, dpadArmSize);

    // L3 Thumbstick Click (next to D-pad)
    _btnL3Frame = CGRectMake(dpadCenterX + dpadSpan/2.0 + 8.0, dpadCenterY - 18.0, 36.0, 36.0);

    // 3. LB (Devil Trigger) - Top Left
    _btnLBFrame = CGRectMake(sideMargin, 30.0, 52.0, 52.0);

    // 4. Right Action Buttons (Classic DMC Diamond Layout)
    CGFloat actionCenterX = w - sideMargin - 75.0;
    CGFloat actionCenterY = h - bottomMargin - 85.0;
    CGFloat btnRadius = 31.0;
    CGFloat diamondSpacing = 52.0;

    _btnYFrame = CGRectMake(actionCenterX - btnRadius, actionCenterY - diamondSpacing - btnRadius, btnRadius * 2, btnRadius * 2); // Melee Sword
    _btnAFrame = CGRectMake(actionCenterX - btnRadius, actionCenterY + diamondSpacing - btnRadius, btnRadius * 2, btnRadius * 2); // Jump
    _btnXFrame = CGRectMake(actionCenterX - diamondSpacing - btnRadius, actionCenterY - btnRadius, btnRadius * 2, btnRadius * 2); // Firearm Handgun
    _btnBFrame = CGRectMake(actionCenterX + diamondSpacing - btnRadius, actionCenterY - btnRadius, btnRadius * 2, btnRadius * 2); // Devil Bringer Buster

    // 5. Right Camera Trackpad / Analog Stick
    _rightStickRadius = 55.0;
    _rightStickCenter = CGPointMake(w - sideMargin - diamondSpacing * 2.0 - 50.0, h - bottomMargin - 75.0);
    if (!_isRightStickActive) {
        _rightStickThumbPos = _rightStickCenter;
    }
    _btnR3Frame = CGRectMake(_rightStickCenter.x - 18.0, _rightStickCenter.y - _rightStickRadius - 40.0, 36.0, 36.0);

    // 6. Shoulders & Triggers (Top Right)
    CGFloat trY = 32.0;
    _btnRBFrame = CGRectMake(w - sideMargin - 48.0, trY, 48.0, 48.0); // Lock-On Reticle
    _btnRTFrame = CGRectMake(w - sideMargin - 105.0, trY, 44.0, 44.0); // Weapon Switch
    _btnLTFrame = CGRectMake(w - sideMargin - 158.0, trY, 44.0, 44.0); // Exceed / Devil Arm

    // 7. Top Utility Bar
    _fpsBadgeFrame = CGRectMake(sideMargin + 65.0, 32.0, 85.0, 30.0);
    _btnSettingsFrame = CGRectMake(w / 2.0 - 45.0, 30.0, 38.0, 38.0);
    _btnPauseFrame    = CGRectMake(w / 2.0 + 7.0, 30.0, 38.0, 38.0);
}

- (void)updateFPSDisplay:(double)fps isProMotion:(BOOL)isProMotion {
    _isProMotion = isProMotion;
    _fpsText = [NSString stringWithFormat:@"%.0f FPS", fps];
    [self setNeedsDisplayInRect:_fpsBadgeFrame];
}

#pragma mark - CoreGraphics Rendering

- (void)drawRect:(CGRect)rect {
    if (self.controlsHidden) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetAlpha(ctx, self.controlsOpacity);

    // 1. FPS Badge
    [self drawFPSBadge:ctx];

    // 2. Left Analog Stick (Dynamic / Floating)
    [self drawAnalogStickAt:_leftStickCenter thumb:_leftStickThumbPos radius:_leftStickRadius context:ctx isRight:NO];

    // 3. Right Camera Stick / Zone
    [self drawAnalogStickAt:_rightStickCenter thumb:_rightStickThumbPos radius:_rightStickRadius context:ctx isRight:YES];

    // 4. Gothic Cross D-Pad
    [self drawGothicCrossDpad:ctx];

    // 5. Action Buttons (Crisp Custom Vector Art)
    // Y: Rebellion Sword (Golden / Yellow)
    [self drawActionButtonInFrame:_btnYFrame 
                             type:@"sword" 
                            badge:@"Y" 
                            color:[UIColor colorWithRed:1.0 green:0.84 blue:0.0 alpha:1.0] 
                           active:(_state.buttons & XINPUT_GAMEPAD_Y) 
                          context:ctx];

    // X: Ebony & Ivory Handgun (Cyan / Blue)
    [self drawActionButtonInFrame:_btnXFrame 
                             type:@"gun" 
                            badge:@"X" 
                            color:[UIColor colorWithRed:0.25 green:0.75 blue:1.0 alpha:1.0] 
                           active:(_state.buttons & XINPUT_GAMEPAD_X) 
                          context:ctx];

    // B: Nero's Devil Bringer Demonic Claw (Crimson Red)
    [self drawActionButtonInFrame:_btnBFrame 
                             type:@"buster" 
                            badge:@"B" 
                            color:[UIColor colorWithRed:0.95 green:0.20 blue:0.25 alpha:1.0] 
                           active:(_state.buttons & XINPUT_GAMEPAD_B) 
                          context:ctx];

    // A: Air Hike Jump Chevrons (Emerald Green)
    [self drawActionButtonInFrame:_btnAFrame 
                             type:@"jump" 
                            badge:@"A" 
                            color:[UIColor colorWithRed:0.2 green:0.92 blue:0.45 alpha:1.0] 
                           active:(_state.buttons & XINPUT_GAMEPAD_A) 
                          context:ctx];

    // 6. Tactical Lock-On Reticle (RB)
    [self drawLockOnReticle:_btnRBFrame active:(_state.buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) context:ctx];

    // 7. Devil Trigger (LB)
    [self drawDevilTriggerButton:_btnLBFrame active:(_state.buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) context:ctx];

    // 8. Triggers (LT, RT) and Thumb Clicks (L3, R3)
    [self drawPillButton:_btnRTFrame label:@"RT" badge:nil active:(_state.rightTrigger > 50) color:[UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0] context:ctx];
    [self drawPillButton:_btnLTFrame label:@"LT" badge:nil active:(_state.leftTrigger > 50) color:[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0] context:ctx];
    [self drawPillButton:_btnL3Frame label:@"L3" badge:nil active:(_state.buttons & XINPUT_GAMEPAD_LEFT_THUMB) color:[UIColor whiteColor] context:ctx];
    [self drawPillButton:_btnR3Frame label:@"R3" badge:nil active:(_state.buttons & XINPUT_GAMEPAD_RIGHT_THUMB) color:[UIColor whiteColor] context:ctx];

    // 9. Utilities (Pause, Settings)
    [self drawPillButton:_btnPauseFrame label:@"❚❚" badge:nil active:(_state.buttons & XINPUT_GAMEPAD_START) color:[UIColor whiteColor] context:ctx];
    [self drawPillButton:_btnSettingsFrame label:@"⚙" badge:nil active:NO color:[UIColor whiteColor] context:ctx];
}

#pragma mark - Vector Elements

- (void)drawFPSBadge:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:_fpsBadgeFrame cornerRadius:15.0];
    [[UIColor colorWithWhite:0.08 alpha:0.80] setFill];
    [path fill];
    
    UIColor *strokeCol = _isProMotion ? [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:0.9] : [UIColor colorWithRed:0.9 green:0.2 blue:0.25 alpha:0.9];
    [strokeCol setStroke];
    path.lineWidth = 1.8;
    [path stroke];

    // Glowing dot
    CGRect dotRect = CGRectMake(_fpsBadgeFrame.origin.x + 10, _fpsBadgeFrame.origin.y + 11, 8, 8);
    UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:dotRect];
    [strokeCol setFill];
    [dot fill];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentLeft;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    CGRect textRect = CGRectMake(_fpsBadgeFrame.origin.x + 24, _fpsBadgeFrame.origin.y + 7, _fpsBadgeFrame.size.width - 26, 16);
    [_fpsText drawInRect:textRect withAttributes:attr];
}

- (void)drawAnalogStickAt:(CGPoint)center thumb:(CGPoint)thumb radius:(CGFloat)radius context:(CGContextRef)ctx isRight:(BOOL)isRight {
    // 1. Outer Frosted Base Ring
    CGRect baseRect = CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2);
    UIBezierPath *basePath = [UIBezierPath bezierPathWithOvalInRect:baseRect];
    
    UIColor *bgTint = isRight ? [UIColor colorWithWhite:0.08 alpha:0.45] : [UIColor colorWithRed:0.12 green:0.02 blue:0.04 alpha:0.55];
    [bgTint setFill];
    [basePath fill];

    UIColor *ringStroke = isRight ? [UIColor colorWithWhite:0.7 alpha:0.4] : [UIColor colorWithRed:0.95 green:0.15 blue:0.22 alpha:0.85];
    [ringStroke setStroke];
    basePath.lineWidth = 2.0;
    [basePath stroke];

    // 2. Cardinal Compass Ticks (N, S, E, W)
    CGFloat tickLen = 6.0;
    CGContextSetStrokeColorWithColor(ctx, ringStroke.CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    // North
    CGContextMoveToPoint(ctx, center.x, center.y - radius);
    CGContextAddLineToPoint(ctx, center.x, center.y - radius + tickLen);
    // South
    CGContextMoveToPoint(ctx, center.x, center.y + radius);
    CGContextAddLineToPoint(ctx, center.x, center.y + radius - tickLen);
    // West
    CGContextMoveToPoint(ctx, center.x - radius, center.y);
    CGContextAddLineToPoint(ctx, center.x - radius + tickLen, center.y);
    // East
    CGContextMoveToPoint(ctx, center.x + radius, center.y);
    CGContextAddLineToPoint(ctx, center.x + radius - tickLen, center.y);
    CGContextStrokePath(ctx);

    // 3. Inner 3D Specular Thumb Knob
    CGFloat thumbR = radius * 0.44;
    CGRect thumbRect = CGRectMake(thumb.x - thumbR, thumb.y - thumbR, thumbR * 2, thumbR * 2);
    
    // Radial gradient for 3D sphere illusion
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[3] = {0.0, 0.65, 1.0};
    
    CGFloat redComponents[12] = {
        1.0, 0.45, 0.50, 0.95,   // Specular glare (light crimson/white)
        0.80, 0.08, 0.12, 0.95,  // Midtone crimson
        0.30, 0.02, 0.04, 1.0    // Shadow edge
    };
    CGFloat greyComponents[12] = {
        0.75, 0.75, 0.75, 0.95,
        0.35, 0.35, 0.35, 0.95,
        0.12, 0.12, 0.12, 1.0
    };
    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, isRight ? greyComponents : redComponents, locations, 3);
    
    CGContextSaveGState(ctx);
    UIBezierPath *thumbPath = [UIBezierPath bezierPathWithOvalInRect:thumbRect];
    [thumbPath addClip];

    CGPoint startPoint = CGPointMake(thumb.x - thumbR * 0.28, thumb.y - thumbR * 0.28);
    CGPoint endPoint = thumb;
    CGContextDrawRadialGradient(ctx, gradient, startPoint, 1.0, endPoint, thumbR, kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(ctx);

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    // Specular Rim Stroke
    [[UIColor colorWithWhite:1.0 alpha:0.75] setStroke];
    thumbPath.lineWidth = 1.8;
    [thumbPath stroke];

    // Center Concave Dimple
    UIBezierPath *dimple = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(thumb.x - 5, thumb.y - 5, 10, 10)];
    [[UIColor colorWithWhite:0.0 alpha:0.35] setStroke];
    dimple.lineWidth = 1.2;
    [dimple stroke];
}

- (void)drawGothicCrossDpad:(CGContextRef)ctx {
    // Draw unified cross background
    CGFloat cx = CGRectGetMidX(_dpadBounds);
    CGFloat cy = CGRectGetMidY(_dpadBounds);
    CGFloat armW = 36.0;
    CGFloat armL = _dpadBounds.size.width / 2.0;

    UIBezierPath *cross = [UIBezierPath bezierPath];
    // Start Top Arm
    [cross moveToPoint:CGPointMake(cx - armW/2, cy - armL)];
    [cross addLineToPoint:CGPointMake(cx + armW/2, cy - armL)];
    [cross addLineToPoint:CGPointMake(cx + armW/2, cy - armW/2)];
    // Right Arm
    [cross addLineToPoint:CGPointMake(cx + armL, cy - armW/2)];
    [cross addLineToPoint:CGPointMake(cx + armL, cy + armW/2)];
    [cross addLineToPoint:CGPointMake(cx + armW/2, cy + armW/2)];
    // Bottom Arm
    [cross addLineToPoint:CGPointMake(cx + armW/2, cy + armL)];
    [cross addLineToPoint:CGPointMake(cx - armW/2, cy + armL)];
    [cross addLineToPoint:CGPointMake(cx - armW/2, cy + armW/2)];
    // Left Arm
    [cross addLineToPoint:CGPointMake(cx - armL, cy + armW/2)];
    [cross addLineToPoint:CGPointMake(cx - armL, cy - armW/2)];
    [cross addLineToPoint:CGPointMake(cx - armW/2, cy - armW/2)];
    [cross closePath];

    [[UIColor colorWithWhite:0.08 alpha:0.80] setFill];
    [cross fill];

    [[UIColor colorWithWhite:0.6 alpha:0.5] setStroke];
    cross.lineWidth = 1.5;
    [cross stroke];

    // Individual Direction Highlights & Arrows
    [self drawDpadArrowInFrame:_dpadUpFrame direction:@"UP" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_UP) context:ctx];
    [self drawDpadArrowInFrame:_dpadDownFrame direction:@"DOWN" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_DOWN) context:ctx];
    [self drawDpadArrowInFrame:_dpadLeftFrame direction:@"LEFT" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_LEFT) context:ctx];
    [self drawDpadArrowInFrame:_dpadRightFrame direction:@"RIGHT" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_RIGHT) context:ctx];

    // Center Core Jewel
    UIBezierPath *centerJewel = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 7, cy - 7, 14, 14)];
    [[UIColor colorWithRed:0.9 green:0.15 blue:0.2 alpha:0.85] setFill];
    [centerJewel fill];
    [[UIColor whiteColor] setStroke];
    centerJewel.lineWidth = 1.0;
    [centerJewel stroke];
}

- (void)drawDpadArrowInFrame:(CGRect)frame direction:(NSString *)dir active:(BOOL)active context:(CGContextRef)ctx {
    if (active) {
        UIBezierPath *activeFill = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(frame, 2, 2) cornerRadius:5.0];
        [[UIColor colorWithRed:0.95 green:0.2 blue:0.25 alpha:0.75] setFill];
        [activeFill fill];
    }

    CGFloat cx = CGRectGetMidX(frame);
    CGFloat cy = CGRectGetMidY(frame);
    CGFloat s = 7.0;

    UIBezierPath *arrow = [UIBezierPath bezierPath];
    if ([dir isEqualToString:@"UP"]) {
        [arrow moveToPoint:CGPointMake(cx, cy - s)];
        [arrow addLineToPoint:CGPointMake(cx + s, cy + s - 2)];
        [arrow addLineToPoint:CGPointMake(cx - s, cy + s - 2)];
    } else if ([dir isEqualToString:@"DOWN"]) {
        [arrow moveToPoint:CGPointMake(cx, cy + s)];
        [arrow addLineToPoint:CGPointMake(cx + s, cy - s + 2)];
        [arrow addLineToPoint:CGPointMake(cx - s, cy - s + 2)];
    } else if ([dir isEqualToString:@"LEFT"]) {
        [arrow moveToPoint:CGPointMake(cx - s, cy)];
        [arrow addLineToPoint:CGPointMake(cx + s - 2, cy - s)];
        [arrow addLineToPoint:CGPointMake(cx + s - 2, cy + s)];
    } else if ([dir isEqualToString:@"RIGHT"]) {
        [arrow moveToPoint:CGPointMake(cx + s, cy)];
        [arrow addLineToPoint:CGPointMake(cx - s + 2, cy - s)];
        [arrow addLineToPoint:CGPointMake(cx - s + 2, cy + s)];
    }
    [arrow closePath];

    UIColor *col = active ? [UIColor whiteColor] : [UIColor colorWithWhite:0.85 alpha:0.9];
    [col setFill];
    [arrow fill];
}

- (void)drawActionButtonInFrame:(CGRect)frame 
                           type:(NSString *)type 
                          badge:(NSString *)badge 
                          color:(UIColor *)color 
                         active:(BOOL)active 
                        context:(CGContextRef)ctx 
{
    // 1. Button Base Circle (Glassmorphism)
    CGRect drawFrame = active ? CGRectInset(frame, -2, -2) : frame;
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:drawFrame];
    
    if (active) {
        // Glowing energized state
        [[UIColor colorWithWhite:1.0 alpha:0.90] setFill];
        [circle fill];
        [color setStroke];
        circle.lineWidth = 3.5;
        [circle stroke];
    } else {
        // Deep obsidian glass background
        [[UIColor colorWithWhite:0.08 alpha:0.82] setFill];
        [circle fill];
        [color setStroke];
        circle.lineWidth = 2.2;
        [circle stroke];
    }

    // 2. Custom DMC Vector Icon Art
    if ([type isEqualToString:@"sword"]) {
        [self drawRebellionSwordInRect:drawFrame color:color active:active context:ctx];
    } else if ([type isEqualToString:@"gun"]) {
        [self drawHandgunInRect:drawFrame color:color active:active context:ctx];
    } else if ([type isEqualToString:@"buster"]) {
        [self drawDevilBringerInRect:drawFrame color:color active:active context:ctx];
    } else if ([type isEqualToString:@"jump"]) {
        [self drawJumpChevronsInRect:drawFrame color:color active:active context:ctx];
    }

    // 3. Corner Letter Badge (Y, X, B, A)
    [self drawCornerBadge:badge color:color parentFrame:drawFrame active:active context:ctx];
}

- (void)drawRebellionSwordInRect:(CGRect)rect color:(UIColor *)color active:(BOOL)active context:(CGContextRef)ctx {
    CGFloat cx = CGRectGetMidX(rect);
    CGFloat cy = CGRectGetMidY(rect);
    
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, cx, cy);
    CGContextRotateCTM(ctx, -M_PI_4); // 45 degree angle

    // Blade
    UIBezierPath *blade = [UIBezierPath bezierPath];
    [blade moveToPoint:CGPointMake(0, -18)]; // Pointed tip
    [blade addLineToPoint:CGPointMake(3.5, -14)];
    [blade addLineToPoint:CGPointMake(3.5, 4)];
    [blade addLineToPoint:CGPointMake(-3.5, 4)];
    [blade addLineToPoint:CGPointMake(-3.5, -14)];
    [blade closePath];

    UIColor *bladeFill = active ? [UIColor blackColor] : [UIColor whiteColor];
    [bladeFill setFill];
    [blade fill];

    // Fuller (center blade groove)
    UIBezierPath *fuller = [UIBezierPath bezierPath];
    [fuller moveToPoint:CGPointMake(0, -12)];
    [fuller addLineToPoint:CGPointMake(0, 2)];
    [[UIColor colorWithWhite:0.4 alpha:0.8] setStroke];
    fuller.lineWidth = 1.0;
    [fuller stroke];

    // Crossguard (Gothic quillons)
    UIBezierPath *guard = [UIBezierPath bezierPath];
    [guard moveToPoint:CGPointMake(-9, 4)];
    [guard addLineToPoint:CGPointMake(-9, 6.5)];
    [guard addLineToPoint:CGPointMake(9, 6.5)];
    [guard addLineToPoint:CGPointMake(9, 4)];
    [guard closePath];
    [color setFill];
    [guard fill];

    // Grip
    UIBezierPath *grip = [UIBezierPath bezierPathWithRect:CGRectMake(-1.8, 6.5, 3.6, 7.5)];
    [[UIColor colorWithWhite:0.2 alpha:1.0] setFill];
    [grip fill];

    // Pommel (Skull / Ribbed knob)
    UIBezierPath *pommel = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-3.0, 14.0, 6.0, 6.0)];
    [color setFill];
    [pommel fill];

    CGContextRestoreGState(ctx);
}

- (void)drawHandgunInRect:(CGRect)rect color:(UIColor *)color active:(BOOL)active context:(CGContextRef)ctx {
    CGFloat cx = CGRectGetMidX(rect);
    CGFloat cy = CGRectGetMidY(rect);
    
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, cx + 1, cy - 2);

    // Slide & Barrel (pointing left)
    UIBezierPath *slide = [UIBezierPath bezierPath];
    [slide moveToPoint:CGPointMake(-15, -6)];
    [slide addLineToPoint:CGPointMake(10, -6)];
    [slide addLineToPoint:CGPointMake(10, 2)];
    [slide addLineToPoint:CGPointMake(-15, 2)];
    [slide closePath];

    UIColor *gunFill = active ? [UIColor blackColor] : [UIColor whiteColor];
    [gunFill setFill];
    [slide fill];

    // Front & Rear Sights
    UIBezierPath *sights = [UIBezierPath bezierPath];
    [sights moveToPoint:CGPointMake(-14, -6)];
    [sights addLineToPoint:CGPointMake(-14, -8)];
    [sights addLineToPoint:CGPointMake(-12, -8)];
    [sights addLineToPoint:CGPointMake(-12, -6)];
    [sights moveToPoint:CGPointMake(7, -6)];
    [sights addLineToPoint:CGPointMake(7, -8)];
    [sights addLineToPoint:CGPointMake(9, -8)];
    [sights addLineToPoint:CGPointMake(9, -6)];
    [color setFill];
    [sights fill];

    // Trigger Guard & Trigger
    UIBezierPath *guard = [UIBezierPath bezierPath];
    [guard moveToPoint:CGPointMake(-4, 2)];
    [guard addCurveToPoint:CGPointMake(2, 7) controlPoint1:CGPointMake(-4, 7) controlPoint2:CGPointMake(0, 7)];
    [guard addLineToPoint:CGPointMake(2, 2)];
    guard.lineWidth = 1.5;
    [color setStroke];
    [guard stroke];

    // Curved Trigger inside
    UIBezierPath *trigger = [UIBezierPath bezierPath];
    [trigger moveToPoint:CGPointMake(-1, 2)];
    [trigger addCurveToPoint:CGPointMake(0, 5) controlPoint1:CGPointMake(0, 3) controlPoint2:CGPointMake(1, 4)];
    trigger.lineWidth = 1.2;
    [[UIColor whiteColor] setStroke];
    [trigger stroke];

    // Pistol Grip
    UIBezierPath *grip = [UIBezierPath bezierPath];
    [grip moveToPoint:CGPointMake(2, 2)];
    [grip addLineToPoint:CGPointMake(9, 14)];
    [grip addLineToPoint:CGPointMake(3, 15)];
    [grip addLineToPoint:CGPointMake(-1, 6)];
    [grip closePath];
    [color setFill];
    [grip fill];

    CGContextRestoreGState(ctx);
}

- (void)drawDevilBringerInRect:(CGRect)rect color:(UIColor *)color active:(BOOL)active context:(CGContextRef)ctx {
    CGFloat cx = CGRectGetMidX(rect);
    CGFloat cy = CGRectGetMidY(rect);
    
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, cx, cy);

    // Palm base
    UIBezierPath *palm = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-8, 3, 16, 11)];
    UIColor *palmFill = active ? [UIColor blackColor] : [UIColor whiteColor];
    [palmFill setFill];
    [palm fill];

    // 4 Demonic Claw Talons pointing upwards
    CGFloat clawX[4] = {-7.5, -2.5, 2.5, 7.5};
    CGFloat clawH[4] = {14.0, 18.0, 17.0, 13.0};
    CGFloat curve[4] = {-2.0, -0.5, 0.5, 2.0};

    for (int i = 0; i < 4; ++i) {
        UIBezierPath *claw = [UIBezierPath bezierPath];
        [claw moveToPoint:CGPointMake(clawX[i] - 1.5, 4)];
        [claw addQuadCurveToPoint:CGPointMake(clawX[i] + curve[i], 4 - clawH[i]) controlPoint:CGPointMake(clawX[i] - 1.0, 4 - clawH[i]*0.5)];
        [claw addQuadCurveToPoint:CGPointMake(clawX[i] + 1.5, 4) controlPoint:CGPointMake(clawX[i] + 1.0, 4 - clawH[i]*0.5)];
        [claw closePath];
        [color setFill];
        [claw fill];
    }

    // Demonic thumb claw (curving left)
    UIBezierPath *thumb = [UIBezierPath bezierPath];
    [thumb moveToPoint:CGPointMake(-6, 8)];
    [thumb addQuadCurveToPoint:CGPointMake(-13, 0) controlPoint:CGPointMake(-11, 4)];
    [thumb addQuadCurveToPoint:CGPointMake(-5, 5) controlPoint:CGPointMake(-8, 1)];
    [thumb closePath];
    [color setFill];
    [thumb fill];

    // Spectral Energy Core in center of palm
    UIBezierPath *core = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-3.5, 6, 7, 6)];
    [[UIColor colorWithRed:0.95 green:0.2 blue:0.25 alpha:0.9] setFill];
    [core fill];

    CGContextRestoreGState(ctx);
}

- (void)drawJumpChevronsInRect:(CGRect)rect color:(UIColor *)color active:(BOOL)active context:(CGContextRef)ctx {
    CGFloat cx = CGRectGetMidX(rect);
    CGFloat cy = CGRectGetMidY(rect);
    
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, cx, cy);

    UIColor *c = active ? [UIColor blackColor] : color;
    [c setStroke];

    // Upper chevron
    UIBezierPath *chev1 = [UIBezierPath bezierPath];
    [chev1 moveToPoint:CGPointMake(-10, -3)];
    [chev1 addLineToPoint:CGPointMake(0, -12)];
    [chev1 addLineToPoint:CGPointMake(10, -3)];
    chev1.lineWidth = 3.6;
    chev1.lineCapStyle = kCGLineCapRound;
    chev1.lineJoinStyle = kCGLineJoinRound;
    [chev1 stroke];

    // Lower chevron
    UIBezierPath *chev2 = [UIBezierPath bezierPath];
    [chev2 moveToPoint:CGPointMake(-10, 7)];
    [chev2 addLineToPoint:CGPointMake(0, -2)];
    [chev2 addLineToPoint:CGPointMake(10, 7)];
    chev2.lineWidth = 3.6;
    chev2.lineCapStyle = kCGLineCapRound;
    chev2.lineJoinStyle = kCGLineJoinRound;
    [chev2 stroke];

    CGContextRestoreGState(ctx);
}

- (void)drawCornerBadge:(NSString *)badge color:(UIColor *)color parentFrame:(CGRect)frame active:(BOOL)active context:(CGContextRef)ctx {
    CGFloat badgeR = 10.0;
    CGFloat bx = frame.origin.x + frame.size.width - badgeR - 2.0;
    CGFloat by = frame.origin.y + frame.size.height - badgeR - 2.0;
    CGRect badgeRect = CGRectMake(bx - badgeR, by - badgeR, badgeR * 2, badgeR * 2);

    UIBezierPath *badgeBg = [UIBezierPath bezierPathWithOvalInRect:badgeRect];
    [[UIColor colorWithWhite:0.06 alpha:0.90] setFill];
    [badgeBg fill];

    [color setStroke];
    badgeBg.lineWidth = 1.4;
    [badgeBg stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName: active ? [UIColor whiteColor] : color,
        NSParagraphStyleAttributeName: style
    };
    CGRect textRect = CGRectMake(badgeRect.origin.x, badgeRect.origin.y + 2, badgeRect.size.width, badgeRect.size.height - 2);
    [badge drawInRect:textRect withAttributes:attr];
}

- (void)drawLockOnReticle:(CGRect)frame active:(BOOL)active context:(CGContextRef)ctx {
    CGRect drawFrame = active ? CGRectInset(frame, -2, -2) : frame;
    UIBezierPath *base = [UIBezierPath bezierPathWithOvalInRect:drawFrame];
    [[UIColor colorWithWhite:0.08 alpha:0.80] setFill];
    [base fill];

    UIColor *c = active ? [UIColor whiteColor] : [UIColor colorWithRed:1.0 green:0.2 blue:0.25 alpha:0.9];
    [c setStroke];
    base.lineWidth = active ? 2.5 : 1.8;
    [base stroke];

    CGFloat cx = CGRectGetMidX(drawFrame);
    CGFloat cy = CGRectGetMidY(drawFrame);
    CGFloat r = drawFrame.size.width * 0.32;

    // Corner brackets ⌜ ⌝ ⌞ ⌟
    CGFloat bLen = 6.0;
    CGContextSetStrokeColorWithColor(ctx, c.CGColor);
    CGContextSetLineWidth(ctx, 1.8);
    // Top-Left
    CGContextMoveToPoint(ctx, cx - r, cy - r + bLen);
    CGContextAddLineToPoint(ctx, cx - r, cy - r);
    CGContextAddLineToPoint(ctx, cx - r + bLen, cy - r);
    // Top-Right
    CGContextMoveToPoint(ctx, cx + r - bLen, cy - r);
    CGContextAddLineToPoint(ctx, cx + r, cy - r);
    CGContextAddLineToPoint(ctx, cx + r, cy - r + bLen);
    // Bottom-Left
    CGContextMoveToPoint(ctx, cx - r, cy + r - bLen);
    CGContextAddLineToPoint(ctx, cx - r, cy + r);
    CGContextAddLineToPoint(ctx, cx - r + bLen, cy + r);
    // Bottom-Right
    CGContextMoveToPoint(ctx, cx + r - bLen, cy + r);
    CGContextAddLineToPoint(ctx, cx + r, cy + r);
    CGContextAddLineToPoint(ctx, cx + r, cy + r - bLen);
    CGContextStrokePath(ctx);

    // Crosshairs
    CGContextMoveToPoint(ctx, cx - r * 0.7, cy);
    CGContextAddLineToPoint(ctx, cx + r * 0.7, cy);
    CGContextMoveToPoint(ctx, cx, cy - r * 0.7);
    CGContextAddLineToPoint(ctx, cx, cy + r * 0.7);
    CGContextStrokePath(ctx);

    // Red Center Dot
    UIBezierPath *centerDot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 2.5, cy - 2.5, 5, 5)];
    [c setFill];
    [centerDot fill];

    // Badge
    [self drawCornerBadge:@"RB" color:c parentFrame:drawFrame active:active context:ctx];
}

- (void)drawDevilTriggerButton:(CGRect)frame active:(BOOL)active context:(CGContextRef)ctx {
    CGRect drawFrame = active ? CGRectInset(frame, -2, -2) : frame;
    UIBezierPath *base = [UIBezierPath bezierPathWithOvalInRect:drawFrame];
    [[UIColor colorWithWhite:0.08 alpha:0.80] setFill];
    [base fill];

    UIColor *c = active ? [UIColor whiteColor] : [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:0.9];
    [c setStroke];
    base.lineWidth = active ? 2.8 : 2.0;
    [base stroke];

    CGFloat cx = CGRectGetMidX(drawFrame);
    CGFloat cy = CGRectGetMidY(drawFrame);

    // Demonic winged crest icon
    UIBezierPath *wings = [UIBezierPath bezierPath];
    // Left Wing
    [wings moveToPoint:CGPointMake(cx, cy + 5)];
    [wings addCurveToPoint:CGPointMake(cx - 14, cy - 8) controlPoint1:CGPointMake(cx - 8, cy) controlPoint2:CGPointMake(cx - 12, cy - 4)];
    [wings addCurveToPoint:CGPointMake(cx - 2, cy - 3) controlPoint1:CGPointMake(cx - 10, cy - 5) controlPoint2:CGPointMake(cx - 6, cy - 3)];
    // Right Wing
    [wings moveToPoint:CGPointMake(cx, cy + 5)];
    [wings addCurveToPoint:CGPointMake(cx + 14, cy - 8) controlPoint1:CGPointMake(cx + 8, cy) controlPoint2:CGPointMake(cx + 12, cy - 4)];
    [wings addCurveToPoint:CGPointMake(cx + 2, cy - 3) controlPoint1:CGPointMake(cx + 10, cy - 5) controlPoint2:CGPointMake(cx + 6, cy - 3)];
    
    wings.lineWidth = 2.2;
    wings.lineCapStyle = kCGLineCapRound;
    [c setStroke];
    [wings stroke];

    // Flaming Core
    UIBezierPath *core = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 3, cy + 2, 6, 6)];
    [c setFill];
    [core fill];

    // Badge
    [self drawCornerBadge:@"LB" color:c parentFrame:drawFrame active:active context:ctx];
}

- (void)drawPillButton:(CGRect)frame label:(NSString *)label badge:(NSString *)badge active:(BOOL)active color:(UIColor *)color context:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:frame.size.height / 2.0];
    if (active) {
        [[UIColor whiteColor] setFill];
    } else {
        [[UIColor colorWithWhite:0.08 alpha:0.80] setFill];
    }
    [path fill];
    
    UIColor *strokeCol = active ? [UIColor whiteColor] : [color colorWithAlphaComponent:0.8];
    [strokeCol setStroke];
    path.lineWidth = 1.5;
    [path stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont fontWithName:@"HelveticaNeue-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: active ? [UIColor blackColor] : [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    CGRect textRect = CGRectMake(frame.origin.x, frame.origin.y + (frame.size.height - 14) / 2.0, frame.size.width, 16);
    [label drawInRect:textRect withAttributes:attr];
}

#pragma mark - Multi-Touch & Floating Joystick Logic

- (TouchElement)elementForPoint:(CGPoint)pt {
    // Generous touch hitboxes (+14pt margin) for zero missed inputs
    CGFloat pad = 14.0;

    // 1. Action Buttons
    if (hypot(pt.x - CGRectGetMidX(_btnYFrame), pt.y - CGRectGetMidY(_btnYFrame)) <= _btnYFrame.size.width/2.0 + pad) return TouchElementBtnY;
    if (hypot(pt.x - CGRectGetMidX(_btnXFrame), pt.y - CGRectGetMidY(_btnXFrame)) <= _btnXFrame.size.width/2.0 + pad) return TouchElementBtnX;
    if (hypot(pt.x - CGRectGetMidX(_btnBFrame), pt.y - CGRectGetMidY(_btnBFrame)) <= _btnBFrame.size.width/2.0 + pad) return TouchElementBtnB;
    if (hypot(pt.x - CGRectGetMidX(_btnAFrame), pt.y - CGRectGetMidY(_btnAFrame)) <= _btnAFrame.size.width/2.0 + pad) return TouchElementBtnA;

    // 2. Shoulders & Triggers
    if (CGRectContainsPoint(CGRectInset(_btnRBFrame, -pad, -pad), pt)) return TouchElementBtnRB;
    if (CGRectContainsPoint(CGRectInset(_btnLBFrame, -pad, -pad), pt)) return TouchElementBtnLB;
    if (CGRectContainsPoint(CGRectInset(_btnRTFrame, -pad, -pad), pt)) return TouchElementBtnRT;
    if (CGRectContainsPoint(CGRectInset(_btnLTFrame, -pad, -pad), pt)) return TouchElementBtnLT;
    if (CGRectContainsPoint(CGRectInset(_btnL3Frame, -pad, -pad), pt)) return TouchElementBtnL3;
    if (CGRectContainsPoint(CGRectInset(_btnR3Frame, -pad, -pad), pt)) return TouchElementBtnR3;

    // 3. D-Pad
    if (CGRectContainsPoint(CGRectInset(_dpadUpFrame, -pad, -pad), pt)) return TouchElementDpadUp;
    if (CGRectContainsPoint(CGRectInset(_dpadDownFrame, -pad, -pad), pt)) return TouchElementDpadDown;
    if (CGRectContainsPoint(CGRectInset(_dpadLeftFrame, -pad, -pad), pt)) return TouchElementDpadLeft;
    if (CGRectContainsPoint(CGRectInset(_dpadRightFrame, -pad, -pad), pt)) return TouchElementDpadRight;

    // 4. Utilities
    if (CGRectContainsPoint(_btnPauseFrame, pt)) return TouchElementBtnPause;
    if (CGRectContainsPoint(_btnSettingsFrame, pt)) return TouchElementBtnSettings;

    // 5. Left Movement Quadrant (Left 42% of screen, bottom 60%)
    if (pt.x < self.bounds.size.width * 0.42 && pt.y > self.bounds.size.height * 0.35) {
        return TouchElementLeftStick;
    }

    // 6. Right Camera Quadrant (Between center and action buttons)
    if (pt.x > self.bounds.size.width * 0.50 && pt.x < _btnXFrame.origin.x - 10.0 && pt.y > self.bounds.size.height * 0.35) {
        return TouchElementRightStick;
    }

    return TouchElementNone;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint pt = [touch locationInView:self];
        TouchElement elem = [self elementForPoint:pt];
        if (elem != TouchElementNone) {
            _activeTouches[[NSValue valueWithNonretainedObject:touch]] = @(elem);

            // Floating dynamic joystick: center joystick immediately under finger
            if (elem == TouchElementLeftStick && self.floatingJoystickEnabled) {
                _isLeftStickActive = YES;
                _leftStickCenter = pt;
                _leftStickThumbPos = pt;
            } else if (elem == TouchElementRightStick && self.floatingJoystickEnabled) {
                _isRightStickActive = YES;
                _rightStickCenter = pt;
                _rightStickThumbPos = pt;
            }

            [self handleElementState:elem pressed:YES point:pt];
            [_hapticFeedback impactOccurred];
        }
    }
    [self notifyDelegate];
    [self setNeedsDisplay];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        NSValue *key = [NSValue valueWithNonretainedObject:touch];
        NSNumber *elemNum = _activeTouches[key];
        if (!elemNum) continue;

        TouchElement elem = (TouchElement)[elemNum integerValue];
        CGPoint pt = [touch locationInView:self];

        if (elem == TouchElementLeftStick) {
            CGFloat dx = pt.x - _leftStickCenter.x;
            CGFloat dy = pt.y - _leftStickCenter.y;
            CGFloat dist = hypot(dx, dy);
            CGFloat maxDist = _leftStickRadius;
            
            if (dist > maxDist) {
                dx = (dx / dist) * maxDist;
                dy = (dy / dist) * maxDist;
            }
            _leftStickThumbPos = CGPointMake(_leftStickCenter.x + dx, _leftStickCenter.y + dy);
            
            // Normalize to [-32768, 32767] (Invert Y for Xbox standard)
            _state.thumbLX = (int16_t)((dx / maxDist) * 32767.0);
            _state.thumbLY = (int16_t)(- (dy / maxDist) * 32767.0);
        } else if (elem == TouchElementRightStick) {
            CGFloat dx = pt.x - _rightStickCenter.x;
            CGFloat dy = pt.y - _rightStickCenter.y;
            CGFloat dist = hypot(dx, dy);
            CGFloat maxDist = _rightStickRadius;
            
            if (dist > maxDist) {
                dx = (dx / dist) * maxDist;
                dy = (dy / dist) * maxDist;
            }
            _rightStickThumbPos = CGPointMake(_rightStickCenter.x + dx, _rightStickCenter.y + dy);
            
            _state.thumbRX = (int16_t)((dx / maxDist) * 32767.0);
            _state.thumbRY = (int16_t)(- (dy / maxDist) * 32767.0);
        }
    }
    [self notifyDelegate];
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        NSValue *key = [NSValue valueWithNonretainedObject:touch];
        NSNumber *elemNum = _activeTouches[key];
        if (elemNum) {
            TouchElement elem = (TouchElement)[elemNum integerValue];
            [self handleElementState:elem pressed:NO point:CGPointZero];
            [_activeTouches removeObjectForKey:key];
        }
    }
    [self notifyDelegate];
    [self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)handleElementState:(TouchElement)elem pressed:(BOOL)pressed point:(CGPoint)pt {
    switch (elem) {
        case TouchElementBtnY:
            [self setButton:XINPUT_GAMEPAD_Y active:pressed];
            break;
        case TouchElementBtnX:
            [self setButton:XINPUT_GAMEPAD_X active:pressed];
            break;
        case TouchElementBtnB:
            [self setButton:XINPUT_GAMEPAD_B active:pressed];
            break;
        case TouchElementBtnA:
            [self setButton:XINPUT_GAMEPAD_A active:pressed];
            break;
        case TouchElementBtnRB:
            [self setButton:XINPUT_GAMEPAD_RIGHT_SHOULDER active:pressed];
            break;
        case TouchElementBtnLB:
            [self setButton:XINPUT_GAMEPAD_LEFT_SHOULDER active:pressed];
            break;
        case TouchElementBtnRT:
            _state.rightTrigger = pressed ? 255 : 0;
            break;
        case TouchElementBtnLT:
            _state.leftTrigger = pressed ? 255 : 0;
            break;
        case TouchElementBtnL3:
            [self setButton:XINPUT_GAMEPAD_LEFT_THUMB active:pressed];
            break;
        case TouchElementBtnR3:
            [self setButton:XINPUT_GAMEPAD_RIGHT_THUMB active:pressed];
            break;
        case TouchElementDpadUp:
            [self setButton:XINPUT_GAMEPAD_DPAD_UP active:pressed];
            break;
        case TouchElementDpadDown:
            [self setButton:XINPUT_GAMEPAD_DPAD_DOWN active:pressed];
            break;
        case TouchElementDpadLeft:
            [self setButton:XINPUT_GAMEPAD_DPAD_LEFT active:pressed];
            break;
        case TouchElementDpadRight:
            [self setButton:XINPUT_GAMEPAD_DPAD_RIGHT active:pressed];
            break;
        case TouchElementLeftStick:
            if (!pressed) {
                _isLeftStickActive = NO;
                _leftStickCenter = _defaultLeftStickCenter;
                _leftStickThumbPos = _leftStickCenter;
                _state.thumbLX = 0;
                _state.thumbLY = 0;
            }
            break;
        case TouchElementRightStick:
            if (!pressed) {
                _isRightStickActive = NO;
                _rightStickThumbPos = _rightStickCenter;
                _state.thumbRX = 0;
                _state.thumbRY = 0;
            }
            break;
        case TouchElementBtnPause:
            [self setButton:XINPUT_GAMEPAD_START active:pressed];
            if (pressed && [self.delegate respondsToSelector:@selector(touchOverlayDidPressPause)]) {
                [self.delegate touchOverlayDidPressPause];
            }
            break;
        case TouchElementBtnSettings:
            if (pressed && [self.delegate respondsToSelector:@selector(touchOverlayDidPressSettings)]) {
                [self.delegate touchOverlayDidPressSettings];
            }
            break;
        default:
            break;
    }
}

- (void)setButton:(uint16_t)mask active:(BOOL)active {
    if (active) {
        _state.buttons |= mask;
    } else {
        _state.buttons &= ~mask;
    }
}

- (const VirtualGamepadState *)currentGamepadState {
    return &_state;
}

- (void)resetGamepadState {
    memset(&_state, 0, sizeof(VirtualGamepadState));
    _isLeftStickActive = NO;
    _isRightStickActive = NO;
    _leftStickThumbPos = _leftStickCenter;
    _rightStickThumbPos = _rightStickCenter;
    [_activeTouches removeAllObjects];
}

- (void)notifyDelegate {
    if ([self.delegate respondsToSelector:@selector(touchOverlayDidChangeGamepadState:)]) {
        [self.delegate touchOverlayDidChangeGamepadState:&_state];
    }
}

@end
