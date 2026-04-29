.PHONY: deps vad-model analyze test verify clean setup doctor env run-web run-ios run-ios-dev run-macos simulator install-ios install-ios-dev help

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

## verify: Run all checks (analyze + test)
verify: analyze test

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

## install-ios: Build and install stable on a physical iOS device (USB or wireless)
install-ios:
	@DEVICE_ID=$$(flutter devices 2>/dev/null | grep '• ios •' | head -1 | awk -F'•' '{gsub(/^[ \t]+|[ \t]+$$/, "", $$2); print $$2}'); \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "ERROR: No physical iOS device found."; \
		echo "Connect your iPhone via USB or enable wireless debugging:"; \
		echo "  Xcode > Window > Devices and Simulators > pair your device"; \
		exit 1; \
	fi; \
	DEVICE_NAME=$$(flutter devices 2>/dev/null | grep '• ios •' | head -1 | awk -F'•' '{gsub(/[ \t]+$$/, "", $$1); print $$1}'); \
	echo "Installing stable on: $$DEVICE_NAME ($$DEVICE_ID)"; \
	flutter run -d "$$DEVICE_ID" --flavor stable $(DART_DEFINE_FLAG)

## install-ios-dev: Build and install dev on a physical iOS device (USB or wireless)
install-ios-dev:
	@DEVICE_ID=$$(flutter devices 2>/dev/null | grep '• ios •' | head -1 | awk -F'•' '{gsub(/^[ \t]+|[ \t]+$$/, "", $$2); print $$2}'); \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "ERROR: No physical iOS device found."; \
		echo "Connect your iPhone via USB or enable wireless debugging:"; \
		echo "  Xcode > Window > Devices and Simulators > pair your device"; \
		exit 1; \
	fi; \
	DEVICE_NAME=$$(flutter devices 2>/dev/null | grep '• ios •' | head -1 | awk -F'•' '{gsub(/[ \t]+$$/, "", $$1); print $$1}'); \
	echo "Installing dev on: $$DEVICE_NAME ($$DEVICE_ID)"; \
	flutter run -d "$$DEVICE_ID" --flavor dev $(DART_DEFINE_FLAG)

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
