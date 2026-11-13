//
//  quickkeyd —— 越狱路线的常驻守护进程
//  由 launchd 拉起，root 身份运行，负责按键监听 + 触发快捷指令。
//  App 只作配置面板，可以随时被系统杀掉，不影响触发。
//

#import <Foundation/Foundation.h>
#include <signal.h>
#include <unistd.h>
#import "QKKeyMonitor.h"
#import "QKShortcutRunner.h"
#import "QKConfig.h"
#import "QKLog.h"

static void QKInstallSignalHandlers(void) {
    signal(SIGTERM, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        QKInstallSignalHandlers();
        QKLogSetEnabled([QKConfig shared].debugLog);
        QKLog(@"quickkeyd 启动，pid=%d", getpid());

        BOOL ok = [[QKKeyMonitor shared] startWithHandler:^(NSString *trigger) {
            NSString *name = [[QKConfig shared] shortcutForTrigger:trigger];
            if (!name.length) return;
            [QKShortcutRunner runShortcutWithName:name];
        }];

        if (!ok) {
            QKLog(@"监听启动失败，10 秒后退出由 launchd 重启");
            sleep(10);
            return 1;
        }

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
