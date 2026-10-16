#import "DMCAssetManager.h"
#import "dmc4_hooks.h"
#import "DMCBootTrace.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

@interface DMCAssetManager ()
@property (nonatomic, readwrite) DMCAssetStatus status;
@property (nonatomic, readwrite) NSString *statusMessage;
@property (nonatomic, readwrite) NSString *detectedGamePath;
@property (nonatomic, readwrite) NSString *detectedIsoPath;
@property (nonatomic, readwrite) BOOL isIsoDirectMount;
@property (nonatomic, strong) dispatch_source_t fileWatcher;
@end

@implementation DMCAssetManager

+ (instancetype)sharedManager {
    static DMCAssetManager *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[DMCAssetManager alloc] init];
    });
    return s_instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _status = DMCAssetStatusSearching;
        _statusMessage = @"Scanning Documents for DMC 4 files...";
        _isIsoDirectMount = NO;
        [self ensureStandardDirectoriesExist];
        [self setupDirectoryWatcher];
    }
    return self;
}

- (NSString *)documentsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths firstObject];
}

- (NSString *)standardGameDirectory {
    return [[self documentsDirectory] stringByAppendingPathComponent:@"game"];
}

- (NSString *)userFriendlyDocumentsPath {
    return @"Files App > On My iPhone/iPad > Devil May Cry 4 > game/";
}

- (void)ensureStandardDirectoriesExist {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [self documentsDirectory];
    NSString *gameDir = [self standardGameDirectory];
    NSString *savesDir = [docs stringByAppendingPathComponent:@"saves"];
    NSString *logsDir = [docs stringByAppendingPathComponent:@"logs"];
    
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:gameDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:gameDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fm fileExistsAtPath:savesDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:savesDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fm fileExistsAtPath:logsDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)setupDirectoryWatcher {
    int dirFd = open([[self documentsDirectory] fileSystemRepresentation], O_EVTONLY);
    if (dirFd < 0) return;

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _fileWatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, dirFd, 
                                          DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB, queue);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_fileWatcher, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf scanAndAutoDetectGameFiles];
        });
    });

    dispatch_source_set_cancel_handler(_fileWatcher, ^{
        close(dirFd);
    });

    dispatch_resume(_fileWatcher);
}

- (void)scanAndAutoDetectGameFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [self documentsDirectory];
    NSString *gameDir = [self standardGameDirectory];
    
    dmc4::boot::Trace("DMCAssetManager: Auto-scanning: " + std::string([docs UTF8String]));
    self.status = DMCAssetStatusSearching;
    self.statusMessage = @"Scanning for Devil May Cry 4 ISO in Documents...";

    // 1. Direct ISO Detection in Documents/
    NSArray *docItems = [fm contentsOfDirectoryAtPath:docs error:nil];
    for (NSString *item in docItems) {
        if ([[item lowercaseString] hasSuffix:@".iso"]) {
            NSString *isoPath = [docs stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:isoPath error:nil];
            unsigned long long sizeBytes = [attrs fileSize];
            double sizeGB = (double)sizeBytes / (1024.0 * 1024.0 * 1024.0);

            dmc4::boot::Trace("DMCAssetManager: Found Xbox 360 ISO: " + std::string([item UTF8String]) + 
                              " (" + std::to_string(sizeBytes) + " bytes / " + std::to_string(sizeGB) + " GB)");

            // Validate GDFX Partition
            FILE *f = fopen([isoPath fileSystemRepresentation], "rb");
            if (f) {
                uint64_t probeOffsets[] = {0xFD90000ULL, 0x0ULL, 0x10000ULL, 0x2080000ULL};
                bool magicFound = false;
                for (uint64_t off : probeOffsets) {
                    fseeko(f, off, SEEK_SET);
                    char magic[24] = {0};
                    if (fread(magic, 1, 20, f) == 20) {
                        if (memcmp(magic, "MICROSOFT*XBOX*MEDIA", 20) == 0) {
                            magicFound = true;
                            char buf[128];
                            snprintf(buf, sizeof(buf), "DMCAssetManager: GDFX partition magic verified at offset 0x%llX", (unsigned long long)off);
                            dmc4::boot::Trace(buf);
                            break;
                        }
                    }
                }
                fclose(f);
                if (!magicFound) {
                    dmc4::boot::Trace("DMCAssetManager: Note: Non-standard GDFX offset, using virtual container wrapper.");
                }
            }

            self.detectedIsoPath = isoPath;
            self.detectedGamePath = isoPath;
            self.isIsoDirectMount = YES;
            self.status = DMCAssetStatusReady;
            self.statusMessage = [NSString stringWithFormat:@"Xbox 360 ISO Ready: %@ (%.2f GB)", item, sizeGB];
            dmc4::boot::Trace("DMCAssetManager: ISO mount ready: " + std::string([isoPath UTF8String]));
            [self notifyGameReady:isoPath isExecutable:YES];
            return;
        }
    }

    // 2. Direct ISO Detection in Documents/game/
    NSArray *gameItems = [fm contentsOfDirectoryAtPath:gameDir error:nil];
    for (NSString *item in gameItems) {
        if ([[item lowercaseString] hasSuffix:@".iso"]) {
            NSString *isoPath = [gameDir stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:isoPath error:nil];
            unsigned long long sizeBytes = [attrs fileSize];
            double sizeGB = (double)sizeBytes / (1024.0 * 1024.0 * 1024.0);

            dmc4::boot::Trace("DMCAssetManager: Found ISO in game folder: " + std::string([item UTF8String]));
            self.detectedIsoPath = isoPath;
            self.detectedGamePath = isoPath;
            self.isIsoDirectMount = YES;
            self.status = DMCAssetStatusReady;
            self.statusMessage = [NSString stringWithFormat:@"Xbox 360 ISO Ready: %@ (%.2f GB)", item, sizeGB];
            [self notifyGameReady:isoPath isExecutable:YES];
            return;
        }
    }

    // 3. Check for extracted game data in Documents/game/
    BOOL hasGameXex = [fm fileExistsAtPath:[gameDir stringByAppendingPathComponent:@"default.xex"]] ||
                      [fm fileExistsAtPath:[gameDir stringByAppendingPathComponent:@"DEFAULT.XEX"]];
    BOOL hasNativePC = [fm fileExistsAtPath:[gameDir stringByAppendingPathComponent:@"nativePC"]];
    if (hasGameXex || hasNativePC) {
        self.isIsoDirectMount = NO;
        self.detectedIsoPath = nil;
        self.status = DMCAssetStatusReady;
        self.detectedGamePath = gameDir;
        self.statusMessage = [NSString stringWithFormat:@"Game Ready in /game/ (%@%@)", 
                              hasGameXex ? @"default.xex" : @"",
                              (hasGameXex && hasNativePC) ? @" + nativePC" : (hasNativePC ? @"nativePC" : @"")];
        dmc4::boot::Trace("DMCAssetManager: Extracted game detected in " + std::string([gameDir UTF8String]));
        [self notifyGameReady:gameDir isExecutable:YES];
        return;
    }

    // 4. Check for extracted game data directly in Documents/
    BOOL docHasXex = [fm fileExistsAtPath:[docs stringByAppendingPathComponent:@"default.xex"]] ||
                     [fm fileExistsAtPath:[docs stringByAppendingPathComponent:@"DEFAULT.XEX"]];
    BOOL docHasNativePC = [fm fileExistsAtPath:[docs stringByAppendingPathComponent:@"nativePC"]];
    if (docHasXex || docHasNativePC) {
        self.isIsoDirectMount = NO;
        self.detectedIsoPath = nil;
        self.status = DMCAssetStatusReady;
        self.detectedGamePath = docs;
        self.statusMessage = [NSString stringWithFormat:@"Game Ready in /Documents/ (%@%@)",
                              docHasXex ? @"default.xex" : @"",
                              (docHasXex && docHasNativePC) ? @" + nativePC" : (docHasNativePC ? @"nativePC" : @"")];
        dmc4::boot::Trace("DMCAssetManager: Extracted game detected in root Documents: " + std::string([docs UTF8String]));
        [self notifyGameReady:docs isExecutable:YES];
        return;
    }

    // 5. Check if bundled inside App Bundle (e.g. pre-packaged IPA)
    NSString *bundleGameDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"game"];
    if ([fm fileExistsAtPath:bundleGameDir]) {
        BOOL bundleXex = [fm fileExistsAtPath:[bundleGameDir stringByAppendingPathComponent:@"default.xex"]] ||
                         [fm fileExistsAtPath:[bundleGameDir stringByAppendingPathComponent:@"DEFAULT.XEX"]];
        BOOL bundleNpc = [fm fileExistsAtPath:[bundleGameDir stringByAppendingPathComponent:@"nativePC"]];
        if (bundleXex || bundleNpc) {
            self.isIsoDirectMount = NO;
            self.detectedIsoPath = nil;
            self.status = DMCAssetStatusReady;
            self.detectedGamePath = bundleGameDir;
            self.statusMessage = @"Bundled Game Ready (App Bundle /game/)";
            dmc4::boot::Trace("DMCAssetManager: Bundled game detected at: " + std::string([bundleGameDir UTF8String]));
            [self notifyGameReady:bundleGameDir isExecutable:YES];
            return;
        }
    }

    // None found yet
    self.isIsoDirectMount = NO;
    self.detectedIsoPath = nil;
    self.status = DMCAssetStatusNotFound;
    self.statusMessage = [NSString stringWithFormat:@"No game files found.\nPlace Devil May Cry 4 ISO or extracted game/ into:\n%@", [self userFriendlyDocumentsPath]];
    dmc4::boot::Trace("DMCAssetManager: No ISO or game/ data found. Waiting for user to copy files into Documents folder.");
    if ([self.delegate respondsToSelector:@selector(assetManagerDidUpdateStatus:message:)]) {
        [self.delegate assetManagerDidUpdateStatus:self.status message:self.statusMessage];
    }
}

- (void)notifyGameReady:(NSString *)path isExecutable:(BOOL)isExecutable {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(assetManagerDidUpdateStatus:message:)]) {
            [self.delegate assetManagerDidUpdateStatus:self.status message:self.statusMessage];
        }
        if ([self.delegate respondsToSelector:@selector(assetManagerDidFindGameAtPath:isExecutable:)]) {
            [self.delegate assetManagerDidFindGameAtPath:path isExecutable:isExecutable];
        }
    });
}

- (void)dealloc {
    if (_fileWatcher) {
        dispatch_source_cancel(_fileWatcher);
    }
}

@end
