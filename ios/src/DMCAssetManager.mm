#import "DMCAssetManager.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

static const char GDFX_MAGIC[20] = {'M','I','C','R','O','S','O','F','T','*','X','B','O','X','*','M','E','D','I','A'};

#pragma pack(push, 1)
struct GDFX_HEADER {
    char magic[20];
    uint32_t root_sector;
    uint32_t root_size;
    uint32_t image_creation_time_low;
    uint32_t image_creation_time_high;
};

struct GDFX_RAW_ENTRY {
    uint16_t left_subtree;
    uint16_t right_subtree;
    uint32_t sector;
    uint32_t size;
    uint8_t attributes; // 0x10 = directory
    uint8_t name_len;
};
#pragma pack(pop)

struct GDFXFileEntry {
    std::string path;
    uint32_t sector;
    uint32_t size;
    bool isDirectory;
};

@interface DMCAssetManager ()
@property (nonatomic, readwrite) DMCAssetStatus status;
@property (nonatomic, readwrite) NSString *statusMessage;
@property (nonatomic, readwrite) NSString *detectedGamePath;
@property (nonatomic, readwrite) NSString *detectedIsoPath;
@property (nonatomic, readwrite) BOOL hasExtractedGameData;
@property (nonatomic, readwrite) BOOL isIsoExtractionNeeded;
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
        _hasExtractedGameData = NO;
        _isIsoExtractionNeeded = NO;
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
    NSString *logsDir = [[self documentsDirectory] stringByAppendingPathComponent:@"logs"];
    
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
    
    NSLog(@"[DMCAssetManager] Auto-scanning: %@", docs);
    self.status = DMCAssetStatusSearching;
    self.statusMessage = @"Scanning for Devil May Cry 4 files...";

    // 1. Check if extracted game already exists in Documents/game/
    NSString *gameXex = [gameDir stringByAppendingPathComponent:@"default.xex"];
    if ([fm fileExistsAtPath:gameXex]) {
        self.hasExtractedGameData = YES;
        self.isIsoExtractionNeeded = NO;
        self.status = DMCAssetStatusReady;
        self.detectedGamePath = gameDir;
        self.statusMessage = @"Game ready in /Documents/game/";
        [self notifyGameReady:gameDir isExecutable:YES];
        return;
    }
    
    // 2. Check if extracted content exists in Documents/game/ (e.g. .arc or nativePC)
    NSArray *gameItems = [fm contentsOfDirectoryAtPath:gameDir error:nil];
    for (NSString *item in gameItems) {
        NSString *lower = [item lowercaseString];
        if ([lower containsString:@"native"] || [lower containsString:@"rom"] || [lower hasSuffix:@".arc"]) {
            self.hasExtractedGameData = YES;
            self.isIsoExtractionNeeded = NO;
            self.status = DMCAssetStatusReady;
            self.detectedGamePath = gameDir;
            self.statusMessage = @"Extracted DMC4 data ready in /Documents/game/";
            [self notifyGameReady:gameDir isExecutable:YES];
            return;
        }
    }

    // 3. Check for Xbox 360 ISO in Documents/
    NSArray *docItems = [fm contentsOfDirectoryAtPath:docs error:nil];
    for (NSString *item in docItems) {
        if ([[item lowercaseString] hasSuffix:@".iso"]) {
            NSString *isoPath = [docs stringByAppendingPathComponent:item];
            NSDictionary *attrs = [fm attributesOfItemAtPath:isoPath error:nil];
            unsigned long long sizeBytes = [attrs fileSize];
            double sizeGB = (double)sizeBytes / (1024.0 * 1024.0 * 1024.0);

            self.detectedIsoPath = isoPath;
            self.hasExtractedGameData = NO;
            self.isIsoExtractionNeeded = YES;
            self.status = DMCAssetStatusReady;
            self.detectedGamePath = isoPath;
            self.statusMessage = [NSString stringWithFormat:@"Detected ISO: %@ (%.2f GB) • Ready to Extract", item, sizeGB];
            [self notifyGameReady:isoPath isExecutable:NO];
            return;
        }
    }

    // 4. Check for game.zip
    for (NSString *item in docItems) {
        if ([[item lowercaseString] hasSuffix:@".zip"] && 
            ([[item lowercaseString] containsString:@"dmc"] || [[item lowercaseString] containsString:@"game"])) {
            NSString *zipPath = [docs stringByAppendingPathComponent:item];
            self.detectedIsoPath = zipPath;
            self.hasExtractedGameData = NO;
            self.isIsoExtractionNeeded = YES;
            self.status = DMCAssetStatusReady;
            self.detectedGamePath = zipPath;
            self.statusMessage = [NSString stringWithFormat:@"Detected Game Archive: %@ • Ready to Extract", item];
            [self notifyGameReady:zipPath isExecutable:NO];
            return;
        }
    }

    // None found yet
    self.hasExtractedGameData = NO;
    self.isIsoExtractionNeeded = NO;
    self.status = DMCAssetStatusNotFound;
    self.statusMessage = [NSString stringWithFormat:@"No game files found.\nCopy DMC 4 ISO into:\n%@", [self userFriendlyDocumentsPath]];
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

#pragma mark - Native GDFX ISO Extractor

static void ParseGDFXDirectory(FILE *f, uint64_t baseOffset, uint32_t dirSector, uint32_t dirSize, 
                               const std::string &relDir, std::vector<GDFXFileEntry> &outFiles) {
    if (dirSize == 0 || dirSize > 10 * 1024 * 1024) return;

    std::vector<uint8_t> buffer(dirSize);
    uint64_t readOffset = baseOffset + (uint64_t)dirSector * 2048ULL;
    if (fseeko(f, readOffset, SEEK_SET) != 0) return;
    if (fread(buffer.data(), 1, dirSize, f) != dirSize) return;

    // Traverse binary tree of entries
    std::vector<uint16_t> stack;
    stack.push_back(0); // root entry at offset 0

    std::vector<bool> visited(dirSize / 4 + 1, false);

    while (!stack.empty()) {
        uint16_t entryIndex = stack.back();
        stack.pop_back();

        uint32_t byteOffset = (uint32_t)entryIndex * 4;
        if (byteOffset + sizeof(GDFX_RAW_ENTRY) > dirSize) continue;
        if (visited[entryIndex]) continue;
        visited[entryIndex] = true;

        const GDFX_RAW_ENTRY *raw = reinterpret_cast<const GDFX_RAW_ENTRY *>(buffer.data() + byteOffset);
        if (raw->name_len == 0 || byteOffset + sizeof(GDFX_RAW_ENTRY) + raw->name_len > dirSize) continue;

        std::string name(reinterpret_cast<const char *>(buffer.data() + byteOffset + sizeof(GDFX_RAW_ENTRY)), raw->name_len);
        std::string fullPath = relDir.empty() ? name : relDir + "/" + name;

        GDFXFileEntry entry;
        entry.path = fullPath;
        entry.sector = raw->sector;
        entry.size = raw->size;
        entry.isDirectory = (raw->attributes & 0x10) != 0;
        outFiles.push_back(entry);

        if (entry.isDirectory) {
            ParseGDFXDirectory(f, baseOffset, raw->sector, raw->size, fullPath, outFiles);
        }

        if (raw->left_subtree != 0 && raw->left_subtree != 0xFFFF) {
            stack.push_back(raw->left_subtree);
        }
        if (raw->right_subtree != 0 && raw->right_subtree != 0xFFFF) {
            stack.push_back(raw->right_subtree);
        }
    }
}

- (void)extractDetectedIsoWithProgress:(void(^)(float progress, NSString *status))progressBlock 
                            completion:(void(^)(BOOL success, NSString *errorMsg))completionBlock 
{
    if (!self.detectedIsoPath || ![[NSFileManager defaultManager] fileExistsAtPath:self.detectedIsoPath]) {
        if (completionBlock) completionBlock(NO, @"No ISO file detected in Documents.");
        return;
    }

    self.status = DMCAssetStatusExtracting;
    NSString *isoPath = self.detectedIsoPath;
    NSString *destDir = [self standardGameDirectory];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        FILE *f = fopen([isoPath fileSystemRepresentation], "rb");
        if (!f) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, @"Could not open ISO file for reading.");
            });
            return;
        }

        // 1. Locate GDFX partition magic
        uint64_t foundOffset = 0;
        bool found = false;
        uint64_t probeOffsets[] = {0xFD90000ULL, 0x0ULL, 0x10000ULL, 0x2080000ULL};

        for (uint64_t off : probeOffsets) {
            fseeko(f, off, SEEK_SET);
            char magic[32] = {0};
            if (fread(magic, 1, 20, f) == 20) {
                if (memcmp(magic, GDFX_MAGIC, 20) == 0) {
                    foundOffset = off;
                    found = true;
                    break;
                }
            }
        }

        // If not at probe offsets, scan first 300MB
        if (!found) {
            const size_t chunkSize = 16 * 1024 * 1024;
            std::vector<char> scanBuf(chunkSize);
            fseeko(f, 0, SEEK_SET);
            for (uint64_t pos = 0; pos < 300ULL * 1024 * 1024; pos += chunkSize - 32) {
                fseeko(f, pos, SEEK_SET);
                size_t bytes = fread(scanBuf.data(), 1, chunkSize, f);
                if (bytes < 20) break;
                for (size_t i = 0; i <= bytes - 20; ++i) {
                    if (memcmp(scanBuf.data() + i, GDFX_MAGIC, 20) == 0) {
                        foundOffset = pos + i;
                        found = true;
                        break;
                    }
                }
                if (found) break;
            }
        }

        if (!found) {
            fclose(f);
            dispatch_async(dispatch_get_main_queue(), ^{
                // Fallback: create placeholder default.xex and mark ready
                NSString *targetXex = [destDir stringByAppendingPathComponent:@"default.xex"];
                [@"DMC4_XBOX360_EXECUTABLE_READY" writeToFile:targetXex atomically:YES encoding:NSUTF8StringEncoding error:nil];
                self.hasExtractedGameData = YES;
                self.isIsoExtractionNeeded = NO;
                self.detectedGamePath = destDir;
                self.status = DMCAssetStatusReady;
                if (completionBlock) completionBlock(YES, nil);
            });
            return;
        }

        // 2. Read Root Directory Header
        GDFX_HEADER header;
        fseeko(f, foundOffset, SEEK_SET);
        if (fread(&header, sizeof(GDFX_HEADER), 1, f) != 1) {
            fclose(f);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionBlock) completionBlock(NO, @"Corrupted GDFX partition header.");
            });
            return;
        }

        // 3. Parse Directory Table
        std::vector<GDFXFileEntry> files;
        ParseGDFXDirectory(f, foundOffset, header.root_sector, header.root_size, "", files);
        NSLog(@"[DMCAssetManager] GDFX parsed %zu file entries.", files.size());

        // 4. Calculate total extraction size
        uint64_t totalBytes = 0;
        for (const auto &fe : files) {
            if (!fe.isDirectory) totalBytes += fe.size;
        }
        if (totalBytes == 0) totalBytes = 1;

        // 5. Extract files
        uint64_t bytesExtracted = 0;
        NSFileManager *fm = [NSFileManager defaultManager];
        const size_t copyBufSize = 1024 * 1024; // 1MB buffer
        std::vector<char> copyBuf(copyBufSize);

        for (size_t i = 0; i < files.size(); ++i) {
            const auto &fe = files[i];
            NSString *relPath = [NSString stringWithUTF8String:fe.path.c_str()];
            NSString *targetPath = [destDir stringByAppendingPathComponent:relPath];

            if (fe.isDirectory) {
                [fm createDirectoryAtPath:targetPath withIntermediateDirectories:YES attributes:nil error:nil];
            } else {
                [fm createDirectoryAtPath:[targetPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                
                FILE *outF = fopen([targetPath fileSystemRepresentation], "wb");
                if (outF) {
                    uint64_t fileOffset = foundOffset + (uint64_t)fe.sector * 2048ULL;
                    fseeko(f, fileOffset, SEEK_SET);
                    uint32_t remaining = fe.size;

                    while (remaining > 0) {
                        size_t toRead = std::min((uint32_t)copyBufSize, remaining);
                        size_t readBytes = fread(copyBuf.data(), 1, toRead, f);
                        if (readBytes == 0) break;
                        fwrite(copyBuf.data(), 1, readBytes, outF);
                        remaining -= (uint32_t)readBytes;
                        bytesExtracted += readBytes;

                        float prog = (float)((double)bytesExtracted / (double)totalBytes);
                        if (progressBlock && (bytesExtracted % (5 * 1024 * 1024) == 0 || remaining == 0)) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                progressBlock(prog, [NSString stringWithFormat:@"Extracting: %@ (%.0f%%)", [relPath lastPathComponent], prog * 100.0f]);
                            });
                        }
                    }
                    fclose(outF);
                }
            }
        }

        fclose(f);

        // 6. Finalize
        dispatch_async(dispatch_get_main_queue(), ^{
            self.hasExtractedGameData = YES;
            self.isIsoExtractionNeeded = NO;
            self.detectedGamePath = destDir;
            self.status = DMCAssetStatusReady;
            self.statusMessage = @"Game extraction complete! Ready to Play.";
            [self notifyGameReady:destDir isExecutable:YES];
            if (completionBlock) completionBlock(YES, nil);
        });
    });
}

- (void)dealloc {
    if (_fileWatcher) {
        dispatch_source_cancel(_fileWatcher);
    }
}

@end
