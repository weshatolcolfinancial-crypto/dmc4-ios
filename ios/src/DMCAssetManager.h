#pragma once

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DMCAssetStatus) {
    DMCAssetStatusSearching,
    DMCAssetStatusReady,
    DMCAssetStatusExtracting,
    DMCAssetStatusNotFound,
    DMCAssetStatusError
};

@protocol DMCAssetManagerDelegate <NSObject>
@optional
- (void)assetManagerDidUpdateStatus:(DMCAssetStatus)status message:(NSString *)message;
- (void)assetManagerDidProgressExtraction:(float)progress detail:(NSString *)detail;
- (void)assetManagerDidFindGameAtPath:(NSString *)path isExecutable:(BOOL)isExecutable;
@end

@interface DMCAssetManager : NSObject

@property (nonatomic, weak) id<DMCAssetManagerDelegate> delegate;
@property (nonatomic, readonly) DMCAssetStatus status;
@property (nonatomic, readonly) NSString *statusMessage;
@property (nonatomic, readonly) NSString *detectedGamePath;
@property (nonatomic, readonly) NSString *documentsDirectory;
@property (nonatomic, readonly) NSString *standardGameDirectory;

+ (instancetype)sharedManager;

// Scans Documents/ and standard directories automatically without requiring file picker
- (void)scanAndAutoDetectGameFiles;

// Helper to manually extract an ISO or ZIP if needed
- (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath;

// Human-readable path for user in Files app
- (NSString *)userFriendlyDocumentsPath;

@end
