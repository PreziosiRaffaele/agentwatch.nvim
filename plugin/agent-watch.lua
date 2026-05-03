if vim.g.loaded_agent_watch == 1 then
    return
end

vim.g.loaded_agent_watch = 1

require('agent-watch').setup()
