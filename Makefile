PRODUCT_NAME  = Flapline
PROJECT       = SplitFlap.xcodeproj
SCHEME        = SplitFlap
BUILD_DIR     = build
INSTALL_DIR   = $(HOME)/Library/Screen\ Savers
SAVER_RELEASE = $(BUILD_DIR)/Build/Products/Release/$(PRODUCT_NAME).saver
SAVER_DEBUG   = $(BUILD_DIR)/Build/Products/Debug/$(PRODUCT_NAME).saver
INSTALLED_SAVER = $(HOME)/Library/Screen Savers/$(PRODUCT_NAME).saver
SIGN_IDENTITY ?=
DEVELOPMENT_TEAM ?=

ifneq ($(SIGN_IDENTITY),)
XCODE_SIGN_FLAGS = CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" CODE_SIGN_STYLE=Manual
ifneq ($(DEVELOPMENT_TEAM),)
XCODE_SIGN_FLAGS += DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)
endif
endif

.PHONY: all build debug install uninstall clean

all: build

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=NO \
		$(XCODE_SIGN_FLAGS) \
		build

debug:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		$(XCODE_SIGN_FLAGS) \
		build

install: build
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(PRODUCT_NAME).saver
	cp -R "$(SAVER_RELEASE)" $(INSTALL_DIR)/
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none "$(INSTALLED_SAVER)/Contents/MacOS/$(PRODUCT_NAME)"; \
		codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none "$(INSTALLED_SAVER)"; \
	fi
	@echo "Installed to $(INSTALL_DIR)/$(PRODUCT_NAME).saver"
	-killall ScreenSaverEngine 2>/dev/null; true

install-debug: debug
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(PRODUCT_NAME).saver
	cp -R "$(SAVER_DEBUG)" $(INSTALL_DIR)/
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none "$(INSTALLED_SAVER)/Contents/MacOS/$(PRODUCT_NAME)"; \
		codesign --force --sign "$(SIGN_IDENTITY)" --timestamp=none "$(INSTALLED_SAVER)"; \
	fi
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
