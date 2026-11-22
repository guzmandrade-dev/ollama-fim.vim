VIM ?= vim

.PHONY: test lint

test:
	VIM=$(VIM) bash scripts/test.sh

lint:
	bash scripts/lint.sh
