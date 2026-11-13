//
//  QKKeyMonitor.h
//  QuickKey
//
//  用 IOHIDEventSystemClient（Monitor 类型，只旁听不吞事件）订阅全局硬件按键，
//  再做短按 / 长按 / 双击 / 拨片状态判定。
//

#import <Foundation/Foundation.h>

typedef void (^QKTriggerHandler)(NSString *trigger);

@interface QKKeyMonitor : NSObject

+ (instancetype)shared;

/// 开始监听；block 会在内部串行队列上回调
- (BOOL)startWithHandler:(QKTriggerHandler)handler;
- (void)stop;

/// 监听是否活着（用于界面显示状态）
@property (nonatomic, readonly) BOOL running;

@end
