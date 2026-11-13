#import "QKAppDelegate.h"
#import "QKRootViewController.h"
#import "QKKeyMonitor.h"
#import "QKShortcutRunner.h"
#import "QKConfig.h"
#import "QKKeepAlive.h"
#import "QKLog.h"

@implementation QKAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    QKLogSetEnabled([QKConfig shared].debugLog);

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController =
        [[UINavigationController alloc] initWithRootViewController:[QKRootViewController new]];
    [self.window makeKeyAndVisible];

    [self startMonitoring];
    if ([QKConfig shared].keepAlive) [[QKKeepAlive shared] start];
    return YES;
}

- (void)startMonitoring {
    __weak typeof(self) weakSelf = self;
    BOOL ok = [[QKKeyMonitor shared] startWithHandler:^(NSString *trigger) {
        NSString *name = [[QKConfig shared] shortcutForTrigger:trigger];
        if (name.length) [QKShortcutRunner runShortcutWithName:name];
        (void)weakSelf;
    }];
    QKLog(@"按键监听启动：%@", ok ? @"成功" : @"失败");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // 没有 daemon 时，靠后台音频把进程吊住
    if ([QKConfig shared].keepAlive) [[QKKeepAlive shared] ensureRunning];
}

@end
