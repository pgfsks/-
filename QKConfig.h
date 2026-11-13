//
//  QKConfig.h
//  QuickKey —— 硬件按键 → 运行快捷指令
//
//  配置存于 /var/mobile/Library/Preferences/com.quickkey.config.plist
//  App（TrollStore，无沙盒）与守护进程（越狱，root）共用同一份文件。
//

#import <Foundation/Foundation.h>

// 触发器 ID（配置键名）
extern NSString *const QKTriggerVolUpShort;      // 音量+ 短按
extern NSString *const QKTriggerVolUpLong;       // 音量+ 长按
extern NSString *const QKTriggerVolUpDouble;     // 音量+ 双击
extern NSString *const QKTriggerVolDownShort;    // 音量- 短按
extern NSString *const QKTriggerVolDownLong;     // 音量- 长按
extern NSString *const QKTriggerVolDownDouble;   // 音量- 双击
extern NSString *const QKTriggerPowerShort;      // 电源键 短按
extern NSString *const QKTriggerPowerLong;       // 电源键 长按
extern NSString *const QKTriggerMuteOff;         // 静音拨片 拨到响铃
extern NSString *const QKTriggerMuteOn;          // 静音拨片 拨到静音
extern NSString *const QKTriggerVolCombo;        // 音量+ 与 音量− 同按（无系统副作用）

// 手势判定参数
#define QK_SHORT_MAX_DURATION   0.45   // 小于此值算短按
#define QK_LONG_MIN_DURATION    0.55   // 大于此值算长按
#define QK_DOUBLE_TAP_WINDOW    0.32   // 两次短按间隔小于此值算双击

@interface QKConfig : NSObject

+ (instancetype)shared;

/// 界面上要展示的触发项定义：@[ @{@"id":…, @"title":…}, … ]
+ (NSArray<NSDictionary *> *)triggerDefinitions;

/// 触发器 → 快捷指令名；未配置返回 nil
- (NSString *)shortcutForTrigger:(NSString *)trigger;
- (void)setShortcut:(NSString *)name forTrigger:(NSString *)trigger;

- (BOOL)keepAlive;
- (void)setKeepAlive:(BOOL)value;

- (BOOL)debugLog;
- (void)setDebugLog:(BOOL)value;

- (BOOL)enabled;
- (void)setEnabled:(BOOL)value;

@end
