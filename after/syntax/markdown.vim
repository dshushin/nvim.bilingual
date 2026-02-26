" bilingual.nvim — fenced-div syntax highlighting + conceal
" Colors visible at conceallevel=0 (default)
" Conceal chars visible at conceallevel=1 (:set conceallevel=1)

syntax match bilingualBlockOpen  /^::: {\.bilingual}$/ conceal cchar=║
syntax match bilingualColLtr     /^::: {\.col}$/       conceal cchar=│
syntax match bilingualColRtl     /^::: {\.col [^}]\+}$/ conceal cchar=│
syntax match bilingualBlockClose /^:::$/                conceal cchar=·

highlight default bilingualBlockOpen  guifg=#B8860B ctermfg=136 gui=bold cterm=bold
highlight default bilingualColLtr     guifg=#6A9955 ctermfg=65
highlight default bilingualColRtl     guifg=#6A9955 ctermfg=65 gui=italic cterm=italic
highlight default bilingualBlockClose guifg=#555555 ctermfg=240
