.PHONY: build test app dmg run clean

build:
	swift build

test:
	./Scripts/test.sh

app:
	./Scripts/build-app.sh

dmg:
	./Scripts/package-dmg.sh

run: app
	open "dist/Codex Remaining.app"

clean:
	swift package clean
