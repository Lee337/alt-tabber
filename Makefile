.PHONY: build test app dmg installer release-artifacts run clean

build:
	/bin/zsh scripts/swift.sh build

test:
	/bin/zsh scripts/swift.sh test

app:
	/bin/zsh scripts/build-app.sh

dmg:
	/bin/zsh scripts/build-dmg.sh

installer:
	/bin/zsh scripts/build-installer.sh

release-artifacts:
	/bin/zsh scripts/package-release.sh

run: app
	open dist/AltTabber.app

clean:
	swift package clean
	rm -rf dist
