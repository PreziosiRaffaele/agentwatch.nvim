.PHONY: quality

quality:
	luacheck lua/ plugin/
	stylua --check .
