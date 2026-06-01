PRODUCT  = secure-vault
BUILD_DIR = .build/release
XCODE_PROJECT = secure-vault.xcodeproj
APP_PRODUCT = SecureVault.app
APP_EXECUTABLE = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(PRODUCT)
VALIDATION_SCRIPT = scripts/validate-secure-vault.sh
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
LOCAL_SIGNING_CONFIG = SecureVault.local.xcconfig

.PHONY: build test full-test full-tests sign install uninstall clean

build:
	swift build -c release

test:
	swift test

full-test: test sign
	SECURE_VAULT_BIN="$(CURDIR)/$(APP_EXECUTABLE)" "$(VALIDATION_SCRIPT)"

full-tests: full-test

# sign uses xcodebuild so Xcode's automatic signing can create/refresh the
# provisioning profile that backs the keychain-access-groups entitlement.
# CONFIGURATION_BUILD_DIR redirects the signed app bundle into .build/release/.
sign:
	@if [ -z "$(DEVELOPMENT_TEAM)" ] && ! grep -q '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' "$(LOCAL_SIGNING_CONFIG)" 2>/dev/null; then \
		echo "Error: pass your Team ID: make sign DEVELOPMENT_TEAM=XXXXXXXXXX"; \
		echo "       or create $(LOCAL_SIGNING_CONFIG) with DEVELOPMENT_TEAM = XXXXXXXXXX"; \
		exit 1; \
	fi
	xcodebuild \
		-project "$(XCODE_PROJECT)" \
		-scheme "$(PRODUCT)" \
		-configuration Release \
		-destination "platform=macOS" \
		-derivedDataPath .build/xcode \
		CONFIGURATION_BUILD_DIR="$(CURDIR)/$(BUILD_DIR)" \
		CODE_SIGN_STYLE=Automatic \
		$(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),) \
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
	mkdir -p "$(BIN_DIR)"
	@test -w "$(BIN_DIR)" || { \
		echo "Error: $(BIN_DIR) is not writable."; \
		echo "       Choose a writable directory with BIN_DIR=/path/to/bin, or run with sudo for a system install."; \
		exit 1; \
	}
	printf '%s\n' '#!/bin/sh' 'exec "$(APP_INSTALL_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(PRODUCT)" "$$@"' > "$(BIN_DIR)/$(PRODUCT)"
	chmod 755 "$(BIN_DIR)/$(PRODUCT)"
	@echo "Installed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	@echo "Installed CLI wrapper to $(BIN_DIR)/$(PRODUCT)"
	@case ":$$PATH:" in *:"$(BIN_DIR)":*) ;; *) echo "Note: add $(BIN_DIR) to PATH to run $(PRODUCT) from any shell." ;; esac

uninstall:
	rm -f "$(BIN_DIR)/$(PRODUCT)"
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"
	@echo "Removed $(BIN_DIR)/$(PRODUCT)"
	@echo "Removed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"

clean:
	swift package clean
	rm -rf .build/xcode
