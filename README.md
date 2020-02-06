
No documents. Sorry.


dependencies
  - [wtrans](https://github.com/thinca/wtrans)

```vim
nnoremap <silent> gr :<C-u>call translate_it#cword_or_close()<CR>
xnoremap <silent> gr :<C-u>call translate_it#visual()<CR>
" nnoremap <expr><silent> <ESC> translate_it#is_closable() ? ':<C-u>call translate_it#finish()<CR>' : '<ESC>'
```

![image](https://user-images.githubusercontent.com/29811106/73963768-414f0680-4954-11ea-9931-ec54f83fcd69.png)
