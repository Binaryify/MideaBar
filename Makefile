.PHONY: help build icon app run dist clean

APP     := build/MideaBar.app
# 版本号：有 tag 用 tag（去掉前缀 v），否则用提交号。
VERSION ?= $(patsubst v%,%,$(shell git describe --tags --dirty --always 2>/dev/null || echo dev))
# 同时编出 Apple 芯片与 Intel 版本（通用二进制）。
ARCHS   := --arch arm64 --arch x86_64
# 可选：midea-ac-agent 路径。传入则打进 App 包；不传则 App 运行时去包外查找（见 docs/agent-protocol.md）。
AGENT   ?=

.DEFAULT_GOAL := help

help: ## 显示此帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

build: ## 编译 Swift 可执行文件（release，通用二进制）
	swift build -c release $(ARCHS)

icon: ## 由 Icon/make-icon.swift 重新生成 Resources/AppIcon.icns
	@rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	swift Icon/make-icon.swift build/AppIcon-1024.png
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); sips -z $$d $$d build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "✓ 生成图标: Resources/AppIcon.icns"

app: build ## 打包 build/MideaBar.app（可选 AGENT=/path/to/midea-ac-agent 一并打包）
	@test -z "$(AGENT)" || test -x "$(AGENT)" || { echo "✗ $(AGENT) 不存在或不可执行"; exit 1; }
	@rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release $(ARCHS) --show-bin-path)/MideaBar" $(APP)/Contents/MacOS/MideaBar
	@if [ -n "$(AGENT)" ]; then cp "$(AGENT)" $(APP)/Contents/MacOS/midea-ac-agent; fi
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)
	@echo "✓ 生成 App: $(APP)（版本 $(VERSION)$(if $(AGENT),，含 agent,，不含 agent)）"

run: app ## 打包并启动（必须经 open 启动，蓝牙权限才归属本 App）
	-pkill -x MideaBar && sleep 1
	open $(APP)

dist: app ## 打成发布用的 zip：build/MideaBar-$(VERSION).zip
	cd build && rm -f MideaBar-$(VERSION).zip && ditto -c -k --keepParent MideaBar.app MideaBar-$(VERSION).zip
	@echo "✓ 生成发布包: build/MideaBar-$(VERSION).zip"

clean: ## 清理构建产物
	rm -rf build .build
