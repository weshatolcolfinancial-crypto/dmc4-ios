#import "ControllerManager.h"

@interface ControllerManager () {
    VirtualGamepadState _physicalState;
}
@end

@implementation ControllerManager

+ (instancetype)sharedManager {
    static ControllerManager *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[ControllerManager alloc] init];
    });
    return s_instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        memset(&_physicalState, 0, sizeof(VirtualGamepadState));
    }
    return self;
}

- (BOOL)hasPhysicalControllerConnected {
    return ([GCController controllers].count > 0);
}

- (void)startMonitoring {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleControllerDidConnect:) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(handleControllerDidDisconnect:) name:GCControllerDidDisconnectNotification object:nil];

    for (GCController *c in [GCController controllers]) {
        [self setupControllerHandlers:c];
    }
}

- (void)stopMonitoring {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleControllerDidConnect:(NSNotification *)note {
    GCController *controller = note.object;
    NSLog(@"[ControllerManager] Gamepad Connected: %@", controller.vendorName);
    [self setupControllerHandlers:controller];
    
    if ([self.delegate respondsToSelector:@selector(controllerManagerDidConnectController:)]) {
        [self.delegate controllerManagerDidConnectController:controller];
    }
}

- (void)handleControllerDidDisconnect:(NSNotification *)note {
    GCController *controller = note.object;
    NSLog(@"[ControllerManager] Gamepad Disconnected: %@", controller.vendorName);
    
    if ([self.delegate respondsToSelector:@selector(controllerManagerDidDisconnectController:)]) {
        [self.delegate controllerManagerDidDisconnectController:controller];
    }
}

- (void)setupControllerHandlers:(GCController *)controller {
    GCExtendedGamepad *gamepad = controller.extendedGamepad;
    if (!gamepad) return;

    __weak typeof(self) weakSelf = self;
    gamepad.valueChangedHandler = ^(GCExtendedGamepad * _Nonnull pad, GCControllerElement * _Nonnull element) {
        [weakSelf updateStateFromGamepad:pad];
    };
}

- (void)updateStateFromGamepad:(GCExtendedGamepad *)pad {
    memset(&_physicalState, 0, sizeof(VirtualGamepadState));

    if (pad.buttonA.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_A;
    if (pad.buttonB.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_B;
    if (pad.buttonX.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_X;
    if (pad.buttonY.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_Y;

    if (pad.leftShoulder.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_LEFT_SHOULDER;
    if (pad.rightShoulder.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_RIGHT_SHOULDER;

    if (pad.dpad.up.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_DPAD_UP;
    if (pad.dpad.down.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_DPAD_DOWN;
    if (pad.dpad.left.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_DPAD_LEFT;
    if (pad.dpad.right.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_DPAD_RIGHT;

    if (pad.buttonMenu.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_START;
    if (pad.buttonOptions && pad.buttonOptions.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_BACK;

    if (pad.leftThumbstickButton && pad.leftThumbstickButton.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_LEFT_THUMB;
    if (pad.rightThumbstickButton && pad.rightThumbstickButton.isPressed) _physicalState.buttons |= XINPUT_GAMEPAD_RIGHT_THUMB;

    _physicalState.leftTrigger = (uint8_t)(pad.leftTrigger.value * 255.0);
    _physicalState.rightTrigger = (uint8_t)(pad.rightTrigger.value * 255.0);

    _physicalState.thumbLX = (int16_t)(pad.leftThumbstick.xAxis.value * 32767.0);
    _physicalState.thumbLY = (int16_t)(pad.leftThumbstick.yAxis.value * 32767.0);

    _physicalState.thumbRX = (int16_t)(pad.rightThumbstick.xAxis.value * 32767.0);
    _physicalState.thumbRY = (int16_t)(pad.rightThumbstick.yAxis.value * 32767.0);

    if ([self.delegate respondsToSelector:@selector(controllerManagerDidUpdateState:)]) {
        [self.delegate controllerManagerDidUpdateState:&_physicalState];
    }
}

- (void)dealloc {
    [self stopMonitoring];
}

@end
