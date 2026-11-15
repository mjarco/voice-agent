.PHONY: deps vad-model analyze test verify test-changed verify-changed test-times clean setup doctor env run-web run-ios run-ios-dev run-macos simulator install-ios install-ios-dev install-ios-dev-debug install-android install-android-dev tag help

MODEL_DIR := assets/models

VAD_MODEL_URL := https://cdn.jsdelivr.net/npm/@keyurmaru/vad@0.0.1/silero_vad_v5.onnx
VAD_MODEL_PATH := $(MODEL_DIR)/silero_vad_v5.onnx

# Inject compile-time defaults from .env.mobile when the file has content.
ENV_FILE := .env.mobile
DART_DEFINE_FLAG := $(shell test -s $(ENV_FILE) && echo "--dart-define-from-file=$(ENV_FILE)")

# ──────────────────────────────────────────────
# Project setup
# ──────────────────────────────────────────────

## deps: Install Flutter dependencies
deps:
	flutter pub get

## vad-model: Download Silero VAD v5 ONNX model (~2 MB) if not present
vad-model: $(VAD_MODEL_PATH)

$(VAD_MODEL_PATH):
	@mkdir -p $(MODEL_DIR)
	@echo "Downloading Silero VAD v5 model (~2 MB)..."
	curl -L -o $(VAD_MODEL_PATH) $(VAD_MODEL_URL)
	@echo "Model downloaded to $(VAD_MODEL_PATH)"

## setup: Full project setup (deps + models)
setup: deps vad-model

# ──────────────────────────────────────────────
# Quality checks
# ──────────────────────────────────────────────

## analyze: Run Flutter static analysis
analyze:
	flutter analyze

## test: Run all tests
test:
	flutter test

## verify: Run all checks (analyze + test) — before a PR goes ready and before every push to it
verify: analyze test

## test-changed: Run the tests of the modules this branch touches (scripts/test-changed.sh; BASE=<ref>)
test-changed:
	@scripts/test-changed.sh

## verify-changed: The dev loop: analyze + the tests of the touched modules
verify-changed: analyze test-changed

## test-times: The full suite with the slowest test files listed (TOP=N, default 20)
test-times:
	@flutter test --reporter json | scripts/test-times.py --top $(or $(TOP),20)

# ──────────────────────────────────────────────
# Environment setup
# ──────────────────────────────────────────────

## doctor: Show Flutter environment status
doctor:
	flutter doctor -v

## env: Install all development tools (Xcode CLI, CocoaPods, accept licenses)
env:
	@echo "=== Checking Xcode CLI tools ==="
	@xcode-select -p > /dev/null 2>&1 || (echo "Installing Xcode CLI tools..." && xcode-select --install && echo ">>> After install completes, run 'make env' again")
	@echo ""
	@echo "=== Checking Xcode ==="
	@if [ ! -d /Applications/Xcode.app ]; then \
		echo "ERROR: Xcode not found. Install from App Store:"; \
		echo "  https://apps.apple.com/app/xcode/id497799835"; \
		echo "After install, run:"; \
		echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"; \
		echo "  sudo xcodebuild -runFirstLaunch"; \
		exit 1; \
	else \
		echo "Xcode found at /Applications/Xcode.app"; \
	fi
	@echo ""
	@echo "=== Checking CocoaPods ==="
	@which pod > /dev/null 2>&1 || (echo "Installing CocoaPods..." && brew install cocoapods)
	@echo "CocoaPods: $$(pod --version)"
	@echo ""
	@echo "=== Accepting iOS licenses ==="
	@sudo xcodebuild -license accept 2>/dev/null || true
	@echo ""
	@echo "=== Flutter doctor ==="
	@flutter doctor
	@echo ""
	@echo "=== Environment ready ==="

# ──────────────────────────────────────────────
# Run targets
# ──────────────────────────────────────────────

## run-web: Run stable flavor in Chrome (no native plugins)
run-web:
	flutter run -d chrome --flavor stable $(DART_DEFINE_FLAG)

## run-ios: Run stable flavor on iOS Simulator
run-ios: _ensure-simulator
	flutter run -d iPhone --flavor stable $(DART_DEFINE_FLAG)

## run-ios-dev: Run dev flavor on iOS Simulator
run-ios-dev: _ensure-simulator
	flutter run -d iPhone --flavor dev $(DART_DEFINE_FLAG)

## run-macos: Run the app as macOS desktop
run-macos:
	flutter run -d macos $(DART_DEFINE_FLAG)

## simulator: Open iOS Simulator
simulator:
	@open -a Simulator

# Splits flutter-devices output on '•' (with surrounding spaces collapsed).
# Field layout: $$1=name, $$2=id, $$3=platform, $$4=os version. The
# previous `grep '• ios •'` filter was brittle — flutter pads the
# platform column with whitespace so the literal pattern never matched
# on recent versions. Using awk's regex field separator handles any
# spacing.
IOS_DEVICE_ID = flutter devices 2>/dev/null | awk -F' *• *' '$$3=="ios" && $$4 !~ /simulator/{print $$2; exit}'
IOS_DEVICE_NAME = flutter devices 2>/dev/null | awk -F' *• *' '$$3=="ios" && $$4 !~ /simulator/{print $$1; exit}'
IOS_NOT_FOUND = echo "ERROR: No physical iOS device found."; \
	echo "Connect your iPhone via USB or enable wireless debugging:"; \
	echo "  Xcode > Window > Devices and Simulators > pair your device"; \
	exit 1

## install-ios: Build and install stable (release) on a physical iOS device
install-ios:
	@DEVICE_ID=$$($(IOS_DEVICE_ID)); \
	if [ -z "$$DEVICE_ID" ]; then $(IOS_NOT_FOUND); fi; \
	DEVICE_NAME=$$($(IOS_DEVICE_NAME)); \
	echo "Building stable (release)..."; \
	flutter build ios --flavor stable --release $(DART_DEFINE_FLAG) && \
	echo "Installing on: $$DEVICE_NAME ($$DEVICE_ID)" && \
	flutter install -d "$$DEVICE_ID" --flavor stable --release

## install-ios-dev: Build and install dev (release) on a physical iOS device
install-ios-dev:
	@DEVICE_ID=$$($(IOS_DEVICE_ID)); \
	if [ -z "$$DEVICE_ID" ]; then $(IOS_NOT_FOUND); fi; \
	DEVICE_NAME=$$($(IOS_DEVICE_NAME)); \
	echo "Building dev (release)..."; \
	flutter build ios --flavor dev --release $(DART_DEFINE_FLAG) && \
	echo "Installing on: $$DEVICE_NAME ($$DEVICE_ID)" && \
	flutter install -d "$$DEVICE_ID" --flavor dev --release

## install-ios-dev-debug: Build and install dev (debug, hot reload) on a physical iOS device
install-ios-dev-debug:
	@DEVICE_ID=$$($(IOS_DEVICE_ID)); \
	if [ -z "$$DEVICE_ID" ]; then $(IOS_NOT_FOUND); fi; \
	DEVICE_NAME=$$($(IOS_DEVICE_NAME)); \
	echo "Installing dev (debug) on: $$DEVICE_NAME ($$DEVICE_ID)"; \
	flutter run -d "$$DEVICE_ID" --flavor dev $(DART_DEFINE_FLAG)

# Android devices from flutter-devices output (same field layout as above);
# the platform column reads e.g. "android-arm64". Exactly one device must be
# connected over adb (USB or wireless debugging), so a build never lands on
# the wrong phone.
# adb install -r keeps the app's data (settings, token); flutter install
# uninstalls the old version first and wipes it.
ADB := $(or $(ANDROID_HOME),$(HOME)/Android/Sdk)/platform-tools/adb
# The Pixel is arm64, so the APK carries only arm64-v8a: one Dart AOT
# compilation instead of three and ~40 MB instead of ~120 MB (#423). For a
# universal APK: ANDROID_TARGET=android-arm,android-arm64,android-x64
ANDROID_TARGET ?= android-arm64
ANDROID_DEVICE_IDS = flutter devices 2>/dev/null | awk -F' *• *' '$$3 ~ /^android/{print $$2}'
ANDROID_DEVICE_CHECK = IDS=$$($(ANDROID_DEVICE_IDS)); COUNT=$$(echo "$$IDS" | grep -c .); \
	if [ "$$COUNT" -ne 1 ]; then \
	echo "ERROR: expected exactly one Android device, found $$COUNT."; \
	echo "Connect the Pixel over USB (or adb wireless debugging) and check: adb devices"; \
	exit 1; fi; DEVICE_ID=$$IDS

## install-android: Build and install stable (release) on the connected Android device
install-android: vad-model
	@$(ANDROID_DEVICE_CHECK); \
	echo "Building stable (release)..."; \
	flutter build apk --flavor stable --release --target-platform $(ANDROID_TARGET) $(DART_DEFINE_FLAG) && \
	echo "Installing on: $$DEVICE_ID" && \
	$(ADB) -s "$$DEVICE_ID" install -r build/app/outputs/flutter-apk/app-stable-release.apk

## install-android-dev: Build and install dev (release) on the connected Android device
install-android-dev: vad-model
	@$(ANDROID_DEVICE_CHECK); \
	echo "Building dev (release)..."; \
	flutter build apk --flavor dev --release --target-platform $(ANDROID_TARGET) $(DART_DEFINE_FLAG) && \
	echo "Installing on: $$DEVICE_ID" && \
	$(ADB) -s "$$DEVICE_ID" install -r build/app/outputs/flutter-apk/app-dev-release.apk

## tag: Tag main's HEAD with pubspec.yaml's version and push the tag (MSG="vX.Y.Z — …" overrides the note)
# Run after a version-bearing PR merged, in an up-to-date main checkout. The
# default note is the merge commit's subject without its "(x.y.z)" and "(#N)".
# A version that is already tagged is left alone (a build-number-only bump).
tag:
	@set -e; \
	V=$$(sed -n 's/^version: *\([0-9]*\.[0-9]*\.[0-9]*\)+.*/\1/p' pubspec.yaml); \
	if [ -z "$$V" ]; then echo "ERROR: no MAJOR.MINOR.PATCH+BUILD version in pubspec.yaml"; exit 1; fi; \
	git fetch -q origin main --tags; \
	if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ]; then \
	echo "ERROR: HEAD is not origin/main; tag from an up-to-date main checkout"; exit 1; fi; \
	if git rev-parse -q --verify "refs/tags/v$$V" >/dev/null; then \
	echo "v$$V is already tagged at $$(git rev-list -n1 "v$$V" | cut -c1-7); nothing to do"; exit 0; fi; \
	SUBJ=$$(git log -1 --format=%s | sed -E 's/ \(#[0-9]+\)$$//; s/ \([0-9]+\.[0-9]+\.[0-9]+\)$$//' \
	| awk '{print tolower(substr($$0,1,1)) substr($$0,2)}'); \
	NOTE="$${MSG:-v$$V — $$SUBJ}"; \
	git tag -a "v$$V" -m "$$NOTE"; \
	git push -q origin "v$$V"; \
	echo "tagged v$$V at $$(git rev-parse --short HEAD): $$NOTE"

## devices: List available devices
devices:
	flutter devices

# ──────────────────────────────────────────────
# Internal targets
# ──────────────────────────────────────────────

_ensure-simulator:
	@if ! xcrun simctl list devices booted 2>/dev/null | grep -q "iPhone"; then \
		echo "No booted iPhone simulator. Starting one..."; \
		DEVICE=$$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed 's/.*(\([-A-F0-9]*\)).*/\1/'); \
		if [ -n "$$DEVICE" ]; then \
			xcrun simctl boot "$$DEVICE" 2>/dev/null || true; \
			open -a Simulator; \
			echo "Waiting for simulator to boot..."; \
			sleep 5; \
		else \
			echo "ERROR: No iPhone simulator available. Open Xcode > Settings > Platforms > install iOS simulator."; \
			exit 1; \
		fi \
	fi

## clean: Remove build artifacts and downloaded models
clean:
	flutter clean
	rm -rf $(MODEL_DIR)

## help: Show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## //' | column -t -s ':'
