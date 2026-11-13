//
//  QKShortcutRunner.h
//  QuickKey
//
//  通过 LSApplicationWorkspace 的 openSensitiveURL: 打开
//  shortcuts://run-shortcut?name=<指令名>，由「快捷指令」App 真正执行动作。
//  QuickKey 自己只当遥控器。
//

#import <Foundation/Foundation.h>

@interface QKShortcutRunner : NSObject

/// 运行指定名称的快捷指令；返回是否成功把 URL 交出去
+ (BOOL)runShortcutWithName:(NSString *)name;

@end
