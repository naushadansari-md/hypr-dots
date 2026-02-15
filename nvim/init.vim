" ===============================
" BASIC SETTINGS
" ===============================

set nocompatible
set number
set showmatch
set ignorecase
set smartcase
set hlsearch
set incsearch

set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set autoindent

set mouse=a
set clipboard=unnamedplus
set wildmode=longest,list
set ttyfast

" ===============================
" SYNTAX & FILETYPE
" ===============================

syntax enable
filetype plugin indent on

" Enable true color support
if has("termguicolors")
    set termguicolors
endif

" ===============================
" TRANSPARENT BACKGROUND
" ===============================

hi Normal guibg=NONE ctermbg=NONE
hi NormalNC guibg=NONE ctermbg=NONE
hi NonText guibg=NONE ctermbg=NONE
hi SignColumn guibg=NONE ctermbg=NONE
hi Pmenu guibg=NONE ctermbg=NONE
hi NormalFloat guibg=NONE ctermbg=NONE
hi FloatBorder guibg=NONE ctermbg=NONE
hi TabLine guibg=NONE ctermbg=NONE
