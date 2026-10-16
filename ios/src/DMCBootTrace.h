#pragma once

#import <Foundation/Foundation.h>
#include <string>

namespace dmc4::boot {

// Initializes unbuffered boot.txt and redirects stdout/stderr to dmc4.log
void InitializeLogging();

// Writes unbuffered timestamped trace line to Documents/logs/boot.txt
void Trace(const std::string &message);

// Returns path to Documents/logs folder
NSString *GetLogsDirectoryPath();

} // namespace dmc4::boot
