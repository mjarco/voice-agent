.PHONY: deps model analyze test verify clean

WHISPER_MODEL_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
WHISPER_MODEL_DIR := assets/models
WHISPER_MODEL_PATH := $(WHISPER_MODEL_DIR)/ggml-base.bin

## deps: Install Flutter dependencies
deps:
	flutter pub get

## model: Download Whisper base model (~140 MB) if not present
model: $(WHISPER_MODEL_PATH)

$(WHISPER_MODEL_PATH):
	@mkdir -p $(WHISPER_MODEL_DIR)
	@echo "Downloading Whisper base model (~140 MB)..."
	curl -L -o $(WHISPER_MODEL_PATH) $(WHISPER_MODEL_URL)
	@echo "Model downloaded to $(WHISPER_MODEL_PATH)"

## analyze: Run Flutter static analysis
analyze:
	flutter analyze

## test: Run all tests
test:
	flutter test

## verify: Run all checks (analyze + test)
verify: analyze test

## setup: Full project setup (deps + model)
setup: deps model

## clean: Remove build artifacts and downloaded models
clean:
	flutter clean
	rm -rf $(WHISPER_MODEL_DIR)

## help: Show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## //' | column -t -s ':'
