CC      ?= cc
ARCHS   ?= -arch arm64 -arch x86_64
CFLAGS  ?= -O2
WARN    := -w
BUILD   := build
FOO     := third_party/foo2zjs

.PHONY: all clean

all: $(BUILD)/foo2zjs $(BUILD)/rastertopbm $(BUILD)/rastertozjs-foo2zjs

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/foo2zjs: $(FOO)/foo2zjs.c $(FOO)/jbig.c $(FOO)/jbig_ar.c | $(BUILD)
	$(CC) $(ARCHS) $(CFLAGS) $(WARN) -o $@ $(FOO)/foo2zjs.c $(FOO)/jbig.c $(FOO)/jbig_ar.c

$(BUILD)/rastertopbm: src/rastertopbm.c | $(BUILD)
	$(CC) $(ARCHS) $(CFLAGS) -Wall -Wno-deprecated-declarations -o $@ $< -lcups

$(BUILD)/rastertozjs-foo2zjs: src/rastertozjs-foo2zjs | $(BUILD)
	install -m 755 $< $@

clean:
	rm -rf $(BUILD)
