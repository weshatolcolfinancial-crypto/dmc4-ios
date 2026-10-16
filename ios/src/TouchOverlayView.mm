#import "TouchOverlayView.h"

// Element IDs for tracking active touches
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
    
    // Layout frames (calculated on layoutSubviews)
    CGPoint _leftStickCenter;
    CGFloat _leftStickRadius;
    CGPoint _leftStickThumbPos;
    
    CGPoint _rightStickCenter;
    CGFloat _rightStickRadius;
    CGPoint _rightStickThumbPos;
    
    CGRect _btnAFrame;
    CGRect _btnBFrame;
    CGRect _btnXFrame;
    CGRect _btnYFrame;
    
    CGRect _btnRBFrame; // Lock-On Reticle
    CGRect _btnLBFrame; // Devil Trigger
    CGRect _btnRTFrame;
    CGRect _btnLTFrame;
    
    CGRect _btnL3Frame;
    CGRect _btnR3Frame;
    
    CGRect _dpadUpFrame;
    CGRect _dpadDownFrame;
    CGRect _dpadLeftFrame;
    CGRect _dpadRightFrame;
    
    CGRect _btnPauseFrame;
    CGRect _btnSettingsFrame;
    CGRect _fpsBadgeFrame;
    
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
        
        _controlsOpacity = 0.85;
        _controlsHidden = NO;
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

    // Left Stick (Bottom Left)
    _leftStickRadius = 60.0;
    _leftStickCenter = CGPointMake(95.0, h - 95.0);
    _leftStickThumbPos = _leftStickCenter;
    
    // D-Pad (Left side, above joystick)
    CGFloat dpadCenterY = h - 215.0;
    CGFloat dpadCenterX = 75.0;
    CGFloat dpadBtnSize = 36.0;
    _dpadUpFrame    = CGRectMake(dpadCenterX - dpadBtnSize/2, dpadCenterY - dpadBtnSize - 5, dpadBtnSize, dpadBtnSize);
    _dpadDownFrame  = CGRectMake(dpadCenterX - dpadBtnSize/2, dpadCenterY + 5, dpadBtnSize, dpadBtnSize);
    _dpadLeftFrame  = CGRectMake(dpadCenterX - dpadBtnSize - 5, dpadCenterY - dpadBtnSize/2, dpadBtnSize, dpadBtnSize);
    _dpadRightFrame = CGRectMake(dpadCenterX + 5, dpadCenterY - dpadBtnSize/2, dpadBtnSize, dpadBtnSize);

    _btnL3Frame = CGRectMake(130.0, dpadCenterY - 18, 36.0, 36.0);

    // LB (Devil Trigger) - Top Left
    _btnLBFrame = CGRectMake(35.0, 30.0, 48.0, 48.0);

    // Right Action Buttons (DMC Diamond Layout)
    CGFloat actionCenterX = w - 90.0;
    CGFloat actionCenterY = h - 90.0;
    CGFloat btnRadius = 28.0;
    CGFloat offset = 48.0;

    _btnYFrame = CGRectMake(actionCenterX - btnRadius, actionCenterY - offset - btnRadius, btnRadius * 2, btnRadius * 2);      // Sword
    _btnAFrame = CGRectMake(actionCenterX - btnRadius, actionCenterY + offset - btnRadius, btnRadius * 2, btnRadius * 2);      // Jump
    _btnXFrame = CGRectMake(actionCenterX - offset - btnRadius, actionCenterY - btnRadius, btnRadius * 2, btnRadius * 2);      // Gun
    _btnBFrame = CGRectMake(actionCenterX + offset - btnRadius, actionCenterY - btnRadius, btnRadius * 2, btnRadius * 2);      // Buster Hand

    // Right Camera Stick / Touch Zone
    _rightStickRadius = 50.0;
    _rightStickCenter = CGPointMake(w - 210.0, h - 95.0);
    _rightStickThumbPos = _rightStickCenter;
    _btnR3Frame = CGRectMake(w - 230.0, h - 170.0, 36.0, 36.0);

    // Shoulder & Triggers - Top Right
    CGFloat trY = 32.0;
    _btnRBFrame = CGRectMake(w - 55.0, trY, 44.0, 44.0);  // Lock-on Reticle
    _btnRTFrame = CGRectMake(w - 105.0, trY, 42.0, 42.0);
    _btnLTFrame = CGRectMake(w - 152.0, trY, 42.0, 42.0);

    // Top Center Bar
    _fpsBadgeFrame = CGRectMake(100.0, 28.0, 80.0, 28.0);
    _btnSettingsFrame = CGRectMake(w / 2.0 - 24.0, 28.0, 36.0, 36.0);
    _btnPauseFrame = CGRectMake(w / 2.0 + 24.0, 28.0, 36.0, 36.0);
}

- (void)updateFPSDisplay:(double)fps isProMotion:(BOOL)isProMotion {
    _isProMotion = isProMotion;
    _fpsText = [NSString stringWithFormat:@"%.0f FPS", fps];
    [self setNeedsDisplayInRect:_fpsBadgeFrame];
}

#pragma mark - Drawing DMC Combat HUD

- (void)drawRect:(CGRect)rect {
    if (self.controlsHidden) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetAlpha(ctx, self.controlsOpacity);

    // 1. Draw FPS Badge
    [self drawFPSBadge:ctx];

    // 2. Draw Left Analog Stick
    [self drawJoystickAt:_leftStickCenter thumb:_leftStickThumbPos radius:_leftStickRadius context:ctx isRight:NO];

    // 3. Draw Right Camera Stick / Trackpad
    [self drawJoystickAt:_rightStickCenter thumb:_rightStickThumbPos radius:_rightStickRadius context:ctx isRight:YES];

    // 4. Draw D-Pad (Styles)
    [self drawDpadButton:_dpadUpFrame direction:@"▲" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_UP) context:ctx];
    [self drawDpadButton:_dpadDownFrame direction:@"▼" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_DOWN) context:ctx];
    [self drawDpadButton:_dpadLeftFrame direction:@"◀" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_LEFT) context:ctx];
    [self drawDpadButton:_dpadRightFrame direction:@"▶" active:(_state.buttons & XINPUT_GAMEPAD_DPAD_RIGHT) context:ctx];

    // 5. Draw Action Buttons (DMC Vector Icons)
    [self drawActionButton:_btnYFrame label:@"Y" icon:@"⚔" active:(_state.buttons & XINPUT_GAMEPAD_Y) color:[UIColor colorWithRed:0.95 green:0.85 blue:0.2 alpha:1.0] context:ctx];
    [self drawActionButton:_btnXFrame label:@"X" icon:@"︻╦╤─" active:(_state.buttons & XINPUT_GAMEPAD_X) color:[UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0] context:ctx];
    [self drawActionButton:_btnBFrame label:@"B" icon:@"✋" active:(_state.buttons & XINPUT_GAMEPAD_B) color:[UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0] context:ctx];
    [self drawActionButton:_btnAFrame label:@"A" icon:@"⏫" active:(_state.buttons & XINPUT_GAMEPAD_A) color:[UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1.0] context:ctx];

    // 6. Draw Lock-On Reticle (RB)
    [self drawLockOnReticle:_btnRBFrame active:(_state.buttons & XINPUT_GAMEPAD_RIGHT_SHOULDER) context:ctx];

    // 7. Draw Devil Trigger Button (LB)
    [self drawDevilTriggerButton:_btnLBFrame active:(_state.buttons & XINPUT_GAMEPAD_LEFT_SHOULDER) context:ctx];

    // 8. Draw Triggers (LT, RT) and Sticks (L3, R3)
    [self drawPillButton:_btnLTFrame label:@"LT" active:(_state.leftTrigger > 50) context:ctx];
    [self drawPillButton:_btnRTFrame label:@"RT" active:(_state.rightTrigger > 50) context:ctx];
    [self drawPillButton:_btnL3Frame label:@"L3" active:(_state.buttons & XINPUT_GAMEPAD_LEFT_THUMB) context:ctx];
    [self drawPillButton:_btnR3Frame label:@"R3" active:(_state.buttons & XINPUT_GAMEPAD_RIGHT_THUMB) context:ctx];

    // 9. Draw Utility (Pause, Settings)
    [self drawPillButton:_btnPauseFrame label:@"❚❚" active:(_state.buttons & XINPUT_GAMEPAD_START) context:ctx];
    [self drawPillButton:_btnSettingsFrame label:@"⚙" active:NO context:ctx];
}

- (void)drawFPSBadge:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:_fpsBadgeFrame cornerRadius:14.0];
    [[UIColor colorWithWhite:0.1 alpha:0.75] setFill];
    [path fill];
    
    UIColor *strokeCol = _isProMotion ? [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:0.9] : [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:0.8];
    [strokeCol setStroke];
    path.lineWidth = 1.5;
    [path stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:12],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    CGRect textRect = CGRectMake(_fpsBadgeFrame.origin.x, _fpsBadgeFrame.origin.y + 6, _fpsBadgeFrame.size.width, _fpsBadgeFrame.size.height - 6);
    [_fpsText drawInRect:textRect withAttributes:attr];
}

- (void)drawJoystickAt:(CGPoint)center thumb:(CGPoint)thumb radius:(CGFloat)radius context:(CGContextRef)ctx isRight:(BOOL)isRight {
    // Outer base circle
    CGRect baseRect = CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2);
    UIBezierPath *basePath = [UIBezierPath bezierPathWithOvalInRect:baseRect];
    
    // Crimson metallic glow
    UIColor *glow = isRight ? [UIColor colorWithWhite:0.15 alpha:0.5] : [UIColor colorWithRed:0.7 green:0.1 blue:0.15 alpha:0.45];
    [glow setFill];
    [basePath fill];
    
    [[UIColor colorWithWhite:0.8 alpha:0.6] setStroke];
    basePath.lineWidth = 2.0;
    [basePath stroke];

    // Inner thumb
    CGFloat thumbRadius = radius * 0.45;
    CGRect thumbRect = CGRectMake(thumb.x - thumbRadius, thumb.y - thumbRadius, thumbRadius * 2, thumbRadius * 2);
    UIBezierPath *thumbPath = [UIBezierPath bezierPathWithOvalInRect:thumbRect];
    [[UIColor colorWithRed:0.85 green:0.15 blue:0.2 alpha:0.85] setFill];
    [thumbPath fill];
    [[UIColor whiteColor] setStroke];
    thumbPath.lineWidth = 1.5;
    [thumbPath stroke];
}

- (void)drawActionButton:(CGRect)frame label:(NSString *)label icon:(NSString *)icon active:(BOOL)active color:(UIColor *)color context:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:frame];
    if (active) {
        [[UIColor whiteColor] setFill];
    } else {
        [[UIColor colorWithWhite:0.12 alpha:0.85] setFill];
    }
    [path fill];

    [color setStroke];
    path.lineWidth = active ? 3.0 : 2.0;
    [path stroke];

    // Center icon
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont systemFontOfSize:18],
        NSForegroundColorAttributeName: active ? [UIColor blackColor] : [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    CGRect iconRect = CGRectMake(frame.origin.x, frame.origin.y + 12, frame.size.width, frame.size.height - 12);
    [icon drawInRect:iconRect withAttributes:attr];

    // Small Button Name Badge (X, Y, A, B)
    NSDictionary *subAttr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:10],
        NSForegroundColorAttributeName: active ? [UIColor blackColor] : color,
        NSParagraphStyleAttributeName: style
    };
    CGRect subRect = CGRectMake(frame.origin.x, frame.origin.y + frame.size.height - 18, frame.size.width, 16);
    [label drawInRect:subRect withAttributes:subAttr];
}

- (void)drawLockOnReticle:(CGRect)frame active:(BOOL)active context:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:frame];
    [[UIColor colorWithWhite:0.12 alpha:0.85] setFill];
    [path fill];

    UIColor *c = active ? [UIColor whiteColor] : [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.9];
    [c setStroke];
    path.lineWidth = 2.0;
    [path stroke];

    // Crosshair target reticle
    CGFloat cx = CGRectGetMidX(frame);
    CGFloat cy = CGRectGetMidY(frame);
    CGFloat r = frame.size.width * 0.3;
    
    CGContextSetStrokeColorWithColor(ctx, c.CGColor);
    CGContextSetLineWidth(ctx, 1.5);
    
    CGContextMoveToPoint(ctx, cx - r, cy);
    CGContextAddLineToPoint(ctx, cx + r, cy);
    CGContextMoveToPoint(ctx, cx, cy - r);
    CGContextAddLineToPoint(ctx, cx, cy + r);
    CGContextStrokePath(ctx);

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:9],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    [@"RB" drawInRect:CGRectMake(frame.origin.x, frame.origin.y + frame.size.height - 14, frame.size.width, 14) withAttributes:attr];
}

- (void)drawDevilTriggerButton:(CGRect)frame active:(BOOL)active context:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:frame];
    [[UIColor colorWithWhite:0.12 alpha:0.85] setFill];
    [path fill];

    UIColor *c = active ? [UIColor whiteColor] : [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    [c setStroke];
    path.lineWidth = 2.5;
    [path stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont systemFontOfSize:16],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    [@"DT" drawInRect:CGRectMake(frame.origin.x, frame.origin.y + 10, frame.size.width, 20) withAttributes:attr];

    NSDictionary *subAttr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:9],
        NSForegroundColorAttributeName: c,
        NSParagraphStyleAttributeName: style
    };
    [@"LB" drawInRect:CGRectMake(frame.origin.x, frame.origin.y + frame.size.height - 15, frame.size.width, 15) withAttributes:subAttr];
}

- (void)drawDpadButton:(CGRect)frame direction:(NSString *)dir active:(BOOL)active context:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:6.0];
    if (active) {
        [[UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.9] setFill];
    } else {
        [[UIColor colorWithWhite:0.15 alpha:0.8] setFill];
    }
    [path fill];
    [[UIColor colorWithWhite:0.6 alpha:0.5] setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    [dir drawInRect:CGRectMake(frame.origin.x, frame.origin.y + 8, frame.size.width, frame.size.height - 8) withAttributes:attr];
}

- (void)drawPillButton:(CGRect)frame label:(NSString *)label active:(BOOL)active context:(CGContextRef)ctx {
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:10.0];
    if (active) {
        [[UIColor whiteColor] setFill];
    } else {
        [[UIColor colorWithWhite:0.15 alpha:0.8] setFill];
    }
    [path fill];
    [[UIColor colorWithWhite:0.6 alpha:0.5] setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName: active ? [UIColor blackColor] : [UIColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    [label drawInRect:CGRectMake(frame.origin.x, frame.origin.y + (frame.size.height - 14) / 2.0, frame.size.width, 16) withAttributes:attr];
}

#pragma mark - Multi-Touch Tracking

- (TouchElement)elementForPoint:(CGPoint)pt {
    // Check Action Buttons
    if (hypot(pt.x - CGRectGetMidX(_btnYFrame), pt.y - CGRectGetMidY(_btnYFrame)) <= _btnYFrame.size.width/2.0 + 8) return TouchElementBtnY;
    if (hypot(pt.x - CGRectGetMidX(_btnXFrame), pt.y - CGRectGetMidY(_btnXFrame)) <= _btnXFrame.size.width/2.0 + 8) return TouchElementBtnX;
    if (hypot(pt.x - CGRectGetMidX(_btnBFrame), pt.y - CGRectGetMidY(_btnBFrame)) <= _btnBFrame.size.width/2.0 + 8) return TouchElementBtnB;
    if (hypot(pt.x - CGRectGetMidX(_btnAFrame), pt.y - CGRectGetMidY(_btnAFrame)) <= _btnAFrame.size.width/2.0 + 8) return TouchElementBtnA;

    // Check Shoulders
    if (CGRectContainsPoint(CGRectInset(_btnRBFrame, -8, -8), pt)) return TouchElementBtnRB;
    if (CGRectContainsPoint(CGRectInset(_btnLBFrame, -8, -8), pt)) return TouchElementBtnLB;
    if (CGRectContainsPoint(CGRectInset(_btnRTFrame, -8, -8), pt)) return TouchElementBtnRT;
    if (CGRectContainsPoint(CGRectInset(_btnLTFrame, -8, -8), pt)) return TouchElementBtnLT;
    if (CGRectContainsPoint(_btnL3Frame, pt)) return TouchElementBtnL3;
    if (CGRectContainsPoint(_btnR3Frame, pt)) return TouchElementBtnR3;

    // Check D-Pad
    if (CGRectContainsPoint(_dpadUpFrame, pt)) return TouchElementDpadUp;
    if (CGRectContainsPoint(_dpadDownFrame, pt)) return TouchElementDpadDown;
    if (CGRectContainsPoint(_dpadLeftFrame, pt)) return TouchElementDpadLeft;
    if (CGRectContainsPoint(_dpadRightFrame, pt)) return TouchElementDpadRight;

    // Check Utilities
    if (CGRectContainsPoint(_btnPauseFrame, pt)) return TouchElementBtnPause;
    if (CGRectContainsPoint(_btnSettingsFrame, pt)) return TouchElementBtnSettings;

    // Check Left Joystick Zone (left half of screen)
    if (pt.x < self.bounds.size.width * 0.4 && pt.y > self.bounds.size.height * 0.4) {
        return TouchElementLeftStick;
    }

    // Check Right Camera Zone (right side interior)
    if (pt.x > self.bounds.size.width * 0.55 && pt.x < _btnXFrame.origin.x && pt.y > self.bounds.size.height * 0.4) {
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
                _leftStickThumbPos = _leftStickCenter;
                _state.thumbLX = 0;
                _state.thumbLY = 0;
            }
            break;
        case TouchElementRightStick:
            if (!pressed) {
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
