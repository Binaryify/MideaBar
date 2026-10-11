.PHONY: help build icon app run clean

APP     := build/MideaBar.app
VERSION ?= $(shell git describe --tags --dirty --always 2>/dev/null || echo dev)
# midea-ac-agent 可执行文件路径（见 docs/agent-protocol.md），打包时放进 App 内。
AGENT   ?=

.DEFAULT_GOAL := help

help: ## 显示此帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

build: ## 编译 Swift 可执行文件（release）
	swift build -c release

icon: ## 由 Icon/make-icon.swift 重新生成 Resources/AppIcon.icns
	@rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	swift Icon/make-icon.swift build/AppIcon-1024.png
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); sips -z $$d $$d build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "✓ 生成图标: Resources/AppIcon.icns"

app: build ## 打包 build/MideaBar.app（用法：make app AGENT=/path/to/midea-ac-agent）
	@test -n "$(AGENT)" || { echo "✗ 请用 AGENT=/path/to/midea-ac-agent 指定后台程序，见 docs/agent-protocol.md"; exit 1; }
	@test -x "$(AGENT)" || { echo "✗ $(AGENT) 不存在或不可执行"; exit 1; }
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/MideaBar $(APP)/Contents/MacOS/MideaBar
	cp "$(AGENT)" $(APP)/Contents/MacOS/midea-ac-agent
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)
	@echo "✓ 生成 App: $(APP)"

run: app ## 打包并启动（必须经 open 启动，蓝牙权限才归属本 App）
	-pkill -x MideaBar && sleep 1
	open $(APP)

clean: ## 清理构建产物
	rm -rf build .build
