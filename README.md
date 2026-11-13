# QuickKey —— 硬件按键 → 运行快捷指令

从 TrollRecorder 的「自定义按键运行快捷指令」里，只保留这一件事做出来的独立工具。

**它只做三件事**：旁听硬件按键 → 判定手势 → 用 `shortcuts://` 唤起你指定的快捷指令。没有录音、没有联网、没有别的权限。

> ⚠️ 前提条件：`com.apple.private.hid.client.event-monitor` 这类权限只有 **TrollStore（iOS 15.0–17.0）或越狱** 才能授予。
> 用 eSign / AltStore / 普通签名装进去会直接闪退或监听失败，这不是代码问题，是签名权限问题。

---

## 一、原理（对应代码位置）

| 环节 | 系统能力 | 代码 |
|---|---|---|
| 拿到全局按键事件 | `IOHIDEventSystemClientCreateWithType(…, Monitor, …)` + `RegisterEventCallback`，订阅内核 HID 事件总线（Consumer 页 0x0C：音量 0xE9/0xEA、电源 0x30；AppleVendor 页拨片） | `shared/QKKeyMonitor.m` |
| 区分短按/长按/双击 | 自己攒 down/up 时间戳，`<0.45s` 短按、`>0.55s` 长按、间隔 `<0.32s` 两次算双击 | `shared/QKKeyMonitor.m` `-handleKey:pressed:` |
| 触发快捷指令 | 私有 `LSApplicationWorkspace -openSensitiveURL:` 打开 `shortcuts://run-shortcut?name=xxx` | `shared/QKShortcutRunner.m` |
| 让它一直活着 | 越狱：LaunchDaemon；TrollStore：后台静音音频保活 | `layout/…/com.quickkey.daemon.plist` / `app/QKKeepAlive.m` |

关键点：QuickKey **不执行任何动作**，它只是遥控器，真正干活的永远是「快捷指令」App。所以要扩功能（开灯、发微信、启动 App），去 Shortcuts 里写，这边只填名字。

---

## 二、目录结构

```
QuickKey/
├── Makefile                    # Theos：App + Daemon 两个 target
├── control                     # deb 包描述
├── .github/workflows/build.yml # 云端编译（没 Mac 也能出 IPA）
├── tools/build_ipa.sh          # 打 TrollStore 用的 IPA（含 ldid 签名）
├── entitlements/
│   ├── app.entitlements        # 无沙盒 + HID 监听 + LaunchServices
│   └── daemon.entitlements
├── shared/                     # App 与 Daemon 共用
│   ├── QKConfig.{h,m}          # 配置读写（plist + mtime 缓存）
│   ├── QKKeyMonitor.{h,m}      # IOHID 订阅 + 手势引擎
│   ├── QKShortcutRunner.{h,m}  # shortcuts:// 唤起
│   └── QKLog.{h,m}             # 日志（可开关，用于校准）
├── app/                        # 配置界面（被系统杀掉也没事）
│   ├── main.m / QKAppDelegate  # 入口，启动监听
│   ├── QKRootViewController    # 表格：10 个触发项 + 3 个开关
│   ├── QKKeepAlive             # 静音 WAV 保活
│   └── Info.plist              # UIBackgroundModes=audio
├── daemon/main.m               # 常驻守护进程（推荐路线）
└── layout/Library/LaunchDaemons/com.quickkey.daemon.plist
```

配置文件统一在 **`/var/mobile/Library/Preferences/com.quickkey.config.plist`**，App 写、daemon 读，改完立刻生效（有 mtime 缓存）。

---

## 三、构建

### 方式 A：没有 Mac —— 用 GitHub Actions 云编译（最省事）

1. 把 `QuickKey/` 目录推到一个 GitHub 私有仓库（branch = `main`）；
2. 仓库 → Actions → `build` → Run workflow；
3. 跑完在 Artifacts 里下载 `QuickKey.zip`，里面：
   - `packages/*.deb` —— 越狱用（rootless）
   - `build/QuickKey.ipa` —— TrollStore 用（已 ldid 签名）

### 方式 B：本机 macOS + Theos

```bash
export THEOS=~/theos
# 越狱 deb
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
# TrollStore IPA
brew install ldid
make clean all
chmod +x tools/build_ipa.sh && ./tools/build_ipa.sh
```

> 说明：我这边是 Linux 环境、没有 iPhoneOS SDK，所以这套源码**没有经过实际编译验证**。首次编译如果报符号缺失，看下面「排错」。
>
> rootless 打包时，`layout/` 里的 LaunchDaemon 需要落到 `/var/jb/Library/LaunchDaemons/`。若 Theos 没自动加前缀，装完手动执行：
> `cp /Library/LaunchDaemons/com.quickkey.daemon.plist /var/jb/Library/LaunchDaemons/ 2>/dev/null || true`，再 bootstrap 一次。

---

## 四、安装

### 路线 1：越狱（推荐）

rootless 越狱（Dopamine / palera1n / Serotonin 等）：

```bash
# 把 deb 传上去，或用 Sileo 直接装
dpkg -i com.quickkey_1.0_iphoneos-arm64.deb
launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.quickkey.daemon.plist   # 或用 Sileo 装完重启用户空间
```

装完桌面会多一个「快键」App，只用来填配置。**daemon 常驻，App 关掉也照常触发**——这就是它和 TrollRecorder 同款的体验。

### 路线 2：TrollStore（无越狱）

1. TrollStore 里「Install IPA」选 `build/QuickKey.ipa`；
2. 打开「快键」，把「后台保活」开着（默认开）；
3. 填好触发项，把 App 切到后台即可。

限制：没有真正的 daemon，靠后台音频吊着进程，**耗电更高**，重启手机后要手动打开一次 App。这就是官方路线和 TrollStore 路线的真实差距。

---

## 五、手势清单，以及电源键的真实限制

已实现 **12 个触发项**：

| 手势 | 触发 ID | 系统同时会发生什么 | 可用性 |
|---|---|---|---|
| 音量+ 短按 | `volup.short` | 音量 +1 格 | ✅ 可用（音量会变） |
| 音量+ 长按 | `volup.long` | 按住时音量持续上升 | ✅ 可用，建议配"音量恢复"心理准备 |
| 音量+ 双击 | `volup.double` | 音量 +2 格 | ✅ 可用（第二击后 0.32s 才出结果） |
| 音量− 短按/长按/双击 | `voldown.*` | 同上，方向相反 | ✅ 可用 |
| **音量+ / − 同按** | `volcombo.hold` | 加减抵消，几乎没有副作用 | ⭐ 最推荐做主力手势 |
| **电源键 长按** | `power.long` | 超过约 2s 会出关机/SOS 滑块 | ✅ 可用：0.55s 就触发，跑在系统前面 |
| 电源键 短按 | `power.short` | 锁屏 / 亮屏 | ⚠️ 每次息屏都触发一次，基本没法用 |
| 电源键 双击 | `power.double` | 第一击就已经锁屏了，第二击唤醒（Face ID 机型还会拉起钱包） | ❌ 实际不可用 |
| 静音拨片 拨动 | `mute.on` / `mute.off` | 切换静音 | ✅ 可用 |

**为什么电源键和你想的不一样**：我们用的是 Monitor 客户端——只旁听，不吞事件。系统的"锁屏 / Apple Pay / 关机"照常执行，QuickKey 只能在旁边叠一层动作。所以电源键**只能做"叠加触发"，做不到"改掉系统行为"**。

真要做到"电源键长按不弹关机界面"，得换成 **Filter 客户端**（`kQKClientTypeFilter`）把事件消费掉，但那样会把系统原生功能一起废掉，风险很高。我不建议，也没在这版里默认开。

**结论（务实方案）**：
- 主力用 **音量+ 长按** 和 **音量+ 双击**（想更干净就用 **同按**）；
- 电源键只用 **长按**，用来做"长按侧边键 → 开录音/快捷指令"；
- 双击电源键那条填了也没意义，第一击就把屏幕锁了。

---

## 六、配置方法与注意事项

1. **先建快捷指令**：Shortcuts 里新建，名字取得短而唯一，比如 `开录音`。这里填的是**指令名**，不是显示标题。
2. **填进 App**：点某一项 → 输入名字 → 保存。表格里会显示已绑定。
3. **点右上角「测试」**验证 URL 唤起是否通。
4. 首次触发系统可能弹一次「允许运行」确认，之后不再弹。
5. 触发时会**短暂切到快捷指令 App 再回来**——`shortcuts://` 的固有限制，无解。想完全无感，只能等苹果开放后台运行 API（目前没有）。

### 校准按键（重要）

不同机型/系统，电源键、静音拨片的 usage 可能不同。做法：

1. App 里打开「调试日志」；
2. 每个键按一下；
3. 看日志 `HID page=0x… usage=0x…`：
   ```
   /var/mobile/Library/Logs/QuickKey.log          # 调试日志
   /var/mobile/Library/Logs/QuickKey/daemon.err    # daemon 的 stderr
   ```
4. 如果拨片/电源键的 page/usage 对不上，改 `shared/QKKeyMonitor.m` 顶部的
   `kQKUsagePower` / `kQKPageAppleVendor` / `kQKUsageMuteSwitch` 三个宏，重新编译。

---

## 七、排错

| 现象 | 原因 | 处理 |
|---|---|---|
| App 一起动就闪退 | 签名没带 entitlements | 用 `ldid -M -Sentitlements/app.entitlements` 重签；TrollStore 安装前确认 ldid 生效 |
| 日志里 `创建 IOHIDEventSystemClient 失败` | 缺 HID 权限，或不是 Monitor 客户端 | 确认 entitlements 里有 `com.apple.private.hid.client.event-monitor`，且装在 TrollStore/越狱环境 |
| 能监听但按音量键没反应 | usage 不匹配 | 开调试日志校准（见上） |
| 监听到了但不触发 | 触发项没填名字 / 「启用」关了 | 检查表格右侧是否为蓝色指令名 |
| 按音量键时音量条也动了 | Monitor 客户端只旁听，不吞事件 | 正常现象，这是设计取舍（吞事件会影响系统行为） |
| 唤不起快捷指令 | 指令名带空格/特殊字符，或指令不存在 | 换短名字重试；看日志 `唤起快捷指令失败` |
| 编译报 `IOHIDEventSystemClientCreateWithType` 未定义 | 该符号不在公开头文件 | 代码已用 `dlopen` + `dlsym` 手工解析，若仍报错说明 IOKit 路径变了，改 `QKLoadSymbols()` 里的路径 |

---

## 八、想继续扩展的地方

- **加"只在通话中才触发"**：在 `QKKeyMonitor` 里加一个"通话状态"字段，daemon 侧订阅 CallKit 通知（`CXCallObserver` 在越狱环境可用）后再决定是否 fire。
- **加"组合键"**：`QKKeyState` 里已有 down/up 时间戳，加一个跨键的 100ms 窗口判断即可。
- **换配置界面**：配置文件就是普通 plist，你也可以直接 `ssh` 写文件，App 不是必须的。

---

## 九、风险提醒

- 这套东西本质是**绕过苹果签名体系**的私有 API 用法，系统一升级（TrollStore 失效、私有符号改名）就可能整体失灵；
- daemon 以 root 跑，代码你要自己看得懂再装，别装来路不明的改版；
- 按键映射给"发消息/付款/开锁"这类动作时慎用——误触的代价是真金白银。
