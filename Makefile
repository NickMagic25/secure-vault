PRODUCT  = secure-vault
BUILD_DIR = .build/release
XCODE_PROJECT = secure-vault.xcodeproj
APP_PRODUCT = SecureVault.app
APP_EXECUTABLE = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(PRODUCT)
APP_INSTALL_DIR ?= /Applications
BIN_DIR ?= /usr/local/bin

# Your Apple Developer Team ID — the value in parentheses from:
#   security find-identity -v -p codesigning
# e.g. "Apple Development: Your Name (YOURTEAMID)" -> DEVELOPMENT_TEAM=YOURTEAMID
#
# Pass on the command line or export in your shell:
#   make sign DEVELOPMENT_TEAM=YOURTEAMID
#   make sign DEVELOPMENT_TEAM=YOURTEAMID BUNDLE_ID=com.example.vault
DEVELOPMENT_TEAM ?=
BUNDLE_ID        ?= io.securevault

.PHONY: build sign install uninstall clean

build:
	swift build -c release

# sign uses xcodebuild so Xcode's automatic signing can create/refresh the
# provisioning profile that backs the keychain-access-groups entitlement.
# CONFIGURATION_BUILD_DIR redirects the signed app bundle into .build/release/.
sign:
	@test -n "$(DEVELOPMENT_TEAM)" || { echo "Error: pass your Team ID: make sign DEVELOPMENT_TEAM=XXXXXXXXXX"; exit 1; }
	xcodebuild \
		-project "$(XCODE_PROJECT)" \
		-scheme "$(PRODUCT)" \
		-configuration Release \
		-destination "platform=macOS" \
		-derivedDataPath .build/xcode \
		CONFIGURATION_BUILD_DIR="$(CURDIR)/$(BUILD_DIR)" \
		CODE_SIGN_STYLE=Automatic \
		DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
		PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) \
		CODE_SIGN_ENTITLEMENTS=SecureVault.entitlements \
		ENABLE_HARDENED_RUNTIME=YES \
		-allowProvisioningUpdates \
		build
	@echo "Signed $(BUILD_DIR)/$(APP_PRODUCT)"
	@echo "CLI executable: $(APP_EXECUTABLE)"

install: sign
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	cp -R "$(BUILD_DIR)/$(APP_PRODUCT)" "$(APP_INSTALL_DIR)/"
	install -d "$(BIN_DIR)"
	printf '%s\n' '#!/bin/sh' 'exec "$(APP_INSTALL_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(PRODUCT)" "$$@"' > "$(BIN_DIR)/$(PRODUCT)"
	chmod 755 "$(BIN_DIR)/$(PRODUCT)"
	@echo "Installed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	@echo "Installed CLI wrapper to $(BIN_DIR)/$(PRODUCT)"

uninstall:
	rm -f "$(BIN_DIR)/$(PRODUCT)"
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	@echo "Removed $(BIN_DIR)/$(PRODUCT)"
	@echo "Removed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"

clean:
	swift package clean
	rm -rf .build/xcode
