#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DMCAssetStatus) {
    DMCAssetStatusSearching,
    DMCAssetStatusReady,
    DMCAssetStatusNotFound,
    DMCAssetStatusError
};

@protocol DMCAssetManagerDelegate <NSObject>
@optional
- (void)assetManagerDidUpdateStatus:(DMCAssetStatus)status message:(NSString *)message;
- (void)assetManagerDidFindGameAtPath:(NSString *)path isExecutable:(BOOL)isExecutable;
@end

@interface DMCAssetManager : NSObject

@property (nonatomic, weak) id<DMCAssetManagerDelegate> delegate;
@property (nonatomic, readonly) DMCAssetStatus status;
@property (nonatomic, readonly) NSString *statusMessage;
@property (nonatomic, readonly) NSString *detectedGamePath;
@property (nonatomic, readonly) NSString *detectedIsoPath;
@property (nonatomic, readonly) BOOL isIsoDirectMount;
@property (nonatomic, readonly) NSString *documentsDirectory;
@property (nonatomic, readonly) NSString *standardGameDirectory;

+ (instancetype)sharedManager;

// Scans Documents/ and standard directories automatically
- (void)scanAndAutoDetectGameFiles;

// Human-readable path for user in Files app
- (NSString *)userFriendlyDocumentsPath;

@end
