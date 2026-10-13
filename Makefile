.PHONY: build test app run clean

build:
	/bin/zsh scripts/swift.sh build

test:
	/bin/zsh scripts/swift.sh test

app:
	/bin/zsh scripts/build-app.sh

run: app
	open dist/AltTabber.app

clean:
	swift package clean
	rm -rf dist
