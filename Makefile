.PHONY: dev build test clean vendor gterm

LQML_BIN := $(HOME)/common-lisp/lqml/src/build/lqml
GHOSTTY_DIR := lib/vendor/ghostty
GHOSTTY_REPO := https://github.com/ghostty-org/ghostty.git

vendor:
	git submodule update --init --recursive

QT_HEADERS := $(shell qmake -query QT_INSTALL_HEADERS)
QT_LIBS := $(shell qmake -query QT_INSTALL_LIBS)
ECL_HEADERS := /opt/homebrew/include

gterm: vendor
	@if [ ! -d "$(GHOSTTY_DIR)" ]; then \
		echo "Cloning ghostty into $(GHOSTTY_DIR)..."; \
		git clone --depth 1 $(GHOSTTY_REPO) $(GHOSTTY_DIR); \
	fi
	cd lib && zig build -Doptimize=ReleaseSafe
	cc -shared -o lib/libts-wrapper.dylib lib/ts-wrapper.c -I/opt/homebrew/include -L/opt/homebrew/lib -ltree-sitter
	c++ -std=c++17 -shared -fPIC -o lib/libhecl-pushframe.dylib lib/push-frame.cpp \
		-I$(QT_HEADERS) -I$(QT_HEADERS)/QtCore -I$(QT_HEADERS)/QtQml \
		-I$(ECL_HEADERS) \
		-L$(QT_LIBS) -F$(QT_LIBS) \
		-framework QtCore -framework QtQml \
		-L/opt/homebrew/lib -lecl

dev: vendor gterm
	$(LQML_BIN) run.lisp

build: vendor gterm
	mkdir -p build/tmp build/build/tmp
	cd build && qmake ../hecl.pro && $(MAKE)

test: vendor
	ecl -q --load init.lisp \
		--eval '(asdf:test-system :hecl)' \
		--eval '(ext:quit 0)'

clean:
	rm -rf build/
	cd lib && rm -rf zig-out .zig-cache
