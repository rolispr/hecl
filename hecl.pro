LQML = /Users/bret.horne/common-lisp/lqml

LISP_FILES = $$files(src/*) hecl.asd make.lisp

unix {
  lisp.commands = ecl -shell $$PWD/make.lisp
}

lisp.input = LISP_FILES

win32:  lisp.output = build/tmp/app.lib
!win32: lisp.output = build/tmp/libapp.a

QMAKE_EXTRA_COMPILERS += lisp

win32:  PRE_TARGETDEPS = build/tmp/app.lib
!win32: PRE_TARGETDEPS = build/tmp/libapp.a

QT          += quick qml quickcontrols2
TEMPLATE    = app
CONFIG      += c++17 no_keywords release sdk_no_version_check
QMAKE_MACOSX_DEPLOYMENT_TARGET = 13.0
DEFINES     = DESKTOP_APP INI_LISP
INCLUDEPATH = /usr/local/include /opt/homebrew/include
LIBS        = -L/usr/local/lib -L/opt/homebrew/lib
DESTDIR     = build
TARGET      = hecl
OBJECTS_DIR = build/tmp
MOC_DIR     = build/tmp

macx {
  CONFIG -= app_bundle
  LIBS += -L$$LQML/platforms/macos/lib
  QMAKE_LFLAGS += -Wl,-ld_classic
}

linux {
  LIBS += -L$$LQML/platforms/linux/lib
}

LIBS += -Lbuild/tmp -lapp -L$$PWD/lib/zig-out/lib -lhecl-gterm -llqml -llisp -L/usr/local/lib -lecl

HEADERS += $$LQML/src/cpp/main.h
SOURCES += $$LQML/src/cpp/main.cpp lib/spawn-ctty.c

RESOURCES += qml/qml.qrc
