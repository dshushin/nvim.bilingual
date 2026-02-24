local M = {}

local function plugin_root()
  local info = debug.getinfo(1, "S")
  local path = info.source:match("@(.*/)")
  return vim.fn.fnamemodify(path .. "../../", ":p"):gsub("/$", "")
end

-- Available language pairs
local pairs_list = {
  { code = "en-ru", label = "English / Russian" },
  { code = "en-ar", label = "English / Arabic" },
  { code = "en-he", label = "English / Hebrew" },
}

-- RTL config per language
local rtl_langs = {
  ["en-ar"] = { dir = "rtl", lang = "ar" },
  ["en-he"] = { dir = "rtl", lang = "he" },
}

--- Export current file to PDF/DOCX
function M.export(format)
  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("[bilingual] No file open", vim.log.levels.ERROR)
    return
  end

  local root = plugin_root()
  local script = root .. "/export.sh"

  if vim.fn.filereadable(script) ~= 1 then
    vim.notify("[bilingual] export.sh not found at " .. script, vim.log.levels.ERROR)
    return
  end

  local flag = ""
  if format == "pdf" then flag = " --pdf"
  elseif format == "docx" then flag = " --docx"
  end

  local cmd = string.format("%s %s%s", vim.fn.shellescape(script), vim.fn.shellescape(file), flag)
  vim.notify("[bilingual] Exporting" .. (format and (" " .. format) or "") .. "...")

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then vim.notify("[bilingual] " .. line) end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then vim.notify("[bilingual] " .. line, vim.log.levels.WARN) end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("[bilingual] Export complete")
      else
        vim.notify("[bilingual] Export failed (exit " .. code .. ")", vim.log.levels.ERROR)
      end
    end,
  })
end

--- Create new document from template
function M.new(pair)
  local function load_template(code)
    local root = plugin_root()
    local path = root .. "/templates/contracts/" .. code .. ".md"
    if vim.fn.filereadable(path) ~= 1 then
      vim.notify("[bilingual] Template not found: " .. path, vim.log.levels.ERROR)
      return
    end
    local lines = vim.fn.readfile(path)
    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.filetype = "markdown"
    vim.notify("[bilingual] New " .. code .. " contract")
  end

  if pair then
    load_template(pair)
  else
    vim.ui.select(pairs_list, {
      prompt = "Language pair:",
      format_item = function(item) return item.label end,
    }, function(choice)
      if choice then load_template(choice.code) end
    end)
  end
end

--- Insert empty bilingual section at cursor
function M.section()
  local col2_attr = ""

  -- Detect RTL from current buffer content
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, 30, false)
  local text = table.concat(buf_lines, "\n")
  if text:match("dir=rtl%s+lang=ar") then
    col2_attr = " dir=rtl lang=ar"
  elseif text:match("dir=rtl%s+lang=he") then
    col2_attr = " dir=rtl lang=he"
  end

  local snippet = {
    "::: {.bilingual}",
    "::: {.col}",
    "",
    ":::",
    "::: {.col" .. col2_attr .. "}",
    "",
    ":::",
    ":::",
  }

  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row, row, false, snippet)
  -- Place cursor on the empty line in the first column
  vim.api.nvim_win_set_cursor(0, { row + 3, 0 })
end

--- Command router
function M.command(args)
  local parts = vim.split(args, "%s+", { trimempty = true })
  local cmd = parts[1]

  if cmd == "new" then
    M.new(parts[2])
  elseif cmd == "section" then
    M.section()
  elseif cmd == "pdf" or cmd == "docx" then
    M.export(cmd)
  elseif not cmd or cmd == "" then
    M.export(nil)
  else
    vim.notify("[bilingual] Unknown: " .. cmd .. ". Use: new, section, pdf, docx", vim.log.levels.ERROR)
  end
end

--- Setup keymaps
function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown", "mdx" },
    callback = function(ev)
      vim.keymap.set("n", "<leader>bs", M.section, {
        buffer = ev.buf,
        desc = "Insert bilingual section",
      })
    end,
  })
end

return M
