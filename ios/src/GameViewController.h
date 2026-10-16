#pragma once

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "DMCAssetManager.h"
#import "DisplayLinkManager.h"
#import "TouchOverlayView.h"
#import "ControllerManager.h"

@interface GameViewController : UIViewController <DMCAssetManagerDelegate, DisplayLinkManagerDelegate, TouchOverlayViewDelegate, ControllerManagerDelegate>

@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) TouchOverlayView *touchOverlay;

// Starts the game loop once files are detected and user hits Play
- (void)launchGame;

@end
