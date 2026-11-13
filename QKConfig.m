#import "QKConfig.h"

NSString *const QKTriggerVolUpShort    = @"volup.short";
NSString *const QKTriggerVolUpLong     = @"volup.long";
NSString *const QKTriggerVolUpDouble   = @"volup.double";
NSString *const QKTriggerVolDownShort  = @"voldown.short";
NSString *const QKTriggerVolDownLong   = @"voldown.long";
NSString *const QKTriggerVolDownDouble = @"voldown.double";
NSString *const QKTriggerPowerShort    = @"power.short";
NSString *const QKTriggerPowerLong     = @"power.long";
NSString *const QKTriggerMuteOff       = @"mute.off";
NSString *const QKTriggerMuteOn        = @"mute.on";
NSString *const QKTriggerVolCombo      = @"volcombo.hold";

static NSString *const kConfigPath = @"/var/mobile/Library/Preferences/com.quickkey.config.plist";

// 键名
static NSString *const kKeyMapping   = @"mapping";
static NSString *const kKeyKeepAlive = @"keepAlive";
static NSString *const kKeyDebugLog  = @"debugLog";
static NSString *const kKeyEnabled   = @"enabled";

@implementation QKConfig {
    NSDictionary *_cache;
    NSDate       *_cacheStamp;
}

+ (instancetype)shared {
    static QKConfig *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [QKConfig new]; });
    return instance;
}

+ (NSArray<NSDictionary *> *)triggerDefinitions {
    return @[
        @{@"id": QKTriggerVolUpShort,    @"title": @"音量+ 短按"},
        @{@"id": QKTriggerVolUpLong,     @"title": @"音量+ 长按"},
        @{@"id": QKTriggerVolUpDouble,   @"title": @"音量+ 双击"},
        @{@"id": QKTriggerVolDownShort,  @"title": @"音量- 短按"},
        @{@"id": QKTriggerVolDownLong,   @"title": @"音量- 长按"},
        @{@"id": QKTriggerVolDownDouble, @"title": @"音量- 双击"},
        @{@"id": QKTriggerVolCombo,      @"title": @"音量+ / − 同按"},
        @{@"id": QKTriggerPowerLong,     @"title": @"电源键 长按"},
        @{@"id": QKTriggerPowerShort,    @"title": @"电源键 短按"},
        @{@"id": QKTriggerPowerDouble,   @"title": @"电源键 双击"},
        @{@"id": QKTriggerMuteOff,       @"title": @"静音拨片 → 响铃"},
        @{@"id": QKTriggerMuteOn,        @"title": @"静音拨片 → 静音"},
    ];
}

#pragma mark - 读写

/// 带 mtime 缓存：daemon 每秒可能被问很多次，但只在文件变了才重新解析
- (NSDictionary *)rawConfig {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:kConfigPath error:nil];
    NSDate *stamp = attrs[NSFileModificationDate];

    if (_cache && ((!stamp && !_cacheStamp) || [stamp isEqualToDate:_cacheStamp])) {
        return _cache;
    }
    _cache = [NSDictionary dictionaryWithContentsOfFile:kConfigPath] ?: @{};
    _cacheStamp = stamp;
    return _cache;
}

- (void)mutate:(void (^)(NSMutableDictionary *cfg))block {
    NSMutableDictionary *cfg = [[self rawConfig] mutableCopy] ?: [NSMutableDictionary dictionary];
    block(cfg);

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[kConfigPath stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES attributes:nil error:nil];

    if (![cfg writeToFile:kConfigPath atomically:YES]) {
        NSLog(@"[QuickKey] 写配置失败，检查 %@ 的权限", kConfigPath);
    }
    // 让 root 的 daemon 也能读
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644}
                                     ofItemAtPath:kConfigPath error:nil];

    _cache = nil;
    _cacheStamp = nil;
}

#pragma mark - 触发器

- (NSString *)shortcutForTrigger:(NSString *)trigger {
    if (!trigger.length) return nil;
    NSString *name = [self rawConfig][kKeyMapping][trigger];
    return name.length ? name : nil;
}

- (void)setShortcut:(NSString *)name forTrigger:(NSString *)trigger {
    if (!trigger.length) return;
    [self mutate:^(NSMutableDictionary *cfg) {
        NSMutableDictionary *mapping = [cfg[kKeyMapping] mutableCopy] ?: [NSMutableDictionary dictionary];
        if (name.length) {
            mapping[trigger] = name;
        } else {
            [mapping removeObjectForKey:trigger];
        }
        cfg[kKeyMapping] = mapping;
    }];
}

#pragma mark - 开关

- (BOOL)boolForKey:(NSString *)key default:(BOOL)fallback {
    id value = [self rawConfig][key];
    return value ? [value boolValue] : fallback;
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [self mutate:^(NSMutableDictionary *cfg) { cfg[key] = @(value); }];
}

- (BOOL)keepAlive { return [self boolForKey:kKeyKeepAlive default:YES]; }
- (void)setKeepAlive:(BOOL)value { [self setBool:value forKey:kKeyKeepAlive]; }

- (BOOL)debugLog { return [self boolForKey:kKeyDebugLog default:NO]; }
- (void)setDebugLog:(BOOL)value { [self setBool:value forKey:kKeyDebugLog]; }

- (BOOL)enabled { return [self boolForKey:kKeyEnabled default:YES]; }
- (void)setEnabled:(BOOL)value { [self setBool:value forKey:kKeyEnabled]; }

@end
