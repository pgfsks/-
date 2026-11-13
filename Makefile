//
//  Makefile —— Theos 工程
//
//  越狱路线（推荐）：
//      make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
//  只出 TrollStore 用的 IPA：
//      make clean all
//      ./tools/build_ipa.sh
//

TARGET := iphone:clang:latest:15.0
ARCHS  := arm64 arm64e

include $(THEOS)/makefiles/common.mk

# ---------------------------------------------------------------- App
APPLICATION_NAME = QuickKey
QuickKey_FILES = $(wildcard app/*.m) $(wildcard shared/*.m)
QuickKey_FRAMEWORKS = UIKit Foundation AVFoundation IOKit
QuickKey_CFLAGS = -fobjc-arc -Ishared -Wno-deprecated-declarations
QuickKey_CODESIGN_FLAGS = -Sentitlements/app.entitlements
QuickKey_INSTALL_PATH = /Applications
QuickKey_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/application.mk

# ---------------------------------------------------------------- Daemon
TOOL_NAME = quickkeyd
quickkeyd_FILES = $(wildcard daemon/*.m) $(wildcard shared/*.m)
quickkeyd_FRAMEWORKS = Foundation IOKit
quickkeyd_CFLAGS = -fobjc-arc -Ishared -Wno-deprecated-declarations
quickkeyd_CODESIGN_FLAGS = -Sentitlements/daemon.entitlements
quickkeyd_INSTALL_PATH = /usr/libexec
quickkeyd_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tool.mk

# ---------------------------------------------------------------- 打包
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "mkdir -p /var/mobile/Library/Preferences /var/mobile/Library/Logs/QuickKey && chown -R mobile:mobile /var/mobile/Library/Logs/QuickKey"
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
	install.exec "launchctl bootout system /var/jb/Library/LaunchDaemons/com.quickkey.daemon.plist 2>/dev/null; launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.quickkey.daemon.plist"
	install.exec "killall -9 SpringBoard 2>/dev/null || true"
else
	install.exec "launchctl unload /Library/LaunchDaemons/com.quickkey.daemon.plist 2>/dev/null; launchctl load /Library/LaunchDaemons/com.quickkey.daemon.plist"
	install.exec "killall -9 SpringBoard 2>/dev/null || true"
endif
