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
@property (nonatomic, readonly) NSString *detectedIsoPath;
@property (nonatomic, readonly) BOOL hasExtractedGameData;
@property (nonatomic, readonly) BOOL isIsoExtractionNeeded;
@property (nonatomic, readonly) NSString *documentsDirectory;
@property (nonatomic, readonly) NSString *standardGameDirectory;

+ (instancetype)sharedManager;

// Scans Documents/ and standard directories automatically
- (void)scanAndAutoDetectGameFiles;

// Asynchronous on-device GDFX extractor with progress reporting
- (void)extractDetectedIsoWithProgress:(void(^)(float progress, NSString *status))progressBlock 
                            completion:(void(^)(BOOL success, NSString *errorMsg))completionBlock;

// Human-readable path for user in Files app
- (NSString *)userFriendlyDocumentsPath;

@end
