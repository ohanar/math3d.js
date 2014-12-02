build: build/math3d.min.js build/math3dnofont.min.js

clean:
	rm -rf build

.PHONY: build clean
.DEFAULT_GOAL := build

FONT_SRC = src/helvetiker_regular.js
COFFEESCRIPT_SRC = $(wildcard src/*.coffee)
JAVASCRIPT_SRC = $(filter-out $(FONT_SRC), $(wildcard src/*.js))

build/math3d.js: $(COFFEESCRIPT_SRC) $(JAVASCRIPT_SRC) $(FONT_SRC)
	@mkdir -p $(@D)
	echo '(function() {' > $@
	cat $(JAVASCRIPT_SRC) $(FONT_SRC) >> $@
	cat $(COFFEESCRIPT_SRC) | coffee --compile --bare --stdio >> $@
	echo '}).call(this);' >> $@

build/math3dnofont.js: $(COFFEESCRIPT_SRC) $(JAVASCRIPT_SRC)
	@mkdir -p $(@D)
	echo '(function() {' > $@
	cat $(JAVASCRIPT_SRC) >> $@
	cat $(COFFEESCRIPT_SRC) | coffee --compile --bare --stdio >> $@
	echo '}).call(this);' >> $@

build/math3d.min.js: build/math3d.js
	@mkdir -p $(@D)
	uglifyjs $< --mangle --output $@

build/math3dnofont.min.js: build/math3dnofont.js
	@mkdir -p $(@D)
	uglifyjs $< --mangle --output $@
