.PHONY: quality

quality:
	luacheck lua/ plugin/
	stylua --check .
	lua-language-server --check lua/ --configpath $(CURDIR)/.luarc.json --checklevel=Error
