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

-- DOCX: each .bilingual → table with one row per paragraph pair
local function render_docx(div)
  local cols = extract_cols(div)
  if not cols then return nil end

  local left_blocks = demote_headings(cols[1].content)
  local right_blocks = demote_headings(cols[2].content)

  local dir1 = get_attr(cols[1], "dir") or "ltr"
  local dir2 = get_attr(cols[2], "dir") or "ltr"

  local max_n = math.max(#left_blocks, #right_blocks)
  local rows = {}

  for k = 1, max_n do
    local lb = left_blocks[k] and { left_blocks[k] } or {}
    local rb = right_blocks[k] and { right_blocks[k] } or {}

    if dir1 == "rtl" and #lb > 0 then
      lb = { pandoc.Div(lb, pandoc.Attr("", {}, {{"dir", "rtl"}})) }
    end
    if dir2 == "rtl" and #rb > 0 then
      rb = { pandoc.Div(rb, pandoc.Attr("", {}, {{"dir", "rtl"}})) }
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

-- LaTeX: merge consecutive .bilingual divs into one paracol environment
-- with \switchcolumn* for synchronization between sections
function Pandoc(doc)
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
            left_tex = "\\beginR\n" .. left_tex .. "\\endR\n"
          end
          if dir2 == "rtl" and right_tex ~= "" then
            right_tex = "\\beginR\n" .. right_tex .. "\\endR\n"
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
