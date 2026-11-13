#import "QKRootViewController.h"
#import "QKConfig.h"
#import "QKKeyMonitor.h"
#import "QKKeepAlive.h"
#import "QKShortcutRunner.h"
#import "QKLog.h"

typedef NS_ENUM(NSInteger, QKSection) {
    QKSectionSwitches = 0,
    QKSectionTriggers,
    QKSectionCount
};

@implementation QKRootViewController {
    NSArray<NSDictionary *> *_triggers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _triggers = [QKConfig triggerDefinitions];

    self.title = @"按键 → 快捷指令";
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"测试" style:UIBarButtonItemStylePlain
                                       target:self action:@selector(runTestShortcut)];

    [self updateFooter];
}

- (void)updateFooter {
    BOOL running = [QKKeyMonitor shared].running;
    NSString *status = running ? @"● 按键监听运行中" : @"○ 按键监听未启动（缺 HID 权限或未在 TrollStore 下安装）";
    self.tableView.tableFooterView = [self footerLabelWithText:
        [NSString stringWithFormat:@"%@\n\n用法：填「快捷指令」里那条指令的名字（不是标题里的表情/序号）。\n"
                                    @"触发时会短暂唤起快捷指令 App，这是 URL scheme 的固有限制，不是 QuickKey 的锅。\n\n"
                                    @"配置：/var/mobile/Library/Preferences/com.quickkey.config.plist", status]];
}

- (UIView *)footerLabelWithText:(NSString *)text {
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = [UIColor secondaryLabelColor];
    label.text = text;
    label.textAlignment = NSTextAlignmentLeft;
    CGFloat width = [UIScreen mainScreen].bounds.size.width - 40;
    CGSize size = [label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    label.frame = CGRectMake(0, 0, width, size.height);
    return label;
}

#pragma mark - 快捷指令

- (void)runTestShortcut {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"测试触发"
                                                                  message:@"输入一条快捷指令的名字，立刻运行一次"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"例如 打开录音";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"运行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        BOOL ok = [QKShortcutRunner runShortcutWithName:name];
        [self toast:ok ? @"已唤起快捷指令" : @"唤起失败，见日志"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toast:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [alert dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

#pragma mark - 开关

- (UISwitch *)switchWithOn:(BOOL)on action:(SEL)action {
    UISwitch *toggle = [UISwitch new];
    toggle.on = on;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return toggle;
}

- (void)enabledChanged:(UISwitch *)sender {
    [QKConfig shared].enabled = sender.isOn;
}

- (void)keepAliveChanged:(UISwitch *)sender {
    [QKConfig shared].keepAlive = sender.isOn;
    if (sender.isOn) {
        [[QKKeepAlive shared] start];
    } else {
        [[QKKeepAlive shared] stop];
    }
}

- (void)debugChanged:(UISwitch *)sender {
    [QKConfig shared].debugLog = sender.isOn;
    QKLogSetEnabled(sender.isOn);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return QKSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == QKSectionSwitches ? 3 : _triggers.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == QKSectionSwitches ? @"设置" : @"触发项";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"QKCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];

    QKConfig *config = [QKConfig shared];

    if (indexPath.section == QKSectionSwitches) {
        cell.accessoryView = nil;
        cell.detailTextLabel.text = nil;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"启用";
            cell.accessoryView = [self switchWithOn:config.enabled action:@selector(enabledChanged:)];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"后台保活（耗电）";
            cell.accessoryView = [self switchWithOn:config.keepAlive action:@selector(keepAliveChanged:)];
        } else {
            cell.textLabel.text = @"调试日志";
            cell.accessoryView = [self switchWithOn:config.debugLog action:@selector(debugChanged:)];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *definition = _triggers[indexPath.row];
        NSString *name = [config shortcutForTrigger:definition[@"id"]];
        cell.textLabel.text = definition[@"title"];
        cell.detailTextLabel.text = name.length ? name : @"未设置";
        cell.detailTextLabel.textColor = name.length ? [UIColor systemBlueColor] : [UIColor tertiaryLabelColor];
    }
    return cell;
}

#pragma mark - 编辑动作

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != QKSectionTriggers) return;

    NSDictionary *definition = _triggers[indexPath.row];
    NSString *trigger = definition[@"id"];
    NSString *current = [[QKConfig shared] shortcutForTrigger:trigger];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:definition[@"title"]
                                             message:@"填入快捷指令名称（精确匹配）"
                                      preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = current; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[QKConfig shared] setShortcut:alert.textFields.firstObject.text forTrigger:trigger];
        [tableView reloadData];
    }]];
    if (current.length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [[QKConfig shared] setShortcut:nil forTrigger:trigger];
            [tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
