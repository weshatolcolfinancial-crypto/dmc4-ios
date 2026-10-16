#pragma once

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import "TouchOverlayView.h"

@protocol ControllerManagerDelegate <NSObject>
@optional
- (void)controllerManagerDidConnectController:(GCController *)controller;
- (void)controllerManagerDidDisconnectController:(GCController *)controller;
- (void)controllerManagerDidUpdateState:(const VirtualGamepadState *)state;
@end

@interface ControllerManager : NSObject

@property (nonatomic, weak) id<ControllerManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL hasPhysicalControllerConnected;

+ (instancetype)sharedManager;

- (void)startMonitoring;
- (void)stopMonitoring;

@end
