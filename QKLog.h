#import <Foundation/Foundation.h>

/// 调试日志：默认只打 stderr；打开「调试日志」后同时追加到文件，方便校准按键。
void QKLogSetEnabled(BOOL enabled);
void QKLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
