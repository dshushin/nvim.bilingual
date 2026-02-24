if vim.g.loaded_bilingual then return end
vim.g.loaded_bilingual = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("[bilingual] requires Neovim >= 0.10", vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("Bilingual", function(opts)
  require("bilingual").command(opts.args)
end, {
  nargs = "*",
  complete = function(_, line)
    local parts = vim.split(line, "%s+", { trimempty = true })
    if #parts <= 2 then
      return { "new", "section", "pdf", "docx" }
    end
    if parts[2] == "new" then
      return { "en-ru", "en-ar", "en-he" }
    end
    return {}
  end,
  desc = "Bilingual documents: new, section, pdf, docx",
})

-- Setup keymaps for markdown files
require("bilingual").setup()
