#import "GameViewController.h"
#import "dmc4_hooks.h"
#import "vulkan_metal_bridge.h"

@interface GameViewController () {
    UIView *_launcherContainer;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_pathInstructionLabel;
    UIButton *_playButton;
    UIButton *_scanAgainButton;
    UISegmentedControl *_fpsSegment;
    UISegmentedControl *_resSegment;
    
    BOOL _isGameRunning;
}
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    // 1. Setup Metal Render Layer
    [self setupMetalLayer];
    
    // 2. Setup Touch Controls Overlay
    [self setupTouchOverlay];
    
    // 3. Setup Beautiful Gothic Launcher UI
    [self setupLauncherUI];
    
    // 4. Connect Controllers & Display
    [DisplayLinkManager sharedManager].delegate = self;
    [ControllerManager sharedManager].delegate = self;
    [[ControllerManager sharedManager] startMonitoring];
    
    [DMCAssetManager sharedManager].delegate = self;
    
    // 5. Start Auto-Scanning
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
}

- (void)setupTouchOverlay {
    self.touchOverlay = [[TouchOverlayView alloc] initWithFrame:self.view.bounds];
    self.touchOverlay.delegate = self;
    self.touchOverlay.hidden = YES; // Hidden until game launches
    [self.view addSubview:self.touchOverlay];
}

- (void)setupLauncherUI {
    _launcherContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    _launcherContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _launcherContainer.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.95];
    [self.view addSubview:_launcherContainer];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Title: DEVIL MAY CRY 4
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 25, w - 40, 36)];
    _titleLabel.text = @"DEVIL MAY CRY 4";
    _titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:30] ?: [UIFont boldSystemFontOfSize:30];
    _titleLabel.textColor = [UIColor colorWithRed:0.9 green:0.15 blue:0.18 alpha:1.0];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_launcherContainer addSubview:_titleLabel];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 62, w - 40, 18)];
    subtitle.text = @"Xbox 360 Edition • Native Apple Silicon Port";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [_launcherContainer addSubview:subtitle];

    // Status Label
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 95, w - 80, 48)];
    _statusLabel.numberOfLines = 2;
    _statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = @"Auto-detecting game data in Documents...";
    [_launcherContainer addSubview:_statusLabel];

    // Instructions Box
    _pathInstructionLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 145, w - 80, 52)];
    _pathInstructionLabel.numberOfLines = 3;
    _pathInstructionLabel.font = [UIFont systemFontOfSize:12];
    _pathInstructionLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    _pathInstructionLabel.textAlignment = NSTextAlignmentCenter;
    _pathInstructionLabel.text = [NSString stringWithFormat:@"Automatic Discovery Location:\n%@\n(Place DMC4 .iso, .zip or extracted folder here)", 
                                  [[DMCAssetManager sharedManager] userFriendlyDocumentsPath]];
    [_launcherContainer addSubview:_pathInstructionLabel];

    // Options Control: ProMotion & Resolution
    UILabel *fpsTitle = [[UILabel alloc] initWithFrame:CGRectMake(w/2 - 170, 205, 120, 20)];
    fpsTitle.text = @"Frame Rate:";
    fpsTitle.font = [UIFont boldSystemFontOfSize:12];
    fpsTitle.textColor = [UIColor whiteColor];
    [_launcherContainer addSubview:fpsTitle];

    _fpsSegment = [[UISegmentedControl alloc] initWithItems:@[@"30 FPS", @"60 FPS", @"120 Hz ProMotion"]];
    _fpsSegment.frame = CGRectMake(w/2 - 170, 228, 340, 32);
    _fpsSegment.selectedSegmentIndex = 2; // Default to 120Hz ProMotion
    [_fpsSegment addTarget:self action:@selector(fpsSettingChanged:) forControlEvents:UIControlEventValueChanged];
    [_launcherContainer addSubview:_fpsSegment];

    // Scan Again Button
    _scanAgainButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _scanAgainButton.frame = CGRectMake(w/2 - 140, h - 85, 130, 44);
    [_scanAgainButton setTitle:@"🔄 Scan Again" forState:UIControlStateNormal];
    [_scanAgainButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _scanAgainButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
    _scanAgainButton.layer.cornerRadius = 10.0;
    [_scanAgainButton addTarget:self action:@selector(onScanAgainPressed) forControlEvents:UIControlEventTouchUpInside];
    [_launcherContainer addSubview:_scanAgainButton];

    // Play Button (Large Crimson Accent)
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _playButton.frame = CGRectMake(w/2 + 10, h - 85, 130, 44);
    [_playButton setTitle:@"⚔ PLAY" forState:UIControlStateNormal];
    [_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _playButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    _playButton.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.2 alpha:1.0];
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
}

- (void)fpsSettingChanged:(UISegmentedControl *)sender {
    NSInteger target = 60;
    if (sender.selectedSegmentIndex == 0) target = 30;
    else if (sender.selectedSegmentIndex == 1) target = 60;
    else if (sender.selectedSegmentIndex == 2) target = 120;

    [[DisplayLinkManager sharedManager] setTargetFramerate:target];
}

- (void)onScanAgainPressed {
    [[DMCAssetManager sharedManager] scanAndAutoDetectGameFiles];
}

#pragma mark - DMCAssetManagerDelegate

- (void)assetManagerDidUpdateStatus:(DMCAssetStatus)status message:(NSString *)message {
    _statusLabel.text = message;
    
    if (status == DMCAssetStatusReady) {
        _statusLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1.0];
        _playButton.enabled = YES;
        _playButton.alpha = 1.0;
    } else if (status == DMCAssetStatusExtracting) {
        _statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0];
        _playButton.enabled = NO;
        _playButton.alpha = 0.5;
    } else {
        _statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
        _playButton.enabled = NO;
        _playButton.alpha = 0.5;
    }
}

- (void)assetManagerDidFindGameAtPath:(NSString *)path isExecutable:(BOOL)isExecutable {
    NSLog(@"[GameViewController] Valid game path verified: %@ (exe: %d)", path, isExecutable);
    dmc4::SetGameRootDirectory([path fileSystemRepresentation]);
}

#pragma mark - Game Launch & Run Loop

- (void)launchGame {
    if (_isGameRunning) return;
    _isGameRunning = YES;

    // Fade out launcher
    [UIView animateWithDuration:0.4 animations:^{
        self->_launcherContainer.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->_launcherContainer.hidden = YES;
        self.touchOverlay.hidden = NO;
    }];

    // Initialize MoltenVK on Metal Layer
    bridge::InitializeVulkanOnMetalLayer((__bridge void *)self.metalLayer);

    // Apply 120Hz ProMotion hooks to MT Framework
    dmc4::InitializeEngineHooks();
    
    // Start CADisplayLink Presentation loop
    [[DisplayLinkManager sharedManager] start];
    NSLog(@"[GameViewController] Devil May Cry 4 successfully launched!");
}

#pragma mark - DisplayLinkManagerDelegate (VSync)

- (void)displayLinkDidTickWithDeltaTime:(CFTimeInterval)dt currentFPS:(double)fps {
    if (!_isGameRunning) return;

    // Update Touch Overlay FPS Pill Badge
    [self.touchOverlay updateFPSDisplay:fps isProMotion:[DisplayLinkManager sharedManager].isProMotionActive];

    // Tick game engine and render frame
    bridge::RenderFrame(dt);
}

#pragma mark - TouchOverlayViewDelegate

- (void)touchOverlayDidChangeGamepadState:(const VirtualGamepadState *)state {
    dmc4::UpdateControllerState(state);
}

- (void)touchOverlayDidPressPause {
    NSLog(@"[GameViewController] Pause button pressed");
}

- (void)touchOverlayDidPressSettings {
    // Reveal settings overlay
    [UIView animateWithDuration:0.3 animations:^{
        self->_launcherContainer.hidden = NO;
        self->_launcherContainer.alpha = 0.95;
    }];
}

#pragma mark - ControllerManagerDelegate

- (void)controllerManagerDidConnectController:(GCController *)controller {
    // Smoothly fade out virtual touch HUD when a physical gamepad is detected
    [UIView animateWithDuration:0.3 animations:^{
        self.touchOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.touchOverlay.controlsHidden = YES;
    }];
}

- (void)controllerManagerDidDisconnectController:(GCController *)controller {
    // Restore virtual touch HUD if physical gamepad disconnected
    self.touchOverlay.controlsHidden = NO;
    [UIView animateWithDuration:0.3 animations:^{
        self.touchOverlay.alpha = 0.85;
    }];
}

- (void)controllerManagerDidUpdateState:(const VirtualGamepadState *)state {
    dmc4::UpdateControllerState(state);
}

@end
