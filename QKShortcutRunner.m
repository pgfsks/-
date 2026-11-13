#import "QKShortcutRunner.h"
#import "QKLog.h"

#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>

@implementation QKShortcutRunner

+ (BOOL)runShortcutWithName:(NSString *)name {
    if (!name.length) return NO;

    NSURL *url = [self shortcutURLWithName:name];
    if (!url) return NO;

    if ([self openURLViaLaunchServices:url]) {
        QKLog(@"已唤起快捷指令：%@", name);
        return YES;
    }

    // 退化路径：只有在有 UIApplication 的进程（App 内）才可能成功
    if ([self openURLViaUIKit:url]) {
        QKLog(@"已通过 UIApplication 唤起：%@", name);
        return YES;
    }

    QKLog(@"唤起快捷指令失败：%@", name);
    return NO;
}

#pragma mark - URL 组装

+ (NSURL *)shortcutURLWithName:(NSString *)name {
    // URLQueryAllowed 里保留了 & = ? + ; : #，指令名带这些字符会截断参数，先剔掉
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"&=?+;:#"];
    NSString *encoded = [name stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    if (!encoded.length) return nil;

    NSString *string = [NSString stringWithFormat:@"shortcuts://run-shortcut?name=%@", encoded];
    return [NSURL URLWithString:string];
}

#pragma mark - LaunchServices

+ (BOOL)openURLViaLaunchServices:(NSURL *)url {
    static Class workspaceClass = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // LSApplicationWorkspace 在 MobileCoreServices 里，属于私有框架
        dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
        workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    });
    if (!workspaceClass) return NO;

    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass,
                                                   NSSelectorFromString(@"defaultWorkspace"));
    if (!workspace) return NO;

    SEL sel = NSSelectorFromString(@"openSensitiveURL:withOptions:");
    if (![workspace respondsToSelector:sel]) return NO;

    NSMethodSignature *signature = [workspace methodSignatureForSelector:sel];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = workspace;
    invocation.selector = sel;

    NSURL *arg0 = url;
    NSDictionary *arg1 = @{};
    [invocation setArgument:&arg0 atIndex:2];
    [invocation setArgument:&arg1 atIndex:3];
    [invocation retainArguments];
    [invocation invoke];

    BOOL result = NO;
    if (signature.methodReturnLength == sizeof(BOOL)) {
        [invocation getReturnValue:&result];
    }
    return result;
}

#pragma mark - UIKit 退化路径

+ (BOOL)openURLViaUIKit:(NSURL *)url {
    Class appClass = NSClassFromString(@"UIApplication");
    if (!appClass) return NO;

    id app = ((id (*)(id, SEL))objc_msgSend)(appClass, NSSelectorFromString(@"sharedApplication"));
    if (!app) return NO;

    SEL sel = NSSelectorFromString(@"openURL:options:completionHandler:");
    if (![app respondsToSelector:sel]) return NO;

    ((void (*)(id, SEL, id, id, id))objc_msgSend)(app, sel, url, @{}, nil);
    return YES;
}

@end
