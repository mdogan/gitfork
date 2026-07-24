.PHONY: build test app install run clean

build:
	swift build --disable-sandbox

test:
	swift test --disable-sandbox

app:
	./scripts/build-app.sh

install: app
	@test -n "$(HOME)"
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/GitFork.app"
	/usr/bin/ditto --rsrc --extattr --acl ".build/release/GitFork.app" "$(HOME)/Applications/GitFork.app"
	codesign --verify --deep --strict --verbose=2 "$(HOME)/Applications/GitFork.app"
	@echo "Installed GitFork.app to $(HOME)/Applications"

run:
	swift run --disable-sandbox GitFork

clean:
	swift package clean
