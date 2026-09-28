PREFIX ?= $(HOME)/.local
CONFIGURATION ?= release

.PHONY: build test install clean

build:
	swift build -c $(CONFIGURATION)

test:
	swift run contactctl-core-checks

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 ".build/$(CONFIGURATION)/contactctl" "$(PREFIX)/bin/contactctl"

clean:
	swift package clean
