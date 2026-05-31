.PHONY: quality test check deps

MINI_NVIM := deps/mini.nvim

quality:
	luacheck lua/ plugin/
	stylua --check .
	lua-language-server --check lua/ --configpath $(CURDIR)/.luarc.json --checklevel=Error

# Clone the test-only mini.nvim dependency on first run.
deps: $(MINI_NVIM)

$(MINI_NVIM):
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $(MINI_NVIM)

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua MiniTest.run()"

check: quality test
