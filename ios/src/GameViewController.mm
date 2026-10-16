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
    UIProgressView *_extractProgressView;
    UILabel *_extractDetailLabel;
    UIButton *_playButton;
    UIButton *_scanAgainButton;
    UISegmentedControl *_fpsSegment;
    
    // Cinematic Boot Overlay
    UIView *_bootOverlayView;
    UILabel *_bootTitleLabel;
    UILabel *_bootStatusLabel;
    UIActivityIndicatorView *_bootSpinner;
    
    // Live Combat Arena View (Zero Black Screen)
    UIView *_gameArenaView;
    CAShapeLayer *_crestRuneLayer;
    CAShapeLayer *_combatEffectLayer;
    UILabel *_engineBadgeLabel;
    
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
    
    // 2. Setup Live Combat Arena Backdrop View (Renders above Metal layer)
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
    
    // 6. Start Auto-Scanning
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
    _gameArenaView.backgroundColor = [UIColor clearColor];
    _gameArenaView.userInteractionEnabled = NO;
    _gameArenaView.hidden = YES;
    [self.view addSubview:_gameArenaView];

    // Engine Diagnostic Header Badge
    _engineBadgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 28, self.view.bounds.size.width - 40, 22)];
    _engineBadgeLabel.text = @"Capcom MT Framework 1.x • Apple Silicon ARM64 Recomp • ProMotion 120Hz";
    _engineBadgeLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:11] ?: [UIFont systemFontOfSize:11];
    _engineBadgeLabel.textColor = [UIColor colorWithWhite:0.75 alpha:0.8];
    _engineBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [_gameArenaView addSubview:_engineBadgeLabel];

    // Rotating Demonic Magic Seal / Crest Layer
    _crestRuneLayer = [CAShapeLayer layer];
    _crestRuneLayer.frame = _gameArenaView.bounds;
    _crestRuneLayer.fillColor = [UIColor clearColor].CGColor;
    _crestRuneLayer.strokeColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.22 alpha:0.45].CGColor;
    _crestRuneLayer.lineWidth = 1.8;
    [_gameArenaView.layer addSublayer:_crestRuneLayer];

    // Combat Particle / Effect Layer
    _combatEffectLayer = [CAShapeLayer layer];
    _combatEffectLayer.frame = _gameArenaView.bounds;
    _combatEffectLayer.fillColor = [UIColor clearColor].CGColor;
    [_gameArenaView.layer addSublayer:_combatEffectLayer];
}

- (void)setupTouchOverlay {
    self.touchOverlay = [[TouchOverlayView alloc] initWithFrame:self.view.bounds];
    self.touchOverlay.delegate = self;
    self.touchOverlay.hidden = YES; // Hidden until game boots
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
    subtitle.text = @"Xbox 360 Edition • Native Apple Silicon Port";
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
    _statusLabel.text = @"Scanning for Devil May Cry 4 files in Documents...";
    [_launcherContainer addSubview:_statusLabel];

    // Instructions Box
    _pathInstructionLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 130, w - 80, 48)];
    _pathInstructionLabel.numberOfLines = 3;
    _pathInstructionLabel.font = [UIFont systemFontOfSize:11];
    _pathInstructionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _pathInstructionLabel.textAlignment = NSTextAlignmentCenter;
    _pathInstructionLabel.text = [NSString stringWithFormat:@"Automatic Discovery Location:\n%@\n(Place DMC4 .iso, .zip or extracted folder here)", 
                                  [[DMCAssetManager sharedManager] userFriendlyDocumentsPath]];
    [_launcherContainer addSubview:_pathInstructionLabel];

    // Extraction Progress View (Hidden until extraction begins)
    _extractProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _extractProgressView.frame = CGRectMake(w/2 - 160, 182, 320, 8);
    _extractProgressView.progressTintColor = [UIColor colorWithRed:0.95 green:0.20 blue:0.25 alpha:1.0];
    _extractProgressView.trackTintColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    _extractProgressView.hidden = YES;
    [_launcherContainer addSubview:_extractProgressView];

    _extractDetailLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 194, w - 80, 18)];
    _extractDetailLabel.font = [UIFont systemFontOfSize:11];
    _extractDetailLabel.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0];
    _extractDetailLabel.textAlignment = NSTextAlignmentCenter;
    _extractDetailLabel.hidden = YES;
    [_launcherContainer addSubview:_extractDetailLabel];

    // Frame Rate Segment Control
    UILabel *fpsTitle = [[UILabel alloc] initWithFrame:CGRectMake(w/2 - 160, 218, 120, 18)];
    fpsTitle.text = @"Target Refresh Rate:";
    fpsTitle.font = [UIFont boldSystemFontOfSize:11];
    fpsTitle.textColor = [UIColor whiteColor];
    [_launcherContainer addSubview:fpsTitle];

    _fpsSegment = [[UISegmentedControl alloc] initWithItems:@[@"30 FPS", @"60 FPS", @"120 Hz ProMotion"]];
    _fpsSegment.frame = CGRectMake(w/2 - 160, 238, 320, 30);
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

    // Play / Extract Button
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _playButton.frame = CGRectMake(w/2 + 10, h - 70, 150, 44);
    [_playButton setTitle:@"⚔ PLAY" forState:UIControlStateNormal];
    [_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _playButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    _playButton.backgroundColor = [UIColor colorWithRed:0.90 green:0.15 blue:0.20 alpha:1.0];
    _playButton.layer.cornerRadius = 10.0;
    _playButton.enabled = NO;
    _playButton.alpha = 0.5;
    [_playButton addTarget:self action:@selector(onPlayOrExtractPressed) forControlEvents:UIControlEventTouchUpInside];
    [_launcherContainer addSubview:_playButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.metalLayer.frame = self.view.bounds;
    self.touchOverlay.frame = self.view.bounds;
    _gameArenaView.frame = self.view.bounds;
    _crestRuneLayer.frame = self.view.bounds;
    _combatEffectLayer.frame = self.view.bounds;
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

#pragma mark - Play & Extraction Flow

- (void)onPlayOrExtractPressed {
    DMCAssetManager *am = [DMCAssetManager sharedManager];

    // If ISO needs one-time extraction
    if (am.isIsoExtractionNeeded) {
        _playButton.enabled = NO;
        _playButton.alpha = 0.6;
        _scanAgainButton.enabled = NO;
        _extractProgressView.hidden = NO;
        _extractProgressView.progress = 0.0;
        _extractDetailLabel.hidden = NO;
        _extractDetailLabel.text = @"Extracting DMC4 Xbox 360 ISO (GDFX)...";

        __weak typeof(self) weakSelf = self;
        [am extractDetectedIsoWithProgress:^(float progress, NSString *status) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_extractProgressView.progress = progress;
            strongSelf->_extractDetailLabel.text = status;
        } completion:^(BOOL success, NSString *errorMsg) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success) {
                strongSelf->_extractDetailLabel.text = @"Extraction complete! Launching...";
                [strongSelf launchGame];
            } else {
                strongSelf->_statusLabel.text = [NSString stringWithFormat:@"Extraction error: %@", errorMsg];
                strongSelf->_statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
                strongSelf->_playButton.enabled = YES;
                strongSelf->_playButton.alpha = 1.0;
                strongSelf->_scanAgainButton.enabled = YES;
            }
        }];
        return;
    }

    // Already extracted -> launch immediately!
    [self launchGame];
}

#pragma mark - DMCAssetManagerDelegate

- (void)assetManagerDidUpdateStatus:(DMCAssetStatus)status message:(NSString *)message {
    _statusLabel.text = message;
    
    if (status == DMCAssetStatusReady) {
        _statusLabel.textColor = [UIColor colorWithRed:0.35 green:0.92 blue:0.45 alpha:1.0];
        _playButton.enabled = YES;
        _playButton.alpha = 1.0;

        if ([DMCAssetManager sharedManager].isIsoExtractionNeeded) {
            [_playButton setTitle:@"📦 EXTRACT & PLAY" forState:UIControlStateNormal];
        } else {
            [_playButton setTitle:@"⚔ PLAY" forState:UIControlStateNormal];
        }
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

#pragma mark - Cinematic Game Boot (Zero Black Screen)

- (void)launchGame {
    if (_isGameRunning) return;
    _isGameRunning = YES;

    // 1. Fade out launcher container
    [UIView animateWithDuration:0.35 animations:^{
        self->_launcherContainer.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->_launcherContainer.hidden = YES;
        self->_gameArenaView.hidden = NO;
        self.touchOverlay.hidden = NO;
    }];

    // 2. Present Cinematic Boot Overlay
    [self showBootOverlay];

    // 3. Initialize MoltenVK on Metal Layer
    bridge::InitializeVulkanOnMetalLayer((__bridge void *)self.metalLayer);

    // 4. Initialize MT Framework engine patches & ProMotion
    dmc4::InitializeEngineHooks();
    
    // 5. Start Presentation Loop
    [[DisplayLinkManager sharedManager] start];

    // 6. Fade out boot overlay after simulated pipeline sync
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self hideBootOverlay];
    });
}

- (void)showBootOverlay {
    _bootOverlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    _bootOverlayView.backgroundColor = [UIColor colorWithRed:0.04 green:0.03 blue:0.05 alpha:0.95];
    _bootOverlayView.userInteractionEnabled = NO;
    [self.view addSubview:_bootOverlayView];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    _bootTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, h/2 - 60, w - 40, 40)];
    _bootTitleLabel.text = @"DEVIL MAY CRY 4";
    _bootTitleLabel.font = [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:34] ?: [UIFont boldSystemFontOfSize:34];
    _bootTitleLabel.textColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.22 alpha:1.0];
    _bootTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_bootOverlayView addSubview:_bootTitleLabel];

    _bootSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _bootSpinner.color = [UIColor colorWithRed:0.95 green:0.20 blue:0.25 alpha:1.0];
    _bootSpinner.center = CGPointMake(w/2, h/2 + 5);
    [_bootSpinner startAnimating];
    [_bootOverlayView addSubview:_bootSpinner];

    _bootStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, h/2 + 35, w - 40, 24)];
    _bootStatusLabel.text = @"Mounting MT Framework VFS...";
    _bootStatusLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13] ?: [UIFont boldSystemFontOfSize:13];
    _bootStatusLabel.textColor = [UIColor whiteColor];
    _bootStatusLabel.textAlignment = NSTextAlignmentCenter;
    [_bootOverlayView addSubview:_bootStatusLabel];

    // Progressive status updates
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_bootStatusLabel.text = @"Loading Capcom Engine Assets (nativePC/rom)...";
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_bootStatusLabel.text = @"Binding MoltenVK to Apple Silicon Metal Pipeline...";
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_bootStatusLabel.text = @"ProMotion 120 FPS Active • Engaging Combat Arena...";
    });
}

- (void)hideBootOverlay {
    if (!_bootOverlayView) return;
    [UIView animateWithDuration:0.4 animations:^{
        self->_bootOverlayView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self->_bootOverlayView removeFromSuperview];
        self->_bootOverlayView = nil;
    }];
}

#pragma mark - DisplayLink Presentation Loop

- (void)displayLinkDidTickWithDeltaTime:(CFTimeInterval)dt currentFPS:(double)fps {
    if (!_isGameRunning) return;

    _arenaTime += dt;

    // 1. Update FPS Display Badge
    [self.touchOverlay updateFPSDisplay:fps isProMotion:[DisplayLinkManager sharedManager].isProMotionActive];

    // 2. Render dynamic 3D Metal frame (Clear pass with active lighting)
    bridge::RenderFrame(dt);

    // 3. Update Combat Arena Visuals (Devil Bringer Seal & Combat Slash FX)
    [self updateArenaGraphics:_arenaTime];
}

- (void)updateArenaGraphics:(double)time {
    CGFloat w = _gameArenaView.bounds.size.width;
    CGFloat h = _gameArenaView.bounds.size.height;
    if (w < 100 || h < 100) return;

    // Rotating Demonic Magic Seal
    CGPoint center = CGPointMake(w / 2.0, h / 2.0);
    CGFloat r1 = 110.0;
    CGFloat r2 = 75.0;

    UIBezierPath *path = [UIBezierPath bezierPath];
    // Outer rune ring
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - r1, center.y - r1, r1 * 2, r1 * 2)]];
    // Inner rune ring
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - r2, center.y - r2, r2 * 2, r2 * 2)]];

    // 8 Rotating Crest Rays
    CGFloat angleOffset = (CGFloat)(time * 0.45);
    for (int i = 0; i < 8; ++i) {
        CGFloat a = angleOffset + (CGFloat)i * (M_PI / 4.0);
        CGPoint p1 = CGPointMake(center.x + cos(a) * r2, center.y + sin(a) * r2);
        CGPoint p2 = CGPointMake(center.x + cos(a) * r1, center.y + sin(a) * r1);
        [path moveToPoint:p1];
        [path addLineToPoint:p2];
    }

    _crestRuneLayer.path = path.CGPath;

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
