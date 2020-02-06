
let s:Promise = vital#translate_it#import('Async.Promise')
let s:J = vital#translate_it#import('JobShims.Vim')
let s:ANSI = vital#translate_it#import('Vim.Buffer.ANSI')

function! s:wait(ms)
  return s:Promise.new({resolve -> timer_start(a:ms, {->resolve()})})
endfunction
function! s:next_tick()
  return s:Promise.new({resolve -> timer_start(0, {->resolve()})})
endfunction

let s:buf = nvim_create_buf(v:false, v:true)

let s:line_breaks = ['\.', '．', '?', '!', '。', '？', '！']

let s:basic_opts = ['--interactive']
let s:queue = 0


function! s:option(strs, height) abort
  let maxlen = max(map(copy(a:strs), 'strlen(v:val)'))
  let width = max([min([maxlen, 100, float2nr(&columns * 0.9)]), 1])
  return {
      \   'relative': 'cursor',
      \   'width': width,
      \   'height': max([a:height, 1]),
      \   'col': -width/2,
      \   'row': 1,
      \   'anchor': 'NW',
      \   'style': 'minimal',
      \ }
endfunction

function! s:run_if_not_run() abort
  if exists('s:job') && s:J.job_status(s:job) ==# 'run'
    return
  endif
  if exists('s:job')
    call s:J.job_stop(s:job)
  endif

  let cmd = s:get_executable()
  if cmd is 0
    echoerr '[translate-it] Executable was not found.'
    echoerr '[translate-it] Check the variable g:translate_it#translate_shell.'
    return
  endif

  let s:queue = 0

  let opt = {}
  function! opt.out_cb(data) abort closure
    let s:queue -= 1
    if s:queue
      return
    endif
    if !g:started
      let g:started = 1
      let g:cache_str = ''
    endif
    let g:cache_str ..= a:data
    let g:cache_str_split = s:splitlines(g:cache_str)
    call s:update()
  endfunction

  let s:job = s:J.job_start([cmd] + s:basic_opts, opt)
endfunction

let s:last_id = 0
function! s:trans(str) abort
  let g:started = 0
  let g:cache_str_split = '...'
  call s:run_if_not_run()

  let s:queue += 1
  call s:J.ch_sendraw(s:job, substitute(a:str, '[\n\r]', '', 'g') .. "\n")

  call s:update()
endfunction

function! s:splitlines(str) abort
  let str = a:str

  let old_str = ''
  while str !=# old_str
    let old_str = str
    for lbreak in s:line_breaks
      let str = substitute(str, '\(^\|\n\)\(.\{-50,\}\)' .. lbreak .. '\(\n\|$\)\@!', "&\n", 'g')
    endfor
  endwhile

  return str
endfunction

let s:def_opts = []

function! s:get_executable()
  if exists('g:translate_it#executable') && executable(g:translate_it#executable)
    return g:translate_it#executable
  endif
  if executable('wtrans') | return 'wtrans' | endif
  return 0
endfunction

function! translate_it#close() abort
  if !translate_it#is_closable()
    return
  endif
  sil! call nvim_win_close(g:translate_it_winid, v:true)
  unlet g:translate_it_winid
endfunction

function! translate_it#finish() abort
  call translate_it#close()
endfunction

" Ensure the existence of window,
" resize window adjust to g:cache_str
" and update the buffer
function! s:update(...) abort
  if exists('g:translate_it_winid') && !nvim_win_is_valid(g:translate_it_winid)
    unlet g:translate_it_winid
    call s:update()
    return
  endif

  let strs = split(g:cache_str_split, "\n")
  call nvim_buf_set_lines(s:buf, 0, -1, v:true, strs + ["\n"])
  let old_winid = win_getid()
  call translate_it#event_off()

  if exists('g:translate_it_winid')
    let opts = s:option(strs, 1)
    call nvim_win_set_config(g:translate_it_winid, opts)
    call win_gotoid(g:translate_it_winid)
  else
    let opts = s:option(strs, 1)
    let g:translate_it_winid = nvim_open_win(s:buf, 1, opts)
  endif

  setlocal wrap
  setlocal buftype=nofile
  let opts.height = max([s:count_apparent_lines(), 1])
  let g:translate_it_winheight = opts.height

  call win_gotoid(old_winid)

  call nvim_win_set_config(g:translate_it_winid, opts)
  call nvim_buf_set_lines(s:buf, 0, -1, v:true, strs)

  call win_gotoid(g:translate_it_winid)
  call s:ANSI.define_syntax()
  call win_gotoid(old_winid)

  call translate_it#event_on()
endfunction

" Make window trace to cursor
function! s:trace(...) abort
  if !exists('g:translate_it_winid') || win_getid() == g:translate_it_winid | return | endif
  if !nvim_win_is_valid(g:translate_it_winid)
    unlet g:translate_it_winid
    call s:update()
    return
  endif
  let strs = split(g:cache_str_split, "\n")
  call nvim_buf_set_lines(s:buf, 0, -1, v:true, strs)
  let opts = s:option(strs, g:translate_it_winheight)
  call nvim_win_set_config(g:translate_it_winid, opts)
endfunction

function s:trace_next_tick() abort
  call s:next_tick()
        \.then(function('s:trace'))
        \.catch({ex->execute('echom string(ex)', '')})
endfunction

function! translate_it#register() abort
  call translate_it#event_on()
endfunction

function! translate_it#event_on() abort
  augroup translate_it_events
    au!
    au CursorMoved * call s:trace_next_tick()
    au InsertEnter * call s:trace()
  augroup END
endfunction

function! translate_it#event_off() abort
  augroup translate_it_events
    au!
  augroup END
endfunction

function! translate_it#cword() abort
  call s:trans(expand('<cword>'))
endfunction

function! translate_it#cword_or_close() abort
  if translate_it#is_closable()
    call translate_it#close()
  else
    call s:trans(expand('<cword>'))
  endif
endfunction

function! translate_it#visual() abort
  let str = translate_it#get_visual_text()
  call s:trans(s:joinlines(str))
endfunction

function! translate_it#visual_or_close() abort
  if translate_it#is_closable()
    call translate_it#close()
  else
    let str = translate_it#get_visual_text()
    call s:trans(s:joinlines(str))
  endif
endfunction

function! translate_it#get_visual_text() abort
  let l:reg_save = @@
  silent normal! gvy
  let str = @@
  silent normal! gv
  let @@ = l:reg_save
  return str
endfunction

function! s:joinlines(str) abort
  let str = a:str
  let str = substitute(str, '\_s\+', ' ', 'g')
  return str
endfunction

function! translate_it#is_closable() abort
  return exists('g:translate_it_winid') && win_getid() != g:translate_it_winid
endfunction

" assumes that the last line is blank
function! s:count_apparent_lines()
  normal! gg
  let cnt = 0

  let lastcol = -1
  let col = 0
  while !(line('.') == line('$') || cnt > 100)
    normal! gj
    let cnt += 1
    let lastcol = col
    let col = col('.')
  endwhile
  normal! Gdd
  return cnt
endfunction

