# Host-side build & test (macOS/Linux).  The OPENSTEP build lives in Makefile.openstep.
# Flags approximate what gcc 2.7.2 will accept: strict C89, no // comments,
# no mixed declarations, no stdint.
CC      ?= cc
CFLAGS  = -std=c89 -pedantic -Wall -Wextra -Wdeclaration-after-statement \
          -Wno-long-long -Wno-unused-parameter -O2 -g
BUILD   = build

TERM_SRC = $(wildcard term/*.c)
TERM_OBJ = $(patsubst term/%.c,$(BUILD)/term_%.o,$(TERM_SRC))

all: test

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/term_%.o: term/%.c $(wildcard term/*.h) | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/test_vt: tests/test_vt.c $(TERM_OBJ)
	$(CC) $(CFLAGS) tests/test_vt.c $(TERM_OBJ) -o $@

test: $(BUILD)/test_vt
	$(BUILD)/test_vt

lint:
	sh tools/lint_openstep.sh

# Syntax-check the Objective-C against the modern SDK (never linked or run).
check-objc:
	for f in app/*.m; do \
	  echo "check $$f"; \
	  $(CC) -fsyntax-only -x objective-c -fno-objc-arc -Wall -Wno-deprecated-declarations \
	    -Wdeclaration-after-statement -Wno-unused-parameter -Iterm -Iapp $$f || exit 1; \
	done

# Package the sources for transfer into the OPENSTEP VM.
#   dist/TTY.TAR  plain ustar archive (extract with:  tar xf TTY.TAR)
#   dist/TTY.ISO  a CD image containing TTY.TAR (attach it as a CD-ROM in the VM)
# -b 20 matters: see StepSSH's own Makefile for why (old tar implementations read archives in
# fixed 10240-byte records; a short final record makes their first read() look like premature EOF).
DISTFILES = README.md Makefile.openstep term app tests tools
dist:
	mkdir -p dist
	COPYFILE_DISABLE=1 tar --format ustar -b 20 --exclude '*.o' --exclude '.DS_Store' \
	    -cf dist/TTY.TAR $(DISTFILES)
	rm -rf dist/iso && mkdir -p dist/iso && cp dist/TTY.TAR dist/iso/
	rm -f dist/TTY.ISO dist/TTY.iso dist/TTY.iso.iso
	hdiutil makehybrid -iso -iso-volume-name TTY -o dist/TTY dist/iso >/dev/null
	f=$$(ls dist/TTY.* | grep -iv 'TTY.TAR' | head -1); mv "$$f" dist/TTY.ISO
	rm -rf dist/iso
	@ls -l dist/TTY.TAR dist/TTY.ISO

# Drives a real PTYSession (pty, fork, exec a shell) against a real forked shell on the host --
# the closest thing to session-smoke.m StepSSH has, just against a local shell instead of sshd.
UI_SRC = app/AppController.m app/PTYSession.m app/TerminalView.m app/UIHelpers.m
pty-smoke:
	mkdir -p build
	for f in tests/pty_smoke.m $(UI_SRC); do \
	  $(CC) -c -x objective-c -fno-objc-arc -w -g -Iterm -Iapp $$f -o build/ps_$$(basename $$f .m).o || exit 1; \
	done
	for f in term/*.c; do $(CC) -c -w -g -Iterm $$f -o build/ps_c_$$(basename $$f .c).o || exit 1; done
	$(CC) build/ps_*.o -framework Cocoa -o build/pty_smoke
	build/pty_smoke

clean:
	rm -rf build

.PHONY: all test lint check-objc pty-smoke dist clean
