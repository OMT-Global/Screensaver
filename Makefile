PRODUCT_NAME  = SplitFlap
PROJECT       = SplitFlap.xcodeproj
SCHEME        = SplitFlap
BUILD_DIR     = build
INSTALL_DIR   = $(HOME)/Library/Screen\ Savers
SAVER_RELEASE = $(BUILD_DIR)/Build/Products/Release/$(PRODUCT_NAME).saver
SAVER_DEBUG   = $(BUILD_DIR)/Build/Products/Debug/$(PRODUCT_NAME).saver

.PHONY: all build debug install uninstall clean

all: build

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=NO \
		build

debug:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		build

install: build
	mkdir -p $(INSTALL_DIR)
	cp -R "$(SAVER_RELEASE)" $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/$(PRODUCT_NAME).saver"
	-killall ScreenSaverEngine 2>/dev/null; true

install-debug: debug
	mkdir -p $(INSTALL_DIR)
	cp -R "$(SAVER_DEBUG)" $(INSTALL_DIR)/
	@echo "Installed debug build to $(INSTALL_DIR)/$(PRODUCT_NAME).saver"
	-killall ScreenSaverEngine 2>/dev/null; true

uninstall:
	rm -rf $(INSTALL_DIR)/$(PRODUCT_NAME).saver
	@echo "Uninstalled $(PRODUCT_NAME).saver"

clean:
	rm -rf $(BUILD_DIR)

# Open the Screen Saver preference pane to preview after install
preview:
	open "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
