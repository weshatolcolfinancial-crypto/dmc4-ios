#import "DMCBootTrace.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <exception>
#include <iostream>

namespace dmc4::boot {

static std::atomic<int> g_bootFd{-1};
static struct sigaction g_prevSignals[32];
static NSString *g_logsDir = nil;

static void WriteRaw(const char *text, size_t len) {
    int fd = g_bootFd.load(std::memory_order_acquire);
    if (fd < 0) return;
    while (len > 0) {
        ssize_t n = write(fd, text, len);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            return;
        }
        text += n;
        len -= (size_t)n;
    }
}

static void OnFatalSignal(int sig, siginfo_t *info, void *context) {
    char buf[128];
    const char *sigName = "UNKNOWN";
    if (sig == SIGSEGV) sigName = "SIGSEGV (Segmentation Fault)";
    else if (sig == SIGBUS) sigName = "SIGBUS (Bus Error)";
    else if (sig == SIGABRT) sigName = "SIGABRT (Abort)";
    else if (sig == SIGILL) sigName = "SIGILL (Illegal Instruction)";
    else if (sig == SIGFPE) sigName = "SIGFPE (Floating Point Exception)";

    int n = snprintf(buf, sizeof(buf), "\n[FATAL] Signal %d: %s at fault address: %p\n",
                     sig, sigName, info ? info->si_addr : nullptr);
    if (n > 0) {
        WriteRaw(buf, (size_t)n);
    }

    const struct sigaction &prev = g_prevSignals[sig];
    if (prev.sa_flags & SA_SIGINFO) {
        if (prev.sa_sigaction) {
            prev.sa_sigaction(sig, info, context);
            return;
        }
    } else if (prev.sa_handler != SIG_DFL && prev.sa_handler != SIG_IGN && prev.sa_handler) {
        prev.sa_handler(sig);
        return;
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void OnTerminate() {
    std::string line = "FATAL std::terminate invoked";
    if (auto e = std::current_exception()) {
        try {
            std::rethrow_exception(e);
        } catch (const std::exception &ex) {
            line += std::string(": ") + ex.what();
        } catch (...) {
            line += ": unknown exception type";
        }
    }
    Trace(line);
    std::abort();
}

NSString *GetLogsDirectoryPath() {
    if (!g_logsDir) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = [paths firstObject];
        g_logsDir = [docs stringByAppendingPathComponent:@"logs"];
    }
    return g_logsDir;
}

void InitializeLogging() {
    NSString *logsDir = GetLogsDirectoryPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:logsDir isDirectory:&isDir]) {
        [fm createDirectoryAtPath:logsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // 1. Open Documents/logs/boot.txt (Unbuffered startup trace, rotating old logs)
    NSString *bootPath = [logsDir stringByAppendingPathComponent:@"boot.txt"];
    NSString *bootPrevPath = [logsDir stringByAppendingPathComponent:@"boot.prev.txt"];
    [fm removeItemAtPath:bootPrevPath error:nil];
    [fm moveItemAtPath:bootPath toPath:bootPrevPath error:nil];

    int fd = open([bootPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd >= 0) {
        g_bootFd.store(fd, std::memory_order_release);
    }

    // Install crash interceptors
    std::set_terminate(OnTerminate);
    for (int sig : {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE}) {
        struct sigaction sa{};
        sa.sa_sigaction = OnFatalSignal;
        sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&sa.sa_mask);
        sigaction(sig, &sa, &g_prevSignals[sig]);
    }

    // 2. Redirect stdout and stderr to Documents/logs/dmc4.log (rotating old logs)
    NSString *dmcLogPath = [logsDir stringByAppendingPathComponent:@"dmc4.log"];
    NSString *dmcPrevLogPath = [logsDir stringByAppendingPathComponent:@"dmc4.prev.log"];
    [fm removeItemAtPath:dmcPrevLogPath error:nil];
    [fm moveItemAtPath:dmcLogPath toPath:dmcPrevLogPath error:nil];

    FILE *fout = freopen([dmcLogPath fileSystemRepresentation], "w+", stdout);
    FILE *ferr = freopen([dmcLogPath fileSystemRepresentation], "w+", stderr);
    if (fout) setvbuf(stdout, NULL, _IOLBF, 1024);
    if (ferr) setvbuf(stderr, NULL, _IONBF, 0);

    // Initial boot trace header
    Trace("=================================================================");
    Trace("Devil May Cry 4 (Xbox 360) Native iOS Port - Boot Log");
    Trace("Build: " __DATE__ " " __TIME__ " (arm64 Apple Silicon)");
    Trace("Logs directory initialized at: " + std::string([logsDir UTF8String]));
    Trace("boot.txt and dmc4.log active and streaming");

    // Device telemetry
    UIDevice *dev = [UIDevice currentDevice];
    Trace("Device: " + std::string([dev.model UTF8String]) + " (" + std::string([dev.systemName UTF8String]) + " " + std::string([dev.systemVersion UTF8String]) + ")");

    id<MTLDevice> metal = MTLCreateSystemDefaultDevice();
    if (metal) {
        Trace("Metal GPU: " + std::string([metal.name UTF8String]));
    }

    UIScreen *screen = [UIScreen mainScreen];
    char scBuf[128];
    snprintf(scBuf, sizeof(scBuf), "Display: %.0fx%.0f @ %.1fx (Maximum Refresh Rate: %ld Hz)",
             screen.bounds.size.width, screen.bounds.size.height, screen.scale, (long)screen.maximumFramesPerSecond);
    Trace(scBuf);
    Trace("=================================================================");

    std::cout << "[DMC4_Engine] Logging redirected to dmc4.log successfully." << std::endl;
}

void Trace(const std::string &message) {
    const auto now = std::chrono::system_clock::now();
    const std::time_t t = std::chrono::system_clock::to_time_t(now);
    const int ms = int(std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000);
    
    std::tm tm{};
    localtime_r(&t, &tm);
    
    char stamp[64];
    size_t n = std::strftime(stamp, sizeof(stamp), "[%Y-%m-%d %H:%M:%S", &tm);
    std::string line(stamp, n);
    char tail[16];
    snprintf(tail, sizeof(tail), ".%03d] ", ms);
    line += tail;
    line += message;
    line += "\n";

    WriteRaw(line.data(), line.size());
    std::cout << line;
}

} // namespace dmc4::boot
