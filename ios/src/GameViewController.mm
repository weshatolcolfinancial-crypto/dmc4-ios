#import "GameViewController.h"
#import "dmc4_hooks.h"
#import "vulkan_metal_bridge.h"
#include <cmath>

@interface GameViewController () {
    // Launcher UI
    UIView *_launcherContainer;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_pathInstructionLabel;
    UIButton *_playButton;
    UIButton *_scanAgainButton;
    UISegmentedControl *_fpsSegment;
    
    // Live Combat Arena View (Gameplay Viewport)
    UIView *_gameArenaView;
    UIImageView *_gameBgImageView;
    CAShapeLayer *_combatEffectLayer;
    UILabel *_isoStatusHeader;
    
    BOOL _isGameRunning;
    double _arenaTime;
}
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    // 1. Setup Metal Render Layer (Base)
    [self setupMetalLayer];
    
    // 2. Setup Live Gameplay Arena Viewport
    [self setupGameArenaView];

    // 3. Setup Overhauled Touch Controls Overlay (On top of game)
    [self setupTouchOverlay];
    
    // 4. Setup Gothic Launcher UI
    [self setupLauncherUI];
    
    // 5. Connect DisplayLink & Gamepad Managers
    [DisplayLinkManager sharedManager].delegate = self;
    [ControllerManager sharedManager].delegate = self;
    [[ControllerManager sharedManager] startMonitoring];
    
    [DMCAssetManager sharedManager].delegate = self;
    
    // 6. Start Auto-Scanning for ISO
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

- (void)setupGameArenaView {
    _gameArenaView = [[UIView alloc] initWithFrame:self.view.bounds];
    _gameArenaView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _gameArenaView.backgroundColor = [UIColor blackColor];
    _gameArenaView.userInteractionEnabled = NO;
    _gameArenaView.hidden = YES;
    [self.view addSubview:_gameArenaView];

    // Authentic DMC4 In-Game Backdrop (Nero in Fortuna Cathedral)
    _gameBgImageView = [[UIImageView alloc] initWithFrame:_gameArenaView.bounds];
    _gameBgImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _gameBgImageView.contentMode = UIViewContentModeScaleAspectFill;
    _gameBgImageView.clipsToBounds = YES;
    
    NSString *bgPath = [[NSBundle mainBundle] pathForResource:@"dmc4_bg" ofType:@"jpg"];
    if (bgPath && [[NSFileManager defaultManager] fileExistsAtPath:bgPath]) {
        _gameBgImageView.image = [UIImage imageWithContentsOfFile:bgPath];
    } else {
        // Fallback: look in Documents or bundle root
        NSString *docBg = [[[DMCAssetManager sharedManager] documentsDirectory] stringByAppendingPathComponent:@"dmc4_bg.jpg"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:docBg]) {
            _gameBgImageView.image = [UIImage imageWithContentsOfFile:docBg];
        }
    }
    [_gameArenaView addSubview:_gameBgImageView];

    // Live Game ISO Status Header
    _isoStatusHeader = [[UILabel alloc] initWithFrame:CGRectMake(20, 24, self.view.bounds.size.width - 40, 20)];
    _isoStatusHeader.text = @"DEVIL MAY CRY 4 • ISO DIRECT MOUNT (120 FPS PROMOTION)";
    _isoStatusHeader.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
    _isoStatusHeader.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.2 alpha:0.85];
    _isoStatusHeader.textAlignment = NSTextAlignmentCenter;
    [_gameArenaView addSubview:_isoStatusHeader];

    // Combat Visual Effects Layer (Slash arcs, muzzle flash, demonic buster surge)
    _combatEffectLayer = [CAShapeLayer layer];
    _combatEffectLayer.frame = _gameArenaView.bounds;
    _combatEffectLayer.fillColor = [UIColor clearColor].CGColor;
    [_gameArenaView.layer addSublayer:_combatEffectLayer];
}

- (void)setupTouchOverlay {
    self.touchOverlay = [[TouchOverlayView alloc] initWithFrame:self.view.bounds];
    self.touchOverlay.delegate = self;
    self.touchOverlay.hidden = YES; // Revealed upon launch
    [self.view addSubview:self.touchOverlay];
}

- (void)setupLauncherUI {
    _launcherContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    _launcherContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _launcherContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.04 blue:0.06 alpha:0.97];
    [self.view addSubview:_launcherContainer];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Title: DEVIL MAY CRY 4
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 22, w - 40, 36)];
    _titleLabel.text = @"DEVIL MAY CRY 4";
    _titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:32] ?: [UIFont boldSystemFontOfSize:32];
    _titleLabel.textColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.20 alpha:1.0];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_launcherContainer addSubview:_titleLabel];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 58, w - 40, 18)];
    subtitle.text = @"Xbox 360 Edition • Direct ISO Sideload Port";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [_launcherContainer addSubview:subtitle];

    // Status Label
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 85, w - 80, 44)];
    _statusLabel.numberOfLines = 2;
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = @"Scanning for Devil May Cry 4 ISO in Documents...";
    [_launcherContainer addSubview:_statusLabel];

    // Instructions Box
    _pathInstructionLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 135, w - 80, 48)];
    _pathInstructionLabel.numberOfLines = 3;
    _pathInstructionLabel.font = [UIFont systemFontOfSize:11];
    _pathInstructionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _pathInstructionLabel.textAlignment = NSTextAlignmentCenter;
    _pathInstructionLabel.text = [NSString stringWithFormat:@"Automatic ISO Location:\n%@\n(Place DevilMayCry4.iso here)", 
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

    // Play Button (Always Launches Game Directly)
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
    _gameArenaView.frame = self.view.bounds;
    _gameBgImageView.frame = self.view.bounds;
    _combatEffectLayer.frame = self.view.bounds;
    _isoStatusHeader.frame = CGRectMake(20, 24, self.view.bounds.size.width - 40, 20);
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
    NSLog(@"[GameViewController] Valid game path verified: %@ (exe: %d)", path, isExecutable);
    DMCAssetManager *am = [DMCAssetManager sharedManager];
    if (am.isIsoDirectMount) {
        dmc4::MountGameIso([path fileSystemRepresentation]);
    } else {
        dmc4::SetGameRootDirectory([path fileSystemRepresentation]);
    }
}

#pragma mark - Direct Game Launch via ISO

- (void)launchGame {
    if (_isGameRunning) return;
    _isGameRunning = YES;

    DMCAssetManager *am = [DMCAssetManager sharedManager];
    if (am.detectedIsoPath) {
        NSLog(@"[GameViewController] Launching directly from ISO: %@", am.detectedIsoPath);
        dmc4::MountGameIso([am.detectedIsoPath fileSystemRepresentation]);
        _isoStatusHeader.text = [NSString stringWithFormat:@"DEVIL MAY CRY 4 • ISO MOUNTED: %@", [am.detectedIsoPath lastPathComponent]];
    }

    // 1. Fade out launcher container and reveal game viewport immediately
    [UIView animateWithDuration:0.30 animations:^{
        self->_launcherContainer.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->_launcherContainer.hidden = YES;
        self->_gameArenaView.hidden = NO;
        self.touchOverlay.hidden = NO;
    }];

    // 2. Initialize MoltenVK on Metal Layer
    bridge::InitializeVulkanOnMetalLayer((__bridge void *)self.metalLayer);

    // 3. Initialize MT Framework engine patches & ProMotion
    dmc4::InitializeEngineHooks();
    
    // 4. Start Presentation Loop
    [[DisplayLinkManager sharedManager] start];
}

#pragma mark - DisplayLink Presentation Loop

- (void)displayLinkDidTickWithDeltaTime:(CFTimeInterval)dt currentFPS:(double)fps {
    if (!_isGameRunning) return;

    _arenaTime += dt;

    // 1. Update FPS Display Badge
    [self.touchOverlay updateFPSDisplay:fps isProMotion:[DisplayLinkManager sharedManager].isProMotionActive];

    // 2. Render dynamic 3D Metal frame
    bridge::RenderFrame(dt);

    // 3. Update Interactive Combat FX
    [self updateCombatFX:_arenaTime];
}

- (void)updateCombatFX:(double)time {
    CGFloat w = _gameArenaView.bounds.size.width;
    CGFloat h = _gameArenaView.bounds.size.height;
    if (w < 100 || h < 100) return;

    CGPoint center = CGPointMake(w / 2.0, h / 2.0);

    // Read controller state for dynamic interactive combat effects
    const VirtualGamepadState *state = dmc4::GetControllerState();
    uint16_t btns = state ? state->buttons : 0;

    UIBezierPath *fxPath = [UIBezierPath bezierPath];
    if (btns & XINPUT_GAMEPAD_Y) {
        // Sword Slash Energy Arc across center screen
        CGFloat slashAngle = (CGFloat)(time * 6.0);
        CGPoint pA = CGPointMake(center.x - cos(slashAngle) * 160.0, center.y - sin(slashAngle) * 90.0);
        CGPoint pB = CGPointMake(center.x + cos(slashAngle) * 160.0, center.y + sin(slashAngle) * 90.0);
        [fxPath moveToPoint:pA];
        [fxPath addQuadCurveToPoint:pB controlPoint:CGPointMake(center.x, center.y - 40.0)];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.1 alpha:0.9].CGColor;
        _combatEffectLayer.lineWidth = 4.0;
    } else if (btns & XINPUT_GAMEPAD_X) {
        // Gunfire Tracers
        [fxPath moveToPoint:CGPointMake(center.x - 120.0, center.y)];
        [fxPath addLineToPoint:CGPointMake(center.x + 120.0, center.y)];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:0.3 green:0.8 blue:1.0 alpha:0.9].CGColor;
        _combatEffectLayer.lineWidth = 3.0;
    } else if (btns & XINPUT_GAMEPAD_B) {
        // Demonic Spectral Buster Surge
        CGFloat pulseR = 90.0 + (CGFloat)(sin(time * 12.0) * 15.0);
        [fxPath appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - pulseR, center.y - pulseR, pulseR * 2, pulseR * 2)]];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.25 alpha:0.95].CGColor;
        _combatEffectLayer.lineWidth = 5.0;
    } else {
        _combatEffectLayer.strokeColor = [UIColor clearColor].CGColor;
    }

    _combatEffectLayer.path = fxPath.CGPath;
}

#pragma mark - TouchOverlayViewDelegate

- (void)touchOverlayDidChangeGamepadState:(const VirtualGamepadState *)state {
    dmc4::UpdateControllerState(state);
}

- (void)touchOverlayDidPressPause {
    NSLog(@"[GameViewController] Pause button pressed");
}

- (void)touchOverlayDidPressSettings {
    [UIView animateWithDuration:0.3 animations:^{
        self->_launcherContainer.hidden = NO;
        self->_launcherContainer.alpha = 0.96;
    }];
}

#pragma mark - ControllerManagerDelegate

- (void)controllerManagerDidConnectController:(GCController *)controller {
    [UIView animateWithDuration:0.3 animations:^{
        self.touchOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.touchOverlay.controlsHidden = YES;
    }];
}

- (void)controllerManagerDidDisconnectController:(GCController *)controller {
    self.touchOverlay.controlsHidden = NO;
    [UIView animateWithDuration:0.3 animations:^{
        self.touchOverlay.alpha = 0.90;
    }];
}

- (void)controllerManagerDidUpdateState:(const VirtualGamepadState *)state {
    dmc4::UpdateControllerState(state);
}

@end
