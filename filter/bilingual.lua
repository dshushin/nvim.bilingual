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

-- DOCX: each .bilingual → table (unchanged)
local function render_docx(div)
  local cols = extract_cols(div)
  if not cols then return nil end

  local content1 = demote_headings(cols[1].content)
  local content2 = demote_headings(cols[2].content)

  local dir1 = get_attr(cols[1], "dir") or "ltr"
  local dir2 = get_attr(cols[2], "dir") or "ltr"

  if dir1 == "rtl" then
    content1 = { pandoc.Div(content1, pandoc.Attr("", {}, {{"dir", "rtl"}})) }
  end
  if dir2 == "rtl" then
    content2 = { pandoc.Div(content2, pandoc.Attr("", {}, {{"dir", "rtl"}})) }
  end

  local tbl = skeleton:clone()
  tbl.colspecs = {
    { pandoc.AlignDefault, 0.48 },
    { pandoc.AlignDefault, 0.48 },
  }
  tbl.head = pandoc.TableHead({})
  tbl.bodies[1].body = { pandoc.Row({ pandoc.Cell(content1), pandoc.Cell(content2) }) }
  tbl.bodies[1].head = {}

  return tbl
end

-- LaTeX: merge consecutive .bilingual divs into one paracol environment
-- with \switchcolumn* for synchronization between sections
function Pandoc(doc)
  if not FORMAT:match("latex") then
    -- DOCX: process individual divs
    return doc:walk({ Div = function(div)
      if is_bilingual(div) then return render_docx(div) end
    end })
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

        local left = blocks_to_latex(demote_headings(cols[1].content))
        local right = blocks_to_latex(demote_headings(cols[2].content))

        if dir1 == "rtl" then left = "\\beginR\n" .. left .. "\\endR\n" end
        if dir2 == "rtl" then right = "\\beginR\n" .. right .. "\\endR\n" end

        if j > 1 then
          -- Sync point + thin rule spanning both columns
          parts[#parts + 1] = "\\end{paracol}"
          parts[#parts + 1] = "\\noindent{\\color{rulelight}\\rule{\\linewidth}{0.4pt}}"
          parts[#parts + 1] = "\\vspace{2pt}"
          parts[#parts + 1] = "\\begin{paracol}{2}"
        end

        -- Left column
        parts[#parts + 1] = left

        -- Switch to right column (synced)
        parts[#parts + 1] = "\\switchcolumn"

        -- Right column
        parts[#parts + 1] = right

        -- Sync back to left for next section
        parts[#parts + 1] = "\\switchcolumn*"
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
