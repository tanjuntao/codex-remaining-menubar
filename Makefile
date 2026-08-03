.PHONY: build test app run clean

build:
	swift build

test:
	./Scripts/test.sh

app:
	./Scripts/build-app.sh

run: app
	open "dist/Codex Remaining.app"

clean:
	swift package clean
