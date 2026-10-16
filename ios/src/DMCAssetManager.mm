#import "DMCAssetManager.h"

@interface DMCAssetManager ()
@property (nonatomic, readwrite) DMCAssetStatus status;
@property (nonatomic, readwrite) NSString *statusMessage;
@property (nonatomic, readwrite) NSString *detectedGamePath;
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
    NSString *gameDir = [self standardGameDirectory];
    NSString *savesDir = [[self documentsDirectory] stringByAppendingPathComponent:@"saves"];
    
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:gameDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:gameDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fm fileExistsAtPath:savesDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:savesDir withIntermediateDirectories:YES attributes:nil error:nil];
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
    
    NSLog(@"[DMCAssetManager] Auto-scanning: %@", docs);
    self.status = DMCAssetStatusSearching;
    self.statusMessage = @"Scanning for Devil May Cry 4 files...";
    
    // Check 1: Documents/game/default.xex or native game content
    NSString *gameXex = [gameDir stringByAppendingPathComponent:@"default.xex"];
    if ([fm fileExistsAtPath:gameXex]) {
        self.status = DMCAssetStatusReady;
        self.detectedGamePath = gameDir;
        self.statusMessage = [NSString stringWithFormat:@"Game verified in: /Documents/game/"];
        [self notifyGameReady:gameDir isExecutable:YES];
        return;
    }
    
    // Check 2: Documents/default.xex directly
    NSString *directXex = [docs stringByAppendingPathComponent:@"default.xex"];
    if ([fm fileExistsAtPath:directXex]) {
        self.status = DMCAssetStatusReady;
        self.detectedGamePath = docs;
        self.statusMessage = @"Game executable found in Documents/";
        [self notifyGameReady:docs isExecutable:YES];
        return;
    }

    // Check 3: Check Documents/game/ for unpacked content directories
    NSError *error = nil;
    NSArray *gameItems = [fm contentsOfDirectoryAtPath:gameDir error:&error];
    if (gameItems.count > 0) {
        // Look for common MT Framework or DMC4 files: .arc files, nativePC, rom, etc.
        for (NSString *item in gameItems) {
            NSString *lower = [item lowercaseString];
            if ([lower containsString:@"native"] || [lower containsString:@"rom"] || [lower hasSuffix:@".arc"] || [lower hasSuffix:@".xex"]) {
                self.status = DMCAssetStatusReady;
                self.detectedGamePath = gameDir;
                self.statusMessage = @"Extracted DMC4 data detected in /Documents/game/";
                [self notifyGameReady:gameDir isExecutable:NO];
                return;
            }
        }
    }

    // Check 4: Check for Xbox 360 ISO in Documents/ or Documents/game/
    NSArray *docItems = [fm contentsOfDirectoryAtPath:docs error:nil];
    for (NSString *item in docItems) {
        if ([[item lowercaseString] hasSuffix:@".iso"]) {
            NSString *isoPath = [docs stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:isoPath error:nil];
            unsigned long long sizeBytes = [attrs fileSize];
            double sizeGB = (double)sizeBytes / (1024.0 * 1024.0 * 1024.0);

            self.status = DMCAssetStatusReady;
            self.detectedGamePath = isoPath;
            self.statusMessage = [NSString stringWithFormat:@"Detected ISO: %@ (%.2f GB)", item, sizeGB];
            [self notifyGameReady:isoPath isExecutable:NO];
            return;
        }
    }

    // Check 5: Check for game.zip / dmc4.zip in Documents
    for (NSString *item in docItems) {
        if ([[item lowercaseString] hasSuffix:@".zip"] && 
            ([[item lowercaseString] containsString:@"dmc"] || [[item lowercaseString] containsString:@"game"])) {
            NSString *zipPath = [docs stringByAppendingPathComponent:item];
            self.status = DMCAssetStatusReady;
            self.detectedGamePath = zipPath;
            self.statusMessage = [NSString stringWithFormat:@"Detected Game Archive: %@", item];
            [self notifyGameReady:zipPath isExecutable:NO];
            return;
        }
    }

    // None found yet
    self.status = DMCAssetStatusNotFound;
    self.statusMessage = [NSString stringWithFormat:@"No game files found.\nCopy DMC 4 files into:\n%@", [self userFriendlyDocumentsPath]];
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

- (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath {
    // ReXGlue virtual file system mounts archives directly
    self.status = DMCAssetStatusReady;
    self.detectedGamePath = archivePath;
    [self notifyGameReady:archivePath isExecutable:NO];
    return YES;
}

- (void)dealloc {
    if (_fileWatcher) {
        dispatch_source_cancel(_fileWatcher);
    }
}

@end
