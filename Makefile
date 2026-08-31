APP := MacTyper
SCHEME := MacTyper
BUILD_DIR := build

.PHONY: gen build test run release clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) test

run: build
	open $(BUILD_DIR)/Build/Products/Release/$(APP).app

release:
	./scripts/release.sh

clean:
	rm -rf $(BUILD_DIR) $(APP).xcodeproj
