# nvim.bilingual

Neovim plugin + pandoc tool for writing bilingual legal documents in markdown with parallel two-column export to PDF and Word.

Built for legal contracts where text in two languages must appear side by side with synchronized sections.

## Features

- **Parallel columns** — two languages side by side, sections aligned
- **Page-break support** — columns flow naturally across pages (no gaps)
- **RTL support** — Arabic, Hebrew with automatic font switching
- **Contract templates** — ready-made skeletons for EN-RU, EN-AR, EN-HE
- **Quick section insert** — keymap to add bilingual blocks without typing tags
- **Export from nvim** — `:Bilingual pdf` / `:Bilingual docx`
- **Professional PDF** — XeLaTeX with PT Serif, paracol, proper typography
- **Word export** — clean DOCX with two-column tables

## Requirements

- Neovim >= 0.10
- [pandoc](https://pandoc.org/) >= 3.0 — `brew install pandoc`
- XeLaTeX (for PDF) — `brew install --cask mactex` or `brew install basictex`

Fonts (bundled on macOS):
- PT Serif, Helvetica Neue, Menlo
- Al Nile (Arabic), Arial Hebrew (Hebrew)

## Installation

### vim-plug

```vim
Plug '/path/to/nvim.bilingual'
```

### lazy.nvim

```lua
{ dir = "/path/to/nvim.bilingual" }
```

No `setup()` call needed — the plugin loads automatically.

## Quick Start

### 1. Create a new contract

```vim
:Bilingual new
```

A menu appears with language pairs:

```
Language pair:
> English / Russian
  English / Arabic
  English / Hebrew
```

Select one — a new buffer opens with a full contract template (~10 articles).

Or specify the pair directly:

```vim
:Bilingual new en-ru
:Bilingual new en-ar
:Bilingual new en-he
```

### 2. Add sections

Press `<leader>bs` in a markdown file to insert an empty bilingual section at the cursor:

```markdown
::: {.bilingual}
::: {.col}

:::
::: {.col}

:::
:::
```

If the file already contains RTL content (Arabic/Hebrew), the second column automatically gets `dir=rtl lang=ar/he`.

### 3. Export

```vim
:Bilingual pdf        " export to PDF
:Bilingual docx       " export to Word
:Bilingual            " export both
```

Output goes to `~/Documents/bilingual-exports/`.

Or from the command line:

```bash
./export.sh document.md           # PDF + DOCX
./export.sh document.md --pdf     # PDF only
./export.sh document.md --docx    # DOCX only
```

## Markdown Syntax

Wrap bilingual sections in `::: {.bilingual}` with two `::: {.col}` children:

```markdown
---
title: "Sale and Purchase Agreement / Договор купли-продажи"
date: "2026"
---

::: {.bilingual}
::: {.col}
### Article 1. Definitions

"Agreement" means this Sale and Purchase Agreement.
:::
::: {.col}
### Статья 1. Определения

«Договор» означает настоящий Договор купли-продажи.
:::
:::
```

Text outside `.bilingual` blocks spans the full page width — useful for signatures, document headers, and notes.

### RTL languages

Add `dir=rtl` and `lang=` to the `.col` div:

```markdown
::: {.bilingual}
::: {.col}
### Article 1. Definitions
:::
::: {.col dir=rtl lang=ar}
### المادة 1. التعريفات
:::
:::
```

| Attribute | Effect |
|-----------|--------|
| `dir=rtl` | Right-to-left text direction |
| `lang=ar` | Arabic font (Al Nile) |
| `lang=he` | Hebrew font (Arial Hebrew) |

Font switching is automatic — when LaTeX encounters Arabic or Hebrew characters, it switches to the appropriate font via the `ucharclasses` package. This means Arabic text in document titles also renders correctly.

## Commands

| Command | Description |
|---------|-------------|
| `:Bilingual new` | Create contract from template (interactive menu) |
| `:Bilingual new en-ru` | Create EN-RU contract directly |
| `:Bilingual new en-ar` | Create EN-AR contract (Arabic RTL) |
| `:Bilingual new en-he` | Create EN-HE contract (Hebrew RTL) |
| `:Bilingual section` | Insert empty bilingual section at cursor |
| `:Bilingual pdf` | Export current file to PDF |
| `:Bilingual docx` | Export current file to DOCX |
| `:Bilingual` | Export to both PDF and DOCX |

All commands have tab-completion.

## Keymaps

| Key | Mode | Action |
|-----|------|--------|
| `<leader>bs` | Normal | Insert bilingual section at cursor |

Active only in markdown/mdx files.

## Contract Templates

Three templates are included, each with ~10 articles:

| Template | Languages | Jurisdiction |
|----------|-----------|--------------|
| `en-ru` | English + Russian | configurable |
| `en-ar` | English + Arabic (RTL) | UAE |
| `en-he` | English + Hebrew (RTL) | Israel |

Each template includes: definitions, subject, price and payment, term and termination, representations and warranties, liability, confidentiality, force majeure, governing law, general provisions, and signature blocks.

All placeholder values are marked with `[___]` for easy find-and-replace.

## How It Works

### PDF (LaTeX)

1. Pandoc reads markdown and applies the Lua filter (`filter/bilingual.lua`)
2. The filter collects consecutive `.bilingual` blocks into `paracol` environments
3. Each section pair uses `\switchcolumn*` for vertical synchronization
4. `ucharclasses` package auto-switches fonts for Arabic/Hebrew characters
5. `paracol` handles page breaks within parallel columns — no empty gaps
6. XeLaTeX renders the final PDF

### DOCX (Word)

1. Same Lua filter, but generates two-column tables instead of paracol
2. RTL content is wrapped in `Div` elements with `dir="rtl"` attribute
3. Pandoc converts to DOCX with proper table formatting

## Examples

| File | Languages |
|------|-----------|
| `example/contract.md` | English + Russian |
| `example/contract-ar.md` | English + Arabic (RTL) |
| `example/contract-he.md` | English + Hebrew (RTL) |

```bash
./export.sh example/contract.md
./export.sh example/contract-ar.md
./export.sh example/contract-he.md
```

## Project Structure

```
nvim.bilingual/
├── plugin/bilingual.lua             -- bootstrap, commands
├── lua/bilingual/
│   └── init.lua                     -- new, section, export, keymaps
├── filter/
│   └── bilingual.lua                -- pandoc Lua filter (paracol + tables)
├── templates/
│   ├── bilingual.latex              -- LaTeX template (fonts, paracol, ucharclasses)
│   └── contracts/
│       ├── en-ru.md                 -- English / Russian template
│       ├── en-ar.md                 -- English / Arabic template
│       └── en-he.md                 -- English / Hebrew template
├── example/
│   ├── contract.md                  -- EN-RU example
│   ├── contract-ar.md               -- EN-AR example (RTL)
│   └── contract-he.md               -- EN-HE example (RTL)
├── export.sh                        -- CLI export script
└── README.md
```
