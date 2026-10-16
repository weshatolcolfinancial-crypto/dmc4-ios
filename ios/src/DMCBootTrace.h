#pragma once

#include <string>

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

namespace dmc4::boot {

// Initializes unbuffered boot.txt and redirects stdout/stderr to dmc4.log
void InitializeLogging();

// Writes unbuffered timestamped trace line to Documents/logs/boot.txt
void Trace(const std::string &message);

#ifdef __OBJC__
// Returns path to Documents/logs folder
NSString *GetLogsDirectoryPath();
#endif

} // namespace dmc4::boot
