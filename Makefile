.PHONY: build app install run-dev clean

build:
	swift build

app:
	scripts/build-app.sh

install:
	scripts/install.sh

run-dev: build
	.build/debug/AgentHighlightApp

clean:
	rm -rf .build build
