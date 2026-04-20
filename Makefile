BINARY      := claude-notify
SRC         := src/main.swift
BUILD_DIR   := build
INSTALL_DIR := $(HOME)/.claude/hooks

VERSION     := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
VERSION_SRC := $(BUILD_DIR)/version.swift

SWIFTC_FLAGS := -O
SRCS := $(SRC) $(VERSION_SRC)

.PHONY: all build install uninstall clean run test universal version

all: build

build: $(BUILD_DIR)/$(BINARY)

$(VERSION_SRC): FORCE
	@mkdir -p $(BUILD_DIR)
	@printf 'let CLAUDE_NOTIFY_VERSION = "%s"\n' "$(VERSION)" > $@.tmp
	@cmp -s $@.tmp $@ 2>/dev/null || mv $@.tmp $@
	@rm -f $@.tmp

$(BUILD_DIR)/$(BINARY): $(SRCS)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFTC_FLAGS) -o $@ $(SRCS)
	@echo "Built $@ (version $(VERSION))"

# Fat binary for releases. Slower to build; use `make build` for dev iteration.
universal: $(VERSION_SRC)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFTC_FLAGS) -target arm64-apple-macos12  -o $(BUILD_DIR)/$(BINARY)-arm64   $(SRCS)
	swiftc $(SWIFTC_FLAGS) -target x86_64-apple-macos12 -o $(BUILD_DIR)/$(BINARY)-x86_64  $(SRCS)
	lipo -create -output $(BUILD_DIR)/$(BINARY) $(BUILD_DIR)/$(BINARY)-arm64 $(BUILD_DIR)/$(BINARY)-x86_64
	@echo "Built universal $(BUILD_DIR)/$(BINARY) (version $(VERSION))"
	@lipo -info $(BUILD_DIR)/$(BINARY)

install: build
	@mkdir -p $(INSTALL_DIR)
	cp $(BUILD_DIR)/$(BINARY) $(INSTALL_DIR)/$(BINARY)
	@chmod +x $(INSTALL_DIR)/$(BINARY)
	@echo "Installed to $(INSTALL_DIR)/$(BINARY) (version $(VERSION))"
	@echo ""
	@echo "Next: add the hook to ~/.claude/settings.json — see README."

uninstall:
	@rm -f $(INSTALL_DIR)/$(BINARY)
	@echo "Removed $(INSTALL_DIR)/$(BINARY)"
	@echo "Remember to also remove the hook entry from ~/.claude/settings.json."

run: build
	./$(BUILD_DIR)/$(BINARY) "测试弹窗 · test notification"

test: build
	@BIN=$(BUILD_DIR)/$(BINARY) ./tests/regression.sh

version: build
	@$(BUILD_DIR)/$(BINARY) --version

clean:
	rm -rf $(BUILD_DIR)

FORCE:
