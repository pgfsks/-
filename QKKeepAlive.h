//
//  QKKeepAlive.h
//  QuickKey
//
//  TrollStore 无越狱路线下没有 LaunchDaemon，只能用「后台音频」保活：
//  播放一段静音 PCM（AudioSession 设为 playback + mixWithOthers），
//  配合 Info.plist 的 UIBackgroundModes=audio 让进程常驻。
//  代价是耗电，且系统仍可能在极端情况下回收，所以越狱路线优先用 daemon。
//

#import <Foundation/Foundation.h>

@interface QKKeepAlive : NSObject
+ (instancetype)shared;
- (BOOL)start;
- (void)stop;
- (void)ensureRunning;
@property (nonatomic, readonly) BOOL running;
@end
