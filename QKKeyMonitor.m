#import "QKKeyMonitor.h"
#import "QKConfig.h"
#import "QKLog.h"

#include <dlfcn.h>

#pragma mark - 私有符号声明
// 这些 API 来自 IOKit 私有头（IOHIDEventSystemClient.h / IOHIDEventTypes.h），
// SDK 里不保证有，所以全部手工声明并显式 dlopen，避免链接失败。

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDEvent         *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

typedef void (*QKEventCallback)(void *target, void *refcon,
                                IOHIDServiceClientRef service, IOHIDEventRef event);

// Client 类型：0 = Simple/Filter（会注册成过滤器，可能影响原按键行为）
//            1 = Monitor（只旁听，推荐）
#define kQKClientTypeMonitor 1

// 事件类型 / 字段号：kIOHIDEventFieldBase(type) = type << 16
#define kQKEventTypeKeyboard 3
#define QK_FIELD_BASE(t)        ((int32_t)((t) << 16))
#define QK_FIELD_KB_USAGE_PAGE  QK_FIELD_BASE(kQKEventTypeKeyboard)          // +0
#define QK_FIELD_KB_USAGE       (QK_FIELD_BASE(kQKEventTypeKeyboard) + 1)    // +1
#define QK_FIELD_KB_DOWN        (QK_FIELD_BASE(kQKEventTypeKeyboard) + 2)    // +2

// HID usage page / usage
#define kQKPageConsumer   0x0C
#define kQKUsageVolUp     0xE9   // 233
#define kQKUsageVolDown   0xEA   // 234
#define kQKUsagePower     0x30   // 48
#define kQKPageAppleVendor 0xFF00
#define kQKUsageMuteSwitch 0x0001

#pragma mark - 私有函数指针

static IOHIDEventSystemClientRef (*QKCreateWithType)(CFAllocatorRef, int, CFDictionaryRef);
static IOHIDEventSystemClientRef (*QKCreatePlain)(CFAllocatorRef);
static void (*QKScheduleWithRunLoop)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef);
static int  (*QKRegisterCallback)(IOHIDEventSystemClientRef, QKEventCallback, void *, void *);
static int  (*QKGetType)(IOHIDEventRef);
static int64_t (*QKGetIntegerValue)(IOHIDEventRef, int32_t);

static BOOL QKLoadSymbols(void) {
    if (QKGetType) return YES;

    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!handle) {
        QKLog(@"dlopen IOKit 失败：%s", dlerror());
        return NO;
    }

    QKCreateWithType    = dlsym(handle, "IOHIDEventSystemClientCreateWithType");
    QKCreatePlain       = dlsym(handle, "IOHIDEventSystemClientCreate");
    QKScheduleWithRunLoop = dlsym(handle, "IOHIDEventSystemClientScheduleWithRunLoop");
    QKRegisterCallback  = dlsym(handle, "IOHIDEventSystemClientRegisterEventCallback");
    QKGetType           = dlsym(handle, "IOHIDEventGetType");
    QKGetIntegerValue   = dlsym(handle, "IOHIDEventGetIntegerValue");

    if ((!QKCreateWithType && !QKCreatePlain) || !QKScheduleWithRunLoop ||
        !QKRegisterCallback || !QKGetType || !QKGetIntegerValue) {
        QKLog(@"IOHID 符号不全：create(w/type)=%p create=%p sched=%p reg=%p type=%p val=%p",
              QKCreateWithType, QKCreatePlain, QKScheduleWithRunLoop,
              QKRegisterCallback, QKGetType, QKGetIntegerValue);
        return NO;
    }
    return YES;
}

// C 回调前置声明（start 里要取函数指针）
static void QKEventCallbackIMP(void *target, void *refcon,
                               IOHIDServiceClientRef service, IOHIDEventRef event);

#pragma mark - 每颗键的手势状态

typedef NS_ENUM(NSInteger, QKKey) {
    QKKeyVolumeUp = 0,
    QKKeyVolumeDown,
    QKKeyPower,
    QKKeyMuteSwitch,
    QKKeyCount
};

@interface QKKeyState : NSObject
@property (nonatomic) NSTimeInterval downTime;
@property (nonatomic) NSTimeInterval lastUpTime;
@property (nonatomic) BOOL isDown;           // 去重：长按会连续送 down=1
@property (nonatomic) BOOL waitingSecondTap;
@property (nonatomic) BOOL doubleCandidate;
@property (nonatomic) BOOL longFired;        // 已按"到阈值立即触发"发过长按
@property (nonatomic) NSInteger longToken;   // 作废过期的长按定时器
@property (nonatomic) NSInteger shortToken;  // 作废过期的短按定时器
@end

@implementation QKKeyState
@end

#pragma mark - Monitor

@implementation QKKeyMonitor {
    IOHIDEventSystemClientRef _client;
    QKTriggerHandler          _handler;
    QKKeyState               *_states[QKKeyCount];
    dispatch_queue_t          _queue;
    BOOL                      _running;
    BOOL                      _muteIsMuted;
    BOOL                      _comboActive;    // 音量+/- 同按序列进行中
    BOOL                      _comboFired;     // 本次同按已触发过
}

+ (instancetype)shared {
    static QKKeyMonitor *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [QKKeyMonitor new];
        instance->_queue = dispatch_queue_create("com.quickkey.monitor", DISPATCH_QUEUE_SERIAL);
        for (NSInteger i = 0; i < QKKeyCount; i++) instance->_states[i] = [QKKeyState new];
    });
    return instance;
}

- (BOOL)running { return _running; }

#pragma mark 生命周期

- (BOOL)startWithHandler:(QKTriggerHandler)handler {
    if (_running) return YES;
    if (!QKLoadSymbols()) return NO;

    _handler = [handler copy];

    if (QKCreateWithType) {
        _client = QKCreateWithType(kCFAllocatorDefault, kQKClientTypeMonitor, NULL);
    }
    if (!_client && QKCreatePlain) {
        _client = QKCreatePlain(kCFAllocatorDefault);
    }
    if (!_client) {
        QKLog(@"创建 IOHIDEventSystemClient 失败（缺 com.apple.private.hid.client.event-monitor 权限？）");
        return NO;
    }

    QKRegisterCallback(_client, QKEventCallbackIMP, (__bridge void *)self, NULL);
    QKLog(@"IOHID 客户端已创建，开始监听");

    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        QKScheduleWithRunLoop(self->_client, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());

    _running = YES;
    return YES;
}

- (void)stop {
    _running = NO;
    _handler = nil;
    _client = NULL;   // 客户端交给系统回收，避免和 RunLoop 的时序问题
}

#pragma mark 事件入口

- (void)handleEvent:(IOHIDEventRef)event {
    if (!event || !_running) return;
    if (QKGetType(event) != kQKEventTypeKeyboard) return;

    int64_t page  = QKGetIntegerValue(event, QK_FIELD_KB_USAGE_PAGE);
    int64_t usage = QKGetIntegerValue(event, QK_FIELD_KB_USAGE);
    int64_t down  = QKGetIntegerValue(event, QK_FIELD_KB_DOWN);

    if ([QKConfig shared].debugLog) {
        QKLog(@"HID page=0x%llX usage=0x%llX down=%lld", page, usage, down);
    }

    if (page == kQKPageConsumer && (usage == kQKUsageVolUp || usage == kQKUsageVolDown)) {
        QKKey key = (usage == kQKUsageVolUp) ? QKKeyVolumeUp : QKKeyVolumeDown;
        [self handleKey:key pressed:(down != 0)];
    } else if (page == kQKPageConsumer && usage == kQKUsagePower) {
        [self handleKey:QKKeyPower pressed:(down != 0)];
    } else if (page == kQKPageAppleVendor && usage == kQKUsageMuteSwitch) {
        [self handleMuteSwitchPressed:(down != 0)];
    }
}

#pragma mark 按键 → 手势

- (void)handleKey:(QKKey)key pressed:(BOOL)pressed {
    QKKeyState *st = _states[key];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSString *base = [self triggerPrefixForKey:key];

    if (pressed) {
        if (st.isDown) return;                 // 长按期间重复的 down 事件，忽略
        st.isDown = YES;
        st.downTime = now;
        st.longFired = NO;
        st.shortToken++;                       // 作废待触发的短按

        // ---- 组合键：音量+ 与 音量− 几乎同时按下（唯一没有系统副作用的手势）
        if ((key == QKKeyVolumeUp || key == QKKeyVolumeDown) && !_comboFired) {
            QKKey other = (key == QKKeyVolumeUp) ? QKKeyVolumeDown : QKKeyVolumeUp;
            if (_states[other].isDown) {
                _comboFired = YES;
                _comboActive = YES;
                [self fire:QKTriggerVolCombo];
            }
        }

        // ---- 长按：按住到达阈值立刻触发，不等抬手
        //      这样电源键 0.55s 就出结果，早于系统的关机界面
        NSInteger token = ++st.longToken;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QK_LONG_MIN_DURATION * NSEC_PER_SEC)), _queue, ^{
            QKKeyState *state = self->_states[key];
            if (!state.isDown || state.longFired || state.longToken != token) return;
            if (self->_comboActive) return;     // 同按序列里不发单键长按
            state.longFired = YES;
            [self fire:[base stringByAppendingString:@".long"]];
        });

        // ---- 双击的第一步：和上一次短按间隔够近就标记
        if (st.waitingSecondTap && (now - st.lastUpTime) <= QK_DOUBLE_TAP_WINDOW) {
            st.doubleCandidate = YES;
            st.waitingSecondTap = NO;
        }
        return;
    }

    if (!st.isDown) return;
    st.isDown = NO;
    st.lastUpTime = now;
    st.longToken++;                            // 抬手即作废未到期的长按定时器

    BOOL comboWasActive = _comboActive;
    if (key == QKKeyVolumeUp || key == QKKeyVolumeDown) {
        QKKey other = (key == QKKeyVolumeUp) ? QKKeyVolumeDown : QKKeyVolumeUp;
        if (!_states[other].isDown) {           // 两颗都松开了 → 序列结束
            _comboActive = NO;
            _comboFired = NO;
        }
    }

    if (comboWasActive) {                       // 同按序列内，单键手势全部丢弃
        st.doubleCandidate = NO;
        st.waitingSecondTap = NO;
        st.longFired = NO;
        return;
    }

    if (st.longFired) {                         // 长按已在按住时触发过，抬手不再补发
        st.longFired = NO;
        st.waitingSecondTap = NO;
        return;
    }

    NSTimeInterval duration = now - st.downTime;
    if (!base) return;

    if (st.doubleCandidate) {
        st.doubleCandidate = NO;
        st.waitingSecondTap = NO;
        [self fire:[base stringByAppendingString:@".double"]];
        return;
    }

    if (duration <= QK_SHORT_MAX_DURATION) {
        // 先挂一个双击窗口，没人来接就算短按
        st.waitingSecondTap = YES;
        NSInteger token = ++st.shortToken;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QK_DOUBLE_TAP_WINDOW * NSEC_PER_SEC)), _queue, ^{
            QKKeyState *state = self->_states[key];
            if (state.waitingSecondTap && state.shortToken == token) {
                state.waitingSecondTap = NO;
                [self fire:[base stringByAppendingString:@".short"]];
            }
        });
    }
    // 0.45s ~ 0.55s 之间视为误触，什么都不发
}

- (void)handleMuteSwitchPressed:(BOOL)pressed {
    // 拨片每拨一次发一组 down/up，只取 down
    if (!pressed) return;
    _muteIsMuted = !_muteIsMuted;
    [self fire:_muteIsMuted ? QKTriggerMuteOn : QKTriggerMuteOff];
}

- (NSString *)triggerPrefixForKey:(QKKey)key {
    switch (key) {
        case QKKeyVolumeUp:   return @"volup";
        case QKKeyVolumeDown: return @"voldown";
        case QKKeyPower:      return @"power";
        default:              return nil;   // 拨片走即时触发，不参与短按/长按
    }
}

- (void)fire:(NSString *)trigger {
    dispatch_async(_queue, ^{
        if (![QKConfig shared].enabled) return;
        NSString *name = [[QKConfig shared] shortcutForTrigger:trigger];
        QKLog(@"触发 %@ → %@", trigger, name ?: @"(未配置)");
        if (name.length && self->_handler) self->_handler(trigger);
    });
}

#pragma mark C 回调

static void QKEventCallbackIMP(void *target, void *refcon,
                               IOHIDServiceClientRef service, IOHIDEventRef event) {
    QKKeyMonitor *self = (__bridge QKKeyMonitor *)target;
    [self handleEvent:event];
}

@end
