#import "GameViewController.h"
#import "dmc4_hooks.h"
#import "vulkan_metal_bridge.h"
#import "DMCBootTrace.h"

@interface GameViewController () {
    // Launcher Pre-Game UI
    UIView *_launcherContainer;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_pathInstructionLabel;
    UIButton *_playButton;
    UIButton *_scanAgainButton;
    UISegmentedControl *_fpsSegment;
    
    BOOL _isGameRunning;
    uint64_t _frameCount;
    VirtualGamepadState _gamepadState;
}
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    dmc4::boot::Trace("GameViewController: viewDidLoad initializing Metal layer and native game viewport");
    
    // 1. Setup Metal Render Layer (Native hardware presentation surface)
    [self setupMetalLayer];

    // 2. Setup DMC Touch Controls Overlay (Hardware gamepad controls)
    [self setupTouchOverlay];
    
    // 3. Setup Pre-Launch Configuration UI
    [self setupLauncherUI];
    
    // 4. Connect DisplayLink & Gamepad Managers
    [DisplayLinkManager sharedManager].delegate = self;
    [ControllerManager sharedManager].delegate = self;
    [[ControllerManager sharedManager] startMonitoring];
    
    [DMCAssetManager sharedManager].delegate = self;
    
    // 5. Start Auto-Scanning for Game Data
    [[DMCAssetManager sharedManager] scanAndAutoDetectGameFiles];
}

- (void)setupMetalLayer {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self.metalLayer = [CAMetalLayer layer];
    self.metalLayer.device = device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = YES;
    self.metalLayer.frame = self.view.bounds;
    self.metalLayer.contentsScale = [UIScreen mainScreen].nativeScale;
    [self.view.layer addSublayer:self.metalLayer];
    dmc4::boot::Trace("GameViewController: CAMetalLayer attached to view");
}

- (void)setupTouchOverlay {
    self.touchOverlay = [[TouchOverlayView alloc] initWithFrame:self.view.bounds];
    self.touchOverlay.delegate = self;
    self.touchOverlay.hidden = YES; // Revealed upon launching the game
    [self.view addSubview:self.touchOverlay];
}

- (void)setupLauncherUI {
    _launcherContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    _launcherContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _launcherContainer.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:0.98];
    [self.view addSubview:_launcherContainer];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Title: DEVIL MAY CRY 4
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 24, w - 40, 36)];
    _titleLabel.text = @"DEVIL MAY CRY 4";
    _titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:32] ?: [UIFont boldSystemFontOfSize:32];
    _titleLabel.textColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.20 alpha:1.0];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_launcherContainer addSubview:_titleLabel];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, w - 40, 18)];
    subtitle.text = @"Capcom MT Framework • Xbox 360 Port for Apple Silicon";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [_launcherContainer addSubview:subtitle];

    // Status Label
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 90, w - 80, 44)];
    _statusLabel.numberOfLines = 2;
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = @"Scanning for Devil May Cry 4 files in Documents...";
    [_launcherContainer addSubview:_statusLabel];

    // Instructions Box
    _pathInstructionLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 140, w - 80, 50)];
    _pathInstructionLabel.numberOfLines = 3;
    _pathInstructionLabel.font = [UIFont systemFontOfSize:11];
    _pathInstructionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _pathInstructionLabel.textAlignment = NSTextAlignmentCenter;
    _pathInstructionLabel.text = [NSString stringWithFormat:@"Game Folder Location:\n%@\n(Place default.xex and nativePC/ here)", 
                                  [[DMCAssetManager sharedManager] userFriendlyDocumentsPath]];
    [_launcherContainer addSubview:_pathInstructionLabel];

    // Frame Rate Segment Control
    UILabel *fpsTitle = [[UILabel alloc] initWithFrame:CGRectMake(w/2 - 160, 205, 140, 18)];
    fpsTitle.text = @"Target Refresh Rate:";
    fpsTitle.font = [UIFont boldSystemFontOfSize:11];
    fpsTitle.textColor = [UIColor whiteColor];
    [_launcherContainer addSubview:fpsTitle];

    _fpsSegment = [[UISegmentedControl alloc] initWithItems:@[@"30 FPS", @"60 FPS", @"120 Hz ProMotion"]];
    _fpsSegment.frame = CGRectMake(w/2 - 160, 226, 320, 30);
    _fpsSegment.selectedSegmentIndex = 2; // Default 120Hz ProMotion
    [_fpsSegment addTarget:self action:@selector(fpsSettingChanged:) forControlEvents:UIControlEventValueChanged];
    [_launcherContainer addSubview:_fpsSegment];

    // Scan Again Button
    _scanAgainButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _scanAgainButton.frame = CGRectMake(w/2 - 150, h - 70, 140, 44);
    [_scanAgainButton setTitle:@"🔄 Scan Again" forState:UIControlStateNormal];
    [_scanAgainButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _scanAgainButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    _scanAgainButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.85];
    _scanAgainButton.layer.cornerRadius = 10.0;
    [_scanAgainButton addTarget:self action:@selector(onScanAgainPressed) forControlEvents:UIControlEventTouchUpInside];
    [_launcherContainer addSubview:_scanAgainButton];

    // Play Button (Launches Real Game Engine)
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _playButton.frame = CGRectMake(w/2 + 10, h - 70, 150, 44);
    [_playButton setTitle:@"⚔ PLAY" forState:UIControlStateNormal];
    [_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _playButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    _playButton.backgroundColor = [UIColor colorWithRed:0.90 green:0.15 blue:0.20 alpha:1.0];
    _playButton.layer.cornerRadius = 10.0;
    _playButton.enabled = NO;
    _playButton.alpha = 0.5;
    [_playButton addTarget:self action:@selector(launchGame) forControlEvents:UIControlEventTouchUpInside];
    [_launcherContainer addSubview:_playButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.metalLayer.frame = self.view.bounds;
    self.touchOverlay.frame = self.view.bounds;
    _launcherContainer.frame = self.view.bounds;
}

- (void)fpsSettingChanged:(UISegmentedControl *)sender {
    NSInteger target = 60;
    if (sender.selectedSegmentIndex == 0) target = 30;
    else if (sender.selectedSegmentIndex == 1) target = 60;
    else if (sender.selectedSegmentIndex == 2) target = 120;

    [[DisplayLinkManager sharedManager] setTargetFramerate:target];
    dmc4::boot::Trace("GameViewController: Framerate preset changed to " + std::to_string(target) + " FPS");
}

- (void)onScanAgainPressed {
    dmc4::boot::Trace("GameViewController: Scan Again pressed.");
    [[DMCAssetManager sharedManager] scanAndAutoDetectGameFiles];
}

#pragma mark - DMCAssetManagerDelegate

- (void)assetManagerDidUpdateStatus:(DMCAssetStatus)status message:(NSString *)message {
    _statusLabel.text = message;
    
    if (status == DMCAssetStatusReady) {
        _statusLabel.textColor = [UIColor colorWithRed:0.35 green:0.92 blue:0.45 alpha:1.0];
        _playButton.enabled = YES;
        _playButton.alpha = 1.0;
        [_playButton setTitle:@"⚔ PLAY" forState:UIControlStateNormal];
    } else {
        _statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
        _playButton.enabled = NO;
        _playButton.alpha = 0.5;
    }
}

- (void)assetManagerDidFindGameAtPath:(NSString *)path isExecutable:(BOOL)isExecutable {
    dmc4::boot::Trace("GameViewController: Verified game asset path: " + std::string([path UTF8String]));
    DMCAssetManager *am = [DMCAssetManager sharedManager];
    if (am.isIsoDirectMount) {
        dmc4::MountGameIso([path fileSystemRepresentation]);
    } else {
        dmc4::SetGameRootDirectory([path fileSystemRepresentation]);
    }
}

#pragma mark - Game Launch

- (void)launchGame {
    if (_isGameRunning) return;
    _isGameRunning = YES;

    dmc4::boot::Trace("GameViewController: launchGame() triggered.");

    DMCAssetManager *am = [DMCAssetManager sharedManager];
    if (am.detectedIsoPath) {
        dmc4::MountGameIso([am.detectedIsoPath fileSystemRepresentation]);
    } else if (am.detectedGamePath) {
        dmc4::SetGameRootDirectory([am.detectedGamePath fileSystemRepresentation]);
    }

    // 1. Hide launcher container and reveal active game viewport immediately
    [UIView animateWithDuration:0.2 animations:^{
        self->_launcherContainer.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->_launcherContainer.hidden = YES;
        self.touchOverlay.hidden = NO;
    }];

    // 2. Initialize graphics bridge on CAMetalLayer
    dmc4::boot::Trace("GameViewController: Initializing MoltenVK graphics bridge on Metal layer...");
    bridge::InitializeVulkanOnMetalLayer((__bridge void *)self.metalLayer);

    // 3. Initialize MT Framework engine hooks and load game executable
    dmc4::boot::Trace("GameViewController: Booting Capcom MT Framework engine and loading default.xex...");
    dmc4::InitializeEngineHooks();
    
    // 4. Start CADisplayLink Presentation Loop
    dmc4::boot::Trace("GameViewController: Starting CADisplayLink presentation loop...");
    [[DisplayLinkManager sharedManager] start];
}

#pragma mark - DisplayLink Presentation Loop

- (void)displayLinkDidTickWithDeltaTime:(CFTimeInterval)dt currentFPS:(double)fps {
    if (!_isGameRunning) return;
    _frameCount++;

    // 1. Update FPS Display Badge on Touch Overlay
    [self.touchOverlay updateFPSDisplay:fps isProMotion:[DisplayLinkManager sharedManager].isProMotionActive];

    // 2. Advance game engine simulation tick
    dmc4::TickGameEngine((float)dt);

    // 3. Render hardware graphics frame
    bridge::RenderFrame(dt);

    // 4. Telemetry trace every 300 frames (~2.5s at 120 FPS, ~5s at 60 FPS)
    if (_frameCount % 300 == 0) {
        char teleBuf[128];
        snprintf(teleBuf, sizeof(teleBuf), "Frame %llu: %.1f FPS (CADisplayLink dt=%.4fs, ProMotion=%d)",
                 (unsigned long long)_frameCount, fps, dt, [DisplayLinkManager sharedManager].isProMotionActive);
        dmc4::boot::Trace(teleBuf);
    }
}

#pragma mark - TouchOverlayViewDelegate

- (void)touchOverlayDidChangeGamepadState:(const VirtualGamepadState *)state {
    if (state) {
        memcpy(&_gamepadState, state, sizeof(VirtualGamepadState));
        dmc4::UpdateControllerState(state);
    }
}

- (void)touchOverlayDidPressPause {
    dmc4::boot::Trace("TouchOverlay: Pause button pressed");
}

- (void)touchOverlayDidPressSettings {
    dmc4::boot::Trace("TouchOverlay: Settings button pressed");
    [UIView animateWithDuration:0.25 animations:^{
        self->_launcherContainer.hidden = NO;
        self->_launcherContainer.alpha = 0.98;
    }];
}

#pragma mark - ControllerManagerDelegate

- (void)controllerManagerDidConnectController:(GCController *)controller {
    dmc4::boot::Trace("ControllerManager: Game controller connected: " + std::string([controller.vendorName UTF8String]));
    [UIView animateWithDuration:0.3 animations:^{
        self.touchOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.touchOverlay.controlsHidden = YES;
    }];
}

- (void)controllerManagerDidDisconnectController:(GCController *)controller {
    dmc4::boot::Trace("ControllerManager: Game controller disconnected.");
    self.touchOverlay.controlsHidden = NO;
    [UIView animateWithDuration:0.3 animations:^{
        self.touchOverlay.alpha = 0.90;
    }];
}

- (void)controllerManagerDidUpdateState:(const VirtualGamepadState *)state {
    if (state) {
        memcpy(&_gamepadState, state, sizeof(VirtualGamepadState));
        dmc4::UpdateControllerState(state);
    }
}

@end
