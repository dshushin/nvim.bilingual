-- bilingual.lua — pandoc Lua filter
-- Converts ::: {.bilingual} with two ::: {.col} children into parallel columns.
-- LaTeX: paracol with synced columns. DOCX: two-column tables.
-- Supports dir=rtl on .col divs for Arabic/Hebrew.

-- Skeleton table for DOCX (pandoc 3.x has no TableBody constructor)
local skeleton = pandoc.read("| a | b |\n|---|---|\n| x | y |", "markdown").blocks[1]

local function is_bilingual(div)
  return div.t == "Div" and div.classes and div.classes:includes("bilingual")
end

local function is_col(div)
  return div.classes and div.classes:includes("col")
end

local function get_attr(div, key)
  if div.attributes then
    return div.attributes[key]
  end
  return nil
end

-- Convert headings to bold paragraphs (headings inside paracol cause issues)
local function demote_headings(blocks)
  local out = pandoc.List()
  for _, block in ipairs(blocks) do
    if block.t == "Header" then
      out:insert(pandoc.Para({ pandoc.Strong(block.content) }))
    else
      out:insert(block)
    end
  end
  return out
end

-- Render blocks to LaTeX string via pandoc
local function blocks_to_latex(blocks)
  return pandoc.write(pandoc.Pandoc(blocks), "latex")
end

-- Fix smart quotes for LaTeX RTL: replace backtick ligatures (``..'' )
-- with straight quotes that render correctly in Arabic/Hebrew fonts
local function fix_rtl_quotes(blocks)
  local result = pandoc.List()
  for _, block in ipairs(blocks) do
    result:insert(pandoc.walk_block(block, {
      Quoted = function(el)
        local q = el.quotetype == "DoubleQuote" and '"' or "'"
        local inlines = pandoc.List({pandoc.Str(q)})
        inlines:extend(el.content)
        inlines:insert(pandoc.Str(q))
        return inlines
      end
    }))
  end
  return result
end

-- Extract two .col divs from a .bilingual div
local function extract_cols(div)
  local cols = {}
  for _, block in ipairs(div.content) do
    if block.t == "Div" and is_col(block) then
      cols[#cols + 1] = block
    end
  end
  if #cols == 2 then return cols end
  return nil
end

-- Wrap a block in an RTL Div for DOCX (sets paragraph-level bidi + preserves style)
local function make_rtl_block(block, style)
  return pandoc.Div({block}, pandoc.Attr("", {}, {
    {"dir", "rtl"},
    {"custom-style", style or "Body Text"},
  }))
end

-- DOCX: each .bilingual → table with one row per paragraph pair
local function render_docx(div)
  local cols = extract_cols(div)
  if not cols then return nil end

  local dir1 = get_attr(cols[1], "dir") or "ltr"
  local dir2 = get_attr(cols[2], "dir") or "ltr"

  local left_blocks = demote_headings(cols[1].content)
  local right_blocks = demote_headings(cols[2].content)
  -- DOCX: no character mirroring needed — Word handles bidi correctly

  local max_n = math.max(#left_blocks, #right_blocks)
  local rows = {}

  for k = 1, max_n do
    local lb = left_blocks[k] and { left_blocks[k] } or {}
    local rb = right_blocks[k] and { right_blocks[k] } or {}

    local style = (k == 1) and "First Paragraph" or "Body Text"
    if dir1 == "rtl" and #lb > 0 then
      lb = { make_rtl_block(lb[1], style) }
    end
    if dir2 == "rtl" and #rb > 0 then
      rb = { make_rtl_block(rb[1], style) }
    end

    rows[#rows + 1] = pandoc.Row({ pandoc.Cell(lb), pandoc.Cell(rb) })
  end

  local tbl = skeleton:clone()
  tbl.colspecs = {
    { pandoc.AlignDefault, 0.48 },
    { pandoc.AlignDefault, 0.48 },
  }
  tbl.head = pandoc.TableHead({})
  tbl.bodies[1].body = rows
  tbl.bodies[1].head = {}

  return tbl
end

-- Wrap LaTeX content in a language-specific RTL environment (babel)
local function wrap_rtl_latex(tex, lang)
  if lang == "ar" then
    return "\\begin{otherlanguage}{arabic}\n" .. tex .. "\\end{otherlanguage}\n"
  elseif lang == "he" then
    return "\\begin{otherlanguage}{hebrew}\n" .. tex .. "\\end{otherlanguage}\n"
  else
    return "\\begin{otherlanguage}{arabic}\n" .. tex .. "\\end{otherlanguage}\n"
  end
end

-- Check if a string contains RTL characters (Arabic or Hebrew Unicode ranges)
local function has_rtl(str)
  for _, c in utf8.codes(str) do
    if (c >= 0x0600 and c <= 0x06FF) or (c >= 0x0590 and c <= 0x05FF) then
      return true
    end
  end
  return false
end

-- LaTeX: merge consecutive .bilingual divs into one paracol environment
-- with \switchcolumn* for synchronization between sections
function Pandoc(doc)
  -- LaTeX: wrap RTL title lines in babel's \foreignlanguage for correct direction
  if FORMAT:match("latex") and doc.meta.title and type(doc.meta.title) == "table"
      and #doc.meta.title > 0 and not doc.meta.title.t then
    for i, item in ipairs(doc.meta.title) do
      if has_rtl(pandoc.utils.stringify(item)) then
        local inlines = pandoc.Inlines(item)
        inlines:insert(1, pandoc.RawInline("latex", "\\foreignlanguage{arabic}{"))
        inlines:insert(pandoc.RawInline("latex", "}"))
        doc.meta.title[i] = pandoc.MetaInlines(inlines)
      end
    end
  end

  if not FORMAT:match("latex") then
    -- DOCX: combine list title into single title with line breaks
    local meta = doc.meta
    if meta.title and type(meta.title) == "table" and #meta.title > 0 and not meta.title.t then
      local combined = pandoc.Inlines({})
      for i, item in ipairs(meta.title) do
        if i > 1 then combined:insert(pandoc.LineBreak()) end
        combined:extend(pandoc.Inlines(item))
      end
      meta.title = pandoc.MetaInlines(combined)
    end

    -- DOCX: process .bilingual divs into tables
    local blocks = pandoc.List()
    for _, block in ipairs(doc.blocks) do
      if is_bilingual(block) then
        local tbl = render_docx(block)
        blocks:insert(tbl or block)
      else
        blocks:insert(block)
      end
    end
    return pandoc.Pandoc(blocks, meta)
  end

  -- LaTeX: group consecutive .bilingual blocks
  local result = pandoc.List()
  local i = 1

  while i <= #doc.blocks do
    local block = doc.blocks[i]

    if is_bilingual(block) then
      -- Collect consecutive .bilingual divs
      local group = {}
      while i <= #doc.blocks and is_bilingual(doc.blocks[i]) do
        local cols = extract_cols(doc.blocks[i])
        if cols then group[#group + 1] = cols end
        i = i + 1
      end

      -- Build one paracol environment for the entire group
      local parts = {}
      parts[#parts + 1] = "\\begin{paracol}{2}"

      for j, cols in ipairs(group) do
        local dir1 = get_attr(cols[1], "dir") or "ltr"
        local dir2 = get_attr(cols[2], "dir") or "ltr"

        local left_blocks = demote_headings(cols[1].content)
        local right_blocks = demote_headings(cols[2].content)
        if dir1 == "rtl" then left_blocks = fix_rtl_quotes(left_blocks) end
        if dir2 == "rtl" then right_blocks = fix_rtl_quotes(right_blocks) end
        local max_n = math.max(#left_blocks, #right_blocks)

        if j > 1 then
          -- Sync point + thin rule spanning both columns
          parts[#parts + 1] = "\\end{paracol}"
          parts[#parts + 1] = "\\noindent{\\color{rulelight}\\rule{\\linewidth}{0.4pt}}"
          parts[#parts + 1] = "\\vspace{2pt}"
          parts[#parts + 1] = "\\begin{paracol}{2}"
        end

        -- Interleave paragraphs with sync points
        for k = 1, max_n do
          if k > 1 then
            parts[#parts + 1] = "\\switchcolumn*"
          end

          local left_tex = left_blocks[k] and blocks_to_latex({left_blocks[k]}) or ""
          local right_tex = right_blocks[k] and blocks_to_latex({right_blocks[k]}) or ""

          if dir1 == "rtl" and left_tex ~= "" then
            local lang1 = get_attr(cols[1], "lang") or ""
            left_tex = wrap_rtl_latex(left_tex, lang1)
          end
          if dir2 == "rtl" and right_tex ~= "" then
            local lang2 = get_attr(cols[2], "lang") or ""
            right_tex = wrap_rtl_latex(right_tex, lang2)
          end

          parts[#parts + 1] = left_tex
          parts[#parts + 1] = "\\switchcolumn"
          parts[#parts + 1] = right_tex
        end
      end

      parts[#parts + 1] = "\\end{paracol}"
      parts[#parts + 1] = "\\vspace{4pt}"

      result:insert(pandoc.RawBlock("latex", table.concat(parts, "\n")))
    else
      result:insert(block)
      i = i + 1
    end
  end

  return pandoc.Pandoc(result, doc.meta)
end
