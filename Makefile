build: build/math3d.min.js build/math3d.js

clean:
	rm -rf build

.PHONY: build clean
.DEFAULT_GOAL := build

COFFEESCRIPT_SRC = $(wildcard src/*.coffee)
JAVASCRIPT_SRC = $(wildcard src/*.js)

build/math3d.js: $(COFFEESCRIPT_SRC) $(JAVASCRIPT_SRC)
	@mkdir -p $(@D)
	echo '(function() {' > $@
	cat $(JAVASCRIPT_SRC) >> $@
	cat $(COFFEESCRIPT_SRC) | coffee --compile --bare --stdio >> $@
	echo '}).call(this);' >> $@

build/math3d.min.js: build/math3d.js
	@mkdir -p $(@D)
	uglifyjs $< --mangle --output $@
