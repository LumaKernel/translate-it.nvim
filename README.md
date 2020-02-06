
No documents. Sorry.

```vim
let g:translate_it_opts = []
let s:proxy = ''

if s:proxy !=# ''
  let g:translate_it_opts += ['-x', s:proxy]
endif

nnoremap <silent> <Leader>r :<C-u>call translate_it#cword(0, 'en', g:translate_it_opts)<CR>
xnoremap <silent> <Leader>r :<C-u>call translate_it#visual(0, 'en', g:translate_it_opts)<CR>
nnoremap <silent> <Leader>R :<C-u>call translate_it#cword(0, 'ja', g:translate_it_opts)<CR>
xnoremap <silent> <Leader>R :<C-u>call translate_it#visual(0, 'ja', g:translate_it_opts)<CR>
nnoremap <silent> <Leader>T :<C-u>call translate_it#finish()<CR>
```

