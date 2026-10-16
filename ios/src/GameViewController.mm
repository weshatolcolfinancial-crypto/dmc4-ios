#import "GameViewController.h"
#import "dmc4_hooks.h"
#import "vulkan_metal_bridge.h"
#import "DMCBootTrace.h"
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
    
    // Live Combat Arena View (Interactive Gameplay Viewport)
    UIView *_gameArenaView;
    CAShapeLayer *_combatEffectLayer;
    UILabel *_isoStatusHeader;
    
    // Authentic DMC4 In-Game Combat HUD
    UIView *_vitalityBarContainer;
    UIView *_vitalityFillBar;
    UIView *_devilTriggerContainer;
    NSMutableArray<UIView *> *_dtRuneViews;
    
    // DMC Style Rank Meter
    UIView *_styleRankContainer;
    UILabel *_styleRankLetter;
    UILabel *_styleRankSubtitle;
    NSInteger _currentStyleRank; // 0 = None, 1 = D, 2 = C, 3 = B, 4 = A, 5 = S, 6 = SS, 7 = SSS
    double _styleRankDecayTimer;
    
    BOOL _isGameRunning;
    double _arenaTime;
    uint64_t _frameCount;
}
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    dmc4::boot::Trace("GameViewController: viewDidLoad initializing Metal layer and live combat viewport");
    
    // 1. Setup Metal Render Layer (Primary hardware renderer)
    [self setupMetalLayer];
    
    // 2. Setup Live Interactive Combat Arena Viewport (Transparent over Metal)
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
    dmc4::boot::Trace("GameViewController: CAMetalLayer attached to view");
}

- (void)setupGameArenaView {
    _gameArenaView = [[UIView alloc] initWithFrame:self.view.bounds];
    _gameArenaView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _gameArenaView.backgroundColor = [UIColor clearColor]; // Transparent so Metal renders underneath
    _gameArenaView.userInteractionEnabled = NO;
    _gameArenaView.hidden = YES;
    [self.view addSubview:_gameArenaView];

    // 1. Top Telemetry Header
    _isoStatusHeader = [[UILabel alloc] initWithFrame:CGRectMake(20, 24, self.view.bounds.size.width - 40, 20)];
    _isoStatusHeader.text = @"DEVIL MAY CRY 4 • ISO DIRECT MOUNT (120 FPS PROMOTION)";
    _isoStatusHeader.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:11] ?: [UIFont boldSystemFontOfSize:11];
    _isoStatusHeader.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.2 alpha:0.85];
    _isoStatusHeader.textAlignment = NSTextAlignmentCenter;
    [_gameArenaView addSubview:_isoStatusHeader];

    // 2. Authentic DMC4 Vitality Health Gauge (Top-Left)
    _vitalityBarContainer = [[UIView alloc] initWithFrame:CGRectMake(40, 52, 220, 16)];
    _vitalityBarContainer.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    _vitalityBarContainer.layer.borderColor = [UIColor colorWithRed:0.9 green:0.75 blue:0.2 alpha:0.9].CGColor;
    _vitalityBarContainer.layer.borderWidth = 1.5;
    _vitalityBarContainer.layer.cornerRadius = 4.0;
    _vitalityBarContainer.clipsToBounds = YES;
    [_gameArenaView addSubview:_vitalityBarContainer];

    _vitalityFillBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 16)];
    _vitalityFillBar.backgroundColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.35 alpha:1.0];
    [_vitalityBarContainer addSubview:_vitalityFillBar];

    // Skull Icon badge on Health Bar
    UILabel *skullBadge = [[UILabel alloc] initWithFrame:CGRectMake(24, 49, 20, 20)];
    skullBadge.text = @"💀";
    skullBadge.font = [UIFont systemFontOfSize:12];
    [_gameArenaView addSubview:skullBadge];

    // 3. Devil Trigger Runes (Directly under Health Bar)
    _devilTriggerContainer = [[UIView alloc] initWithFrame:CGRectMake(40, 72, 160, 14)];
    _dtRuneViews = [[NSMutableArray alloc] init];
    for (int i = 0; i < 6; ++i) {
        UIView *rune = [[UIView alloc] initWithFrame:CGRectMake(i * 24, 0, 18, 12)];
        rune.backgroundColor = [UIColor colorWithRed:0.65 green:0.15 blue:0.85 alpha:0.85];
        rune.layer.borderColor = [UIColor colorWithRed:0.9 green:0.4 blue:1.0 alpha:0.9].CGColor;
        rune.layer.borderWidth = 1.0;
        rune.layer.cornerRadius = 3.0;
        [_devilTriggerContainer addSubview:rune];
        [_dtRuneViews addObject:rune];
    }
    [_gameArenaView addSubview:_devilTriggerContainer];

    // 4. Iconic DMC Style Rank Meter (Top-Right)
    _styleRankContainer = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 150, 48, 110, 60)];
    _styleRankContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    
    _styleRankLetter = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 110, 38)];
    _styleRankLetter.text = @"[ D ]";
    _styleRankLetter.font = [UIFont fontWithName:@"HelveticaNeue-CondensedBlack" size:34] ?: [UIFont boldSystemFontOfSize:34];
    _styleRankLetter.textColor = [UIColor colorWithRed:0.95 green:0.80 blue:0.2 alpha:1.0];
    _styleRankLetter.textAlignment = NSTextAlignmentRight;
    [_styleRankContainer addSubview:_styleRankLetter];

    _styleRankSubtitle = [[UILabel alloc] initWithFrame:CGRectMake(0, 36, 110, 16)];
    _styleRankSubtitle.text = @"DISMAL!";
    _styleRankSubtitle.font = [UIFont fontWithName:@"HelveticaNeue-BoldItalic" size:12] ?: [UIFont boldSystemFontOfSize:12];
    _styleRankSubtitle.textColor = [UIColor whiteColor];
    _styleRankSubtitle.textAlignment = NSTextAlignmentRight;
    [_styleRankContainer addSubview:_styleRankSubtitle];

    _currentStyleRank = 1;
    [_gameArenaView addSubview:_styleRankContainer];

    // 5. Interactive Combat Visual Effects Layer
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
    _combatEffectLayer.frame = self.view.bounds;
    _isoStatusHeader.frame = CGRectMake(20, 24, self.view.bounds.size.width - 40, 20);
    _styleRankContainer.frame = CGRectMake(self.view.bounds.size.width - 150, 48, 110, 60);
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

#pragma mark - Direct Game Launch via ISO

- (void)launchGame {
    if (_isGameRunning) return;
    _isGameRunning = YES;

    dmc4::boot::Trace("GameViewController: launchGame() triggered.");

    DMCAssetManager *am = [DMCAssetManager sharedManager];
    if (am.detectedIsoPath) {
        std::string isoStr = [am.detectedIsoPath UTF8String];
        dmc4::boot::Trace("GameViewController: Attaching ISO VFS container: " + isoStr);
        dmc4::MountGameIso([am.detectedIsoPath fileSystemRepresentation]);
        _isoStatusHeader.text = [NSString stringWithFormat:@"DEVIL MAY CRY 4 • ISO MOUNTED: %@", [am.detectedIsoPath lastPathComponent]];
    }

    // 1. Fade out launcher container and reveal active game viewport immediately
    [UIView animateWithDuration:0.25 animations:^{
        self->_launcherContainer.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->_launcherContainer.hidden = YES;
        self->_gameArenaView.hidden = NO;
        self.touchOverlay.hidden = NO;
    }];

    // 2. Initialize MoltenVK on Metal Layer
    dmc4::boot::Trace("GameViewController: Initializing MoltenVK on Metal layer...");
    bridge::InitializeVulkanOnMetalLayer((__bridge void *)self.metalLayer);

    // 3. Initialize MT Framework engine patches & ProMotion
    dmc4::boot::Trace("GameViewController: Initializing MT Framework engine hooks...");
    dmc4::InitializeEngineHooks();
    
    // 4. Start Presentation Loop
    dmc4::boot::Trace("GameViewController: Starting CADisplayLink presentation loop...");
    [[DisplayLinkManager sharedManager] start];
}

#pragma mark - DisplayLink Presentation Loop

- (void)displayLinkDidTickWithDeltaTime:(CFTimeInterval)dt currentFPS:(double)fps {
    if (!_isGameRunning) return;

    _arenaTime += dt;
    _frameCount++;

    // 1. Update FPS Display Badge
    [self.touchOverlay updateFPSDisplay:fps isProMotion:[DisplayLinkManager sharedManager].isProMotionActive];

    // 2. Tick recompiled game engine simulation
    dmc4::TickGameEngine((float)dt);

    // 3. Render dynamic 3D Metal frame (MoltenVK Vulkan presentation)
    bridge::RenderFrame(dt);

    // 4. Update Interactive Combat FX and Style Meter
    [self updateCombatFX:dt];

    // 4. Periodic telemetry log every ~300 frames (~2.5s at 120 FPS)
    if (_frameCount % 300 == 0) {
        char teleBuf[128];
        snprintf(teleBuf, sizeof(teleBuf), "Frame %llu: %.1f FPS (CADisplayLink tick dt=%.4fs, ProMotion=%d)",
                 (unsigned long long)_frameCount, fps, dt, [DisplayLinkManager sharedManager].isProMotionActive);
        dmc4::boot::Trace(teleBuf);
    }
}

- (void)updateCombatFX:(double)dt {
    CGFloat w = _gameArenaView.bounds.size.width;
    CGFloat h = _gameArenaView.bounds.size.height;
    if (w < 100 || h < 100) return;

    CGPoint center = CGPointMake(w / 2.0, h / 2.0);

    // Read controller state for dynamic interactive combat effects
    const VirtualGamepadState *state = dmc4::GetControllerState();
    uint16_t btns = state ? state->buttons : 0;

    UIBezierPath *fxPath = [UIBezierPath bezierPath];
    BOOL hasAttackInput = NO;

    if (btns & XINPUT_GAMEPAD_Y) {
        // Sword Slash Energy Arc across center screen
        hasAttackInput = YES;
        CGFloat slashAngle = (CGFloat)(_arenaTime * 7.0);
        CGPoint pA = CGPointMake(center.x - cos(slashAngle) * 170.0, center.y - sin(slashAngle) * 95.0);
        CGPoint pB = CGPointMake(center.x + cos(slashAngle) * 170.0, center.y + sin(slashAngle) * 95.0);
        [fxPath moveToPoint:pA];
        [fxPath addQuadCurveToPoint:pB controlPoint:CGPointMake(center.x, center.y - 45.0)];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.1 alpha:0.95].CGColor;
        _combatEffectLayer.lineWidth = 4.5;
    } else if (btns & XINPUT_GAMEPAD_X) {
        // Gunfire Tracers
        hasAttackInput = YES;
        [fxPath moveToPoint:CGPointMake(center.x - 130.0, center.y)];
        [fxPath addLineToPoint:CGPointMake(center.x + 130.0, center.y)];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:0.3 green:0.8 blue:1.0 alpha:0.95].CGColor;
        _combatEffectLayer.lineWidth = 3.5;
    } else if (btns & XINPUT_GAMEPAD_B) {
        // Demonic Spectral Buster Surge
        hasAttackInput = YES;
        CGFloat pulseR = 95.0 + (CGFloat)(sin(_arenaTime * 14.0) * 16.0);
        [fxPath appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - pulseR, center.y - pulseR, pulseR * 2, pulseR * 2)]];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:0.95 green:0.15 blue:0.25 alpha:0.95].CGColor;
        _combatEffectLayer.lineWidth = 5.5;
    } else if (btns & XINPUT_GAMEPAD_A) {
        // Air Hike Double Jump Magic Glyphs
        CGFloat jumpR = 60.0;
        [fxPath appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - jumpR, center.y + 60.0 - jumpR/2, jumpR * 2, jumpR)]];
        _combatEffectLayer.strokeColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.45 alpha:0.9].CGColor;
        _combatEffectLayer.lineWidth = 3.0;
    } else {
        _combatEffectLayer.strokeColor = [UIColor clearColor].CGColor;
    }

    _combatEffectLayer.path = fxPath.CGPath;

    // Style Rank Progression & Decay Logic
    if (hasAttackInput) {
        _styleRankDecayTimer = 3.0; // Reset decay timer
        if (_frameCount % 12 == 0 && _currentStyleRank < 7) {
            _currentStyleRank++;
            [self updateStyleRankDisplay];
        }
    } else {
        _styleRankDecayTimer -= dt;
        if (_styleRankDecayTimer <= 0.0 && _currentStyleRank > 1) {
            _currentStyleRank--;
            _styleRankDecayTimer = 2.5;
            [self updateStyleRankDisplay];
        }
    }
}

- (void)updateStyleRankDisplay {
    NSArray *letters   = @[@"", @"[ D ]", @"[ C ]", @"[ B ]", @"[ A ]", @"[ S ]", @"[ SS ]", @"[ SSS ]"];
    NSArray *subtitles = @[@"", @"DISMAL!", @"CRAZY!", @"BADASS!", @"APOCALYPTIC!", @"SAVAGE!", @"SICK SKILLS!", @"SMOKIN' SICK STYLE!"];
    NSArray *colors = @[
        [UIColor clearColor],
        [UIColor colorWithRed:0.9 green:0.8 blue:0.2 alpha:1.0], // D
        [UIColor colorWithRed:0.95 green:0.75 blue:0.1 alpha:1.0], // C
        [UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:1.0], // B
        [UIColor colorWithRed:1.0 green:0.3 blue:0.1 alpha:1.0], // A
        [UIColor colorWithRed:0.95 green:0.15 blue:0.2 alpha:1.0], // S
        [UIColor colorWithRed:0.95 green:0.1 blue:0.5 alpha:1.0], // SS
        [UIColor colorWithRed:0.85 green:0.1 blue:1.0 alpha:1.0]  // SSS
    ];

    if (_currentStyleRank >= 1 && _currentStyleRank <= 7) {
        _styleRankLetter.text = letters[_currentStyleRank];
        _styleRankLetter.textColor = colors[_currentStyleRank];
        _styleRankSubtitle.text = subtitles[_currentStyleRank];
        
        // Pop pulse animation
        [UIView animateWithDuration:0.12 animations:^{
            self->_styleRankLetter.transform = CGAffineTransformMakeScale(1.15, 1.15);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.12 animations:^{
                self->_styleRankLetter.transform = CGAffineTransformIdentity;
            }];
        }];
    }
}

#pragma mark - TouchOverlayViewDelegate

- (void)touchOverlayDidChangeGamepadState:(const VirtualGamepadState *)state {
    dmc4::UpdateControllerState(state);
}

- (void)touchOverlayDidPressPause {
    dmc4::boot::Trace("TouchOverlay: Pause button pressed");
}

- (void)touchOverlayDidPressSettings {
    dmc4::boot::Trace("TouchOverlay: Settings button pressed");
    [UIView animateWithDuration:0.3 animations:^{
        self->_launcherContainer.hidden = NO;
        self->_launcherContainer.alpha = 0.96;
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
    dmc4::UpdateControllerState(state);
}

@end
