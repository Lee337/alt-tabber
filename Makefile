.PHONY: build test app installer run clean

build:
	/bin/zsh scripts/swift.sh build

test:
	/bin/zsh scripts/swift.sh test

app:
	/bin/zsh scripts/build-app.sh

installer:
	/bin/zsh scripts/build-installer.sh

run: app
	open dist/AltTabber.app

clean:
	swift package clean
	rm -rf dist
