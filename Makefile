APP_NAME   := Nudge
EXECUTABLE := Nudge
CONFIG     ?= debug
APP        := build/$(APP_NAME).app
INSTALLED  := /Applications/$(APP_NAME).app

.PHONY: build app install run test clean

build:
	swift build -c $(CONFIG)

# Wraps the SwiftPM binary in a signed .app bundle. A real bundle is required for
# notifications, launch-at-login and a stable identity for macOS permissions.
app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/$(EXECUTABLE)" "$(APP)/Contents/MacOS/"
	cp Support/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

# The copy in /Applications is the one you use day to day, and the only one that
# registers as a login item. It's an optimized release build without the debug-only
# snapshot tools; development runs (`make app`, -StorePath) use the debug build.
install run: CONFIG := release
install: app
	@pkill -x $(EXECUTABLE) && sleep 1 || true
	@# Remove the copy from before the app was renamed to Nudge.
	@pkill -x MacDailyUtility && sleep 1 || true
	rm -rf "/Applications/Mac Daily Utility.app"
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" "$(INSTALLED)"

run: install
	open "$(INSTALLED)"

# Command Line Tools ship Swift Testing outside the default search paths.
CLT_DEV    := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := $(if $(wildcard $(CLT_DEV)/Frameworks/Testing.framework), \
	-Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks -Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib)

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build
