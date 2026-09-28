PREFIX ?= $(HOME)/.local
CONFIGURATION ?= release

.PHONY: build test install clean

build:
	swift build -c $(CONFIGURATION) --product contactctl
	codesign --force --sign - --identifier com.tkoenig.contactctl ".build/$(CONFIGURATION)/contactctl"

test:
	swift test --enable-code-coverage

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 ".build/$(CONFIGURATION)/contactctl" "$(PREFIX)/bin/contactctl"

clean:
	swift package clean
