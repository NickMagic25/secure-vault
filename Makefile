PRODUCT  = SecureVault
CLI_PRODUCT = secure-vault
BUILD_DIR = .build/release
XCODE_PROJECT = secure-vault.xcodeproj
APP_PRODUCT = SecureVault.app
APP_EXECUTABLE = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(PRODUCT)
CLI_EXECUTABLE = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(CLI_PRODUCT)
INFO_PLIST = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/Info.plist
EXPANDED_ENTITLEMENTS = $(BUILD_DIR)/SecureVault.expanded.entitlements
APP_INSTALL_DIR ?= /Applications
SYSTEM_BIN_DIR = /usr/local/bin
USER_BIN_DIR ?= $(HOME)/.local/bin
BIN_DIR ?= $(shell if [ -d "$(SYSTEM_BIN_DIR)" ] && [ -w "$(SYSTEM_BIN_DIR)" ]; then printf '%s' "$(SYSTEM_BIN_DIR)"; else printf '%s' "$(USER_BIN_DIR)"; fi)

# Your Apple Developer Team ID — the value in parentheses from:
#   security find-identity -v -p codesigning
# e.g. "Apple Development: Your Name (YOURTEAMID)" -> DEVELOPMENT_TEAM=YOURTEAMID
#
# Pass on the command line, export in your shell, or set it in
# SecureVault.local.xcconfig.
#   make sign DEVELOPMENT_TEAM=YOURTEAMID
#   make sign DEVELOPMENT_TEAM=YOURTEAMID BUNDLE_ID=com.example.vault
DEVELOPMENT_TEAM ?=
BUNDLE_ID        ?= io.securevault
CODE_SIGN_IDENTITY ?= Apple Development
LOCAL_SIGNING_CONFIG = SecureVault.local.xcconfig
SIGNING_TEAM = $(strip $(if $(DEVELOPMENT_TEAM),$(DEVELOPMENT_TEAM),$(shell sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$(LOCAL_SIGNING_CONFIG)" 2>/dev/null | tail -n 1)))

.PHONY: build bundle sign install uninstall clean

build:
	swift build -c release --product "$(PRODUCT)"
	swift build -c release --product "$(CLI_PRODUCT)"

bundle: build
	rm -rf "$(BUILD_DIR)/$(APP_PRODUCT)"
	mkdir -p "$(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS"
	cp "$(BUILD_DIR)/$(PRODUCT)" "$(APP_EXECUTABLE)"
	cp "$(BUILD_DIR)/$(CLI_PRODUCT)" "$(CLI_EXECUTABLE)"
	chmod 755 "$(APP_EXECUTABLE)" "$(CLI_EXECUTABLE)"
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleExecutable</key>' \
		'  <string>$(PRODUCT)</string>' \
		'  <key>CFBundleIdentifier</key>' \
		'  <string>$(BUNDLE_ID)</string>' \
		'  <key>CFBundleName</key>' \
		'  <string>$(PRODUCT)</string>' \
		'  <key>CFBundleDisplayName</key>' \
		'  <string>$(PRODUCT)</string>' \
		'  <key>CFBundlePackageType</key>' \
		'  <string>APPL</string>' \
		'  <key>LSApplicationCategoryType</key>' \
		'  <string>public.app-category.utilities</string>' \
		'  <key>LSMinimumSystemVersion</key>' \
		'  <string>13.0</string>' \
		'  <key>NSHighResolutionCapable</key>' \
		'  <true/>' \
		'  <key>NSPrincipalClass</key>' \
		'  <string>NSApplication</string>' \
		'</dict>' \
		'</plist>' > "$(INFO_PLIST)"
	@echo "Bundled $(BUILD_DIR)/$(APP_PRODUCT)"
	@echo "GUI executable: $(APP_EXECUTABLE)"
	@echo "CLI executable: $(CLI_EXECUTABLE)"

# sign creates one app bundle that contains both the GUI executable and the CLI
# helper. Both binaries receive the same keychain/Secure Enclave entitlements so
# they can read, update, encrypt, and decrypt the same vault records.
sign: bundle
	@if [ -z "$(SIGNING_TEAM)" ]; then \
		echo "Error: pass your Team ID: make sign DEVELOPMENT_TEAM=XXXXXXXXXX"; \
		echo "       or create $(LOCAL_SIGNING_CONFIG) with DEVELOPMENT_TEAM = XXXXXXXXXX"; \
		exit 1; \
	fi
	sed \
		-e 's/$$(DEVELOPMENT_TEAM)/$(SIGNING_TEAM)/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
		SecureVault.entitlements > "$(EXPANDED_ENTITLEMENTS)"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --options runtime --entitlements "$(EXPANDED_ENTITLEMENTS)" "$(CLI_EXECUTABLE)"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --options runtime --entitlements "$(EXPANDED_ENTITLEMENTS)" "$(APP_EXECUTABLE)"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" --options runtime --entitlements "$(EXPANDED_ENTITLEMENTS)" "$(BUILD_DIR)/$(APP_PRODUCT)"
	@echo "Signed $(BUILD_DIR)/$(APP_PRODUCT)"
	@echo "GUI executable: $(APP_EXECUTABLE)"
	@echo "CLI executable: $(CLI_EXECUTABLE)"

install: sign
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	cp -R "$(BUILD_DIR)/$(APP_PRODUCT)" "$(APP_INSTALL_DIR)/"
	mkdir -p "$(BIN_DIR)"
	@test -w "$(BIN_DIR)" || { \
		echo "Error: $(BIN_DIR) is not writable."; \
		echo "       Choose a writable directory with BIN_DIR=/path/to/bin, or run with sudo for a system install."; \
		exit 1; \
	}
	printf '%s\n' '#!/bin/sh' 'exec "$(APP_INSTALL_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(CLI_PRODUCT)" "$$@"' > "$(BIN_DIR)/$(CLI_PRODUCT)"
	chmod 755 "$(BIN_DIR)/$(CLI_PRODUCT)"
	@echo "Installed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	@echo "Installed CLI wrapper to $(BIN_DIR)/$(CLI_PRODUCT)"
	@case ":$$PATH:" in *:"$(BIN_DIR)":*) ;; *) echo "Note: add $(BIN_DIR) to PATH to run $(CLI_PRODUCT) from any shell." ;; esac

uninstall:
	rm -f "$(BIN_DIR)/$(CLI_PRODUCT)"
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	@echo "Removed $(BIN_DIR)/$(CLI_PRODUCT)"
	@echo "Removed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"

clean:
	swift package clean
	rm -rf .build/xcode
