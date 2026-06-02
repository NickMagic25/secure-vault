PRODUCT = SecureVault
CLI_PRODUCT = secure-vault
BUILD_DIR = .build/release
XCODE_PROJECT = secure-vault.xcodeproj
XCODE_SCHEME = secure-vault
APP_PRODUCT = SecureVault.app
VALIDATION_SCRIPT = scripts/validate-secure-vault.sh
APP_INSTALL_DIR ?= /Applications
SYSTEM_BIN_DIR = /usr/local/bin
USER_BIN_DIR ?= $(HOME)/.local/bin
BIN_DIR ?=

# Your Apple Developer Team ID - the value in parentheses from:
#   security find-identity -v -p codesigning
# e.g. "Apple Development: Your Name (YOURTEAMID)" -> DEVELOPMENT_TEAM=YOURTEAMID
#
# Pass on the command line, export in your shell, or set it in
# SecureVault.local.xcconfig.
#   make sign DEVELOPMENT_TEAM=YOURTEAMID
#   make sign DEVELOPMENT_TEAM=YOURTEAMID BUNDLE_ID=com.example.vault
DEVELOPMENT_TEAM ?=
BUNDLE_ID ?= io.securevault
LOCAL_SIGNING_CONFIG = SecureVault.local.xcconfig

single_quote := '
double_quote := "
backtick := `
semicolon := ;
ampersand := &
pipe := |
less_than := <
greater_than := >
dollar_sign := $$
unsafe_shell_chars := $(single_quote) $(double_quote) $(backtick) $(semicolon) $(ampersand) $(pipe) $(less_than) $(greater_than) $(dollar_sign)

resolved_value = $(if $(filter command line environment environment override,$(origin $(1))),$(value $(1)),$($(1)))
unsafe_chars_in = $(strip $(foreach char,$(unsafe_shell_chars),$(if $(findstring $(char),$(call resolved_value,$(1))),$(char))))
require_safe_shell_value = $(if $(call unsafe_chars_in,$(1)),$(error $(1) contains unsafe shell metacharacter(s): $(call unsafe_chars_in,$(1))))

shell_sensitive_vars = PRODUCT CLI_PRODUCT BUILD_DIR XCODE_PROJECT XCODE_SCHEME APP_PRODUCT VALIDATION_SCRIPT APP_INSTALL_DIR SYSTEM_BIN_DIR USER_BIN_DIR BIN_DIR DEVELOPMENT_TEAM BUNDLE_ID LOCAL_SIGNING_CONFIG
$(foreach var,$(shell_sensitive_vars),$(call require_safe_shell_value,$(var)))

PRODUCT := $(call resolved_value,PRODUCT)
CLI_PRODUCT := $(call resolved_value,CLI_PRODUCT)
BUILD_DIR := $(call resolved_value,BUILD_DIR)
XCODE_PROJECT := $(call resolved_value,XCODE_PROJECT)
XCODE_SCHEME := $(call resolved_value,XCODE_SCHEME)
APP_PRODUCT := $(call resolved_value,APP_PRODUCT)
VALIDATION_SCRIPT := $(call resolved_value,VALIDATION_SCRIPT)
APP_INSTALL_DIR := $(call resolved_value,APP_INSTALL_DIR)
SYSTEM_BIN_DIR := $(call resolved_value,SYSTEM_BIN_DIR)
USER_BIN_DIR := $(call resolved_value,USER_BIN_DIR)
BIN_DIR := $(call resolved_value,BIN_DIR)
DEVELOPMENT_TEAM := $(call resolved_value,DEVELOPMENT_TEAM)
BUNDLE_ID := $(call resolved_value,BUNDLE_ID)
LOCAL_SIGNING_CONFIG := $(call resolved_value,LOCAL_SIGNING_CONFIG)
APP_EXECUTABLE = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(PRODUCT)
CLI_EXECUTABLE = $(BUILD_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(CLI_PRODUCT)

.PHONY: build test full-test full-tests sign install uninstall clean

build:
	swift build -c release --product "$(PRODUCT)"
	swift build -c release --product "$(CLI_PRODUCT)"

test:
	swift test

full-test: test sign
	SECURE_VAULT_BIN="$(CURDIR)/$(CLI_EXECUTABLE)" "$(VALIDATION_SCRIPT)"

full-tests: full-test

# sign uses xcodebuild so Xcode's automatic signing can create/refresh the
# provisioning profile that backs the keychain-access-groups entitlement. The
# app target depends on the CLI target and embeds the signed CLI helper into the
# app bundle, so the resulting bundle supports both GUI and command-line use.
sign:
	@if [ -z "$(DEVELOPMENT_TEAM)" ] && ! grep -q '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' "$(LOCAL_SIGNING_CONFIG)" 2>/dev/null; then \
		echo "Error: pass your Team ID: make sign DEVELOPMENT_TEAM=XXXXXXXXXX"; \
		echo "       or create $(LOCAL_SIGNING_CONFIG) with DEVELOPMENT_TEAM = XXXXXXXXXX"; \
		exit 1; \
	fi
	xcodebuild \
		-project "$(XCODE_PROJECT)" \
		-scheme "$(XCODE_SCHEME)" \
		-configuration Release \
		-destination "platform=macOS" \
		-derivedDataPath .build/xcode \
		CONFIGURATION_BUILD_DIR="$(CURDIR)/$(BUILD_DIR)" \
		CODE_SIGN_STYLE=Automatic \
		$(if $(DEVELOPMENT_TEAM),"DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)",) \
		"PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID)" \
		CODE_SIGN_ENTITLEMENTS=SecureVault.entitlements \
		ENABLE_HARDENED_RUNTIME=YES \
		-allowProvisioningUpdates \
		build
	@echo "Signed $(BUILD_DIR)/$(APP_PRODUCT)"
	@echo "GUI executable: $(APP_EXECUTABLE)"
	@echo "CLI executable: $(CLI_EXECUTABLE)"

install: sign
	@bin_dir="$(BIN_DIR)"; \
	if [ -z "$$bin_dir" ]; then \
		if [ -d "$(SYSTEM_BIN_DIR)" ] && [ -w "$(SYSTEM_BIN_DIR)" ]; then \
			bin_dir="$(SYSTEM_BIN_DIR)"; \
		else \
			bin_dir="$(USER_BIN_DIR)"; \
		fi; \
	fi; \
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"; \
	cp -R "$(BUILD_DIR)/$(APP_PRODUCT)" "$(APP_INSTALL_DIR)/"; \
	mkdir -p "$$bin_dir"; \
	test -w "$$bin_dir" || { \
		echo "Error: $$bin_dir is not writable."; \
		echo "       Choose a writable directory with BIN_DIR=/path/to/bin, or run with sudo for a system install."; \
		exit 1; \
	}; \
	printf '%s\n' '#!/bin/sh' 'exec "$(APP_INSTALL_DIR)/$(APP_PRODUCT)/Contents/MacOS/$(CLI_PRODUCT)" "$$@"' > "$$bin_dir/$(CLI_PRODUCT)"; \
	chmod 755 "$$bin_dir/$(CLI_PRODUCT)"; \
	echo "Installed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"; \
	echo "Installed CLI wrapper to $$bin_dir/$(CLI_PRODUCT)"; \
	case ":$$PATH:" in *:"$$bin_dir":*) ;; *) echo "Note: add $$bin_dir to PATH to run $(CLI_PRODUCT) from any shell." ;; esac

uninstall:
	@bin_dir="$(BIN_DIR)"; \
	if [ -z "$$bin_dir" ]; then \
		if [ -d "$(SYSTEM_BIN_DIR)" ] && [ -w "$(SYSTEM_BIN_DIR)" ]; then \
			bin_dir="$(SYSTEM_BIN_DIR)"; \
		else \
			bin_dir="$(USER_BIN_DIR)"; \
		fi; \
	fi; \
	rm -f "$$bin_dir/$(CLI_PRODUCT)"; \
	rm -rf "$(APP_INSTALL_DIR)/$(APP_PRODUCT)"; \
	echo "Removed $$bin_dir/$(CLI_PRODUCT)"; \
	echo "Removed $(APP_INSTALL_DIR)/$(APP_PRODUCT)"

clean:
	swift package clean
	rm -rf .build/xcode
