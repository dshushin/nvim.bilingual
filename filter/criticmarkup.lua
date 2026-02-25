-- criticmarkup.lua — pandoc Lua filter for CriticMarkup (Track Changes)
--
-- Syntax:
--   {++addition++}       — inserted text
--   {--deletion--}       — deleted text
--   {~~old~>new~~}       — substitution
--   {>>comment<<}        — comment
--   {==highlight==}      — highlight
--
-- Modes (set via -M critic-mode=...):
--   redline (default) — show additions/deletions with styling
--   accept            — accept all changes (final text only)
--
-- Requires: -f markdown-strikeout-subscript (to prevent pandoc from
-- consuming ~~ and ~ as strikethrough/subscript syntax)

local CRITIC_MODE = "redline"

-- Openers: patterns searched in "normal" state
-- Note: {--...--} has an en-dash variant because pandoc's smart extension
-- converts -- to – (U+2013) during parsing.
local OPENERS = {
  { "{%+%+",    "add" },
  { "{%-%-",    "del" },
  { "{–",       "del" },       -- en-dash variant (smart extension)
  { "{~~",      "sub_old" },
  { "{>>",      "comment" },
  { "{==",      "highlight" },
}

-- Closers per state (multiple patterns to handle smart extension)
local CLOSERS = {
  add       = { "%+%+}" },
  del       = { "%-%-}", "–}" },
  sub_old   = { "~>" },         -- separator, not real close
  sub_new   = { "~~}" },
  comment   = { "<<}" },
  highlight = { "==}" },
}

-- Find earliest opening delimiter in text
local function find_open(text)
  local best = nil
  for _, op in ipairs(OPENERS) do
    local s, e = text:find(op[1])
    if s and (not best or s < best.pos) then
      best = { pos = s, endpos = e, state = op[2] }
    end
  end
  return best
end

-- Find closing delimiter for current state
local function find_close(text, state)
  local patterns = CLOSERS[state]
  if not patterns then return nil end
  local best = nil
  for _, p in ipairs(patterns) do
    local s, e = text:find(p)
    if s and (not best or s < best.pos) then
      best = { pos = s, endpos = e }
    end
  end
  return best
end

------------------------------------------------------------------------
-- Styling functions
------------------------------------------------------------------------

local function style_add(inlines)
  if CRITIC_MODE == "accept" then return inlines end
  if FORMAT:match("latex") then
    local r = pandoc.List()
    r:insert(pandoc.RawInline("latex", "\\criticadd{"))
    r:extend(inlines)
    r:insert(pandoc.RawInline("latex", "}"))
    return r
  else
    return pandoc.List({ pandoc.Underline(inlines) })
  end
end

local function style_del(inlines)
  if CRITIC_MODE == "accept" then return pandoc.List() end
  if FORMAT:match("latex") then
    local r = pandoc.List()
    r:insert(pandoc.RawInline("latex", "\\criticdel{"))
    r:extend(inlines)
    r:insert(pandoc.RawInline("latex", "}"))
    return r
  else
    return pandoc.List({ pandoc.Strikeout(inlines) })
  end
end

local function style_comment(inlines)
  if CRITIC_MODE == "accept" then return pandoc.List() end
  if FORMAT:match("latex") then
    local r = pandoc.List()
    r:insert(pandoc.RawInline("latex", "\\criticcomment{"))
    r:extend(inlines)
    r:insert(pandoc.RawInline("latex", "}"))
    return r
  else
    local r = pandoc.List()
    r:insert(pandoc.Str("["))
    r:extend(inlines)
    r:insert(pandoc.Str("]"))
    return r
  end
end

local function style_highlight(inlines)
  if CRITIC_MODE == "accept" then return inlines end
  if FORMAT:match("latex") then
    local r = pandoc.List()
    r:insert(pandoc.RawInline("latex", "\\critichighlight{"))
    r:extend(inlines)
    r:insert(pandoc.RawInline("latex", "}"))
    return r
  else
    return inlines
  end
end

local function apply_style(state, collected, collected_old)
  if state == "add" then
    return style_add(collected)
  elseif state == "del" then
    return style_del(collected)
  elseif state == "sub_new" then
    local r = pandoc.List()
    r:extend(style_del(collected_old))
    r:extend(style_add(collected))
    return r
  elseif state == "comment" then
    return style_comment(collected)
  elseif state == "highlight" then
    return style_highlight(collected)
  end
  return collected
end

------------------------------------------------------------------------
-- Inlines walker: find CriticMarkup delimiters in Str elements
------------------------------------------------------------------------

local function process_inlines(inlines)
  -- Quick check: skip if no CriticMarkup present
  local raw = pandoc.utils.stringify(inlines)
  if not (raw:find("{++", 1, true) or raw:find("{--", 1, true) or
          raw:find("{–",  1, true) or raw:find("{~~", 1, true) or
          raw:find("{>>", 1, true) or raw:find("{==", 1, true)) then
    return nil
  end

  local result = pandoc.List()
  local state = "normal"
  local collected = pandoc.List()
  local collected_old = pandoc.List()

  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      local text = el.text
      while #text > 0 do
        if state == "normal" then
          local op = find_open(text)
          if not op then
            result:insert(pandoc.Str(text))
            text = ""
          else
            if op.pos > 1 then
              result:insert(pandoc.Str(text:sub(1, op.pos - 1)))
            end
            state = op.state
            collected = pandoc.List()
            collected_old = pandoc.List()
            text = text:sub(op.endpos + 1)
          end
        else
          local cl = find_close(text, state)
          if not cl then
            collected:insert(pandoc.Str(text))
            text = ""
          else
            if cl.pos > 1 then
              collected:insert(pandoc.Str(text:sub(1, cl.pos - 1)))
            end
            text = text:sub(cl.endpos + 1)

            if state == "sub_old" then
              -- ~> separator: save old, continue collecting new
              collected_old = collected
              collected = pandoc.List()
              state = "sub_new"
            else
              -- Closing delimiter: apply styling
              result:extend(apply_style(state, collected, collected_old))
              state = "normal"
              collected = pandoc.List()
            end
          end
        end
      end
    else
      -- Non-Str element (Space, Strong, Emph, etc.)
      if state == "normal" then
        result:insert(el)
      else
        collected:insert(el)
      end
    end
  end

  -- Unclosed CriticMarkup: dump as-is
  if state ~= "normal" then
    local openers = {
      add = "{++", del = "{--", sub_old = "{~~",
      sub_new = "~>", comment = "{>>", highlight = "{==",
    }
    result:insert(pandoc.Str(openers[state] or ""))
    if state == "sub_new" then
      result:extend(collected_old)
      result:insert(pandoc.Str("~>"))
    end
    result:extend(collected)
  end

  return result
end

------------------------------------------------------------------------
-- Filter pipeline: Meta first (to read mode), then Inlines
------------------------------------------------------------------------

return {
  {
    Meta = function(meta)
      if meta["critic-mode"] then
        CRITIC_MODE = pandoc.utils.stringify(meta["critic-mode"])
      end
    end,
  },
  {
    Inlines = process_inlines,
  },
}
