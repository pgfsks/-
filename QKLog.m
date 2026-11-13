#import "QKLog.h"

static NSString *const kLogPath = @"/var/mobile/Library/Logs/QuickKey.log";
static BOOL gEnabled = NO;

void QKLogSetEnabled(BOOL enabled) {
    gEnabled = enabled;
    if (enabled) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[kLogPath stringByDeletingLastPathComponent]
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

void QKLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[QuickKey] %@", message);

    if (!gEnabled) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                      [NSDate date].description, message];
    NSString *existing = [NSString stringWithContentsOfFile:kLogPath
                                                   encoding:NSUTF8StringEncoding error:nil] ?: @"";
    // 防止日志无限增长
    if (existing.length > 128 * 1024) existing = @"";
    [[existing stringByAppendingString:line] writeToFile:kLogPath atomically:YES
                                                 encoding:NSUTF8StringEncoding error:nil];
}
