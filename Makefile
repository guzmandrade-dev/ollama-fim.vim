VIM ?= vim

.PHONY: test lint dist

test:
	VIM=$(VIM) bash scripts/test.sh

lint:
	bash scripts/lint.sh

# Build local release artifacts into build/:
#   ollama-fim-<version>.vmb  (vimball)
#   ollama-fim-<version>.zip  (for the vim.org upload form)
# Version defaults to the latest git tag; override with: make dist VERSION=1.4.1
dist:
	bash scripts/dist.sh $(VERSION)
