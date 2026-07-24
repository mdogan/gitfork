.PHONY: build test app run clean

build:
	swift build --disable-sandbox

test:
	swift test --disable-sandbox

app:
	./scripts/build-app.sh

run:
	swift run --disable-sandbox GitFork

clean:
	swift package clean
