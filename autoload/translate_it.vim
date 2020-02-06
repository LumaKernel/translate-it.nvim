
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

let s:jobs = []
let s:line_breaks = ['\.', '．', '?', '!', '。', '？', '！']


function! s:option(strs) abort
  let maxlen = max(map(copy(a:strs), 'strlen(v:val)'))
  return {
      \   'relative': 'cursor',
      \   'width': max([min([maxlen, 100, float2nr(&columns * 0.9)]), 1]),
      \   'height': max([s:guess_height(a:strs), 1]),
      \   'col': 0,
      \   'row': 1,
      \   'anchor': 'NW',
      \   'style': 'minimal',
      \ }
endfunction

function! s:guess_height(strs) abort
  let cnt = 0
  for str in a:strs
    let cnt += (strlen(str) + 74) / 75
  endfor
  return cnt
endfunction

function! s:stop_all() abort
  for job in s:jobs
    sil! call s:J.job_stop(job)
  endfor
  let s:jobs = []
endfunction

let s:last_id = 0
function! s:trans(cmds, str) abort
  let t:cache_str_split = '...'
  call s:update()
  call s:stop_all()
  function! s:ret(resolve, reject) abort closure
    let opt = {}
    let s:last_id += 1
    let l:id = s:last_id
    let l:started = 0
    function! opt.out_cb(data) abort closure
      if l:id != s:last_id | return | endif
      if !l:started
        let l:started = 1
        let t:cache_str = ''
      endif
      let t:cache_str ..= a:data
      let t:cache_str_split = s:splitlines(t:cache_str)
      call s:update()
    endfunction
    let opt.err_cb = opt.out_cb

    let job = s:J.job_start(a:cmds + [a:str], opt)
    call add(s:jobs, job)
  endfunction

  return s:Promise.new(function('s:ret'))
endfunction

function! s:splitlines(str) abort
  let str = a:str

  let old_str = ''
  while str !=# old_str
    let old_str = str
    for lbreak in s:line_breaks
      let str = substitute(str, '\(^\|\n\)\(.\{-30,\}\)' .. lbreak .. '\(\n\|$\)\@!', "&\n", 'g')
    endfor
  endwhile

  return str
endfunction

let s:def_opts = [
      \   '-show-original=n',
      \   '-show-original-phonetics=n',
      \   '-show-prompt-message=n',
      \   '-show-languages=n',
      \   '-no-view',
      \ ]

function! s:get_executable()
  if exists('g:translate_it#translate_shell') && executable(g:translate_it#translate_shell)
    return g:translate_it#translate_shell
  endif
  if executable('trans') | return 'trans' | endif
  return 0
endfunction

function! translate_it#close() abort
  if !exists('t:translate_it_winid') || win_getid() == t:translate_it_winid
    return
  endif
  sil! call nvim_win_close(t:translate_it_winid, v:true)
  unlet t:translate_it_winid
endfunction

function! translate_it#finish() abort
  call translate_it#close()
endfunction

" Ensure the existence of window,
" resize window adjust to t:cache_str
" and update the buffer
function! s:update(...) abort
  if exists('t:translate_it_winid') && !nvim_win_is_valid(t:translate_it_winid)
    unlet t:translate_it_winid
    call s:update()
    return
  endif

  let strs = split(t:cache_str_split, "\n")
  call nvim_buf_set_lines(s:buf, 0, -1, v:true, strs)
  let old_winid = win_getid()
  let opts = s:option(strs)
  call translate_it#event_off()

  if exists('t:translate_it_winid')
    call nvim_win_set_config(t:translate_it_winid, opts)
    call win_gotoid(t:translate_it_winid)
  else
    let t:translate_it_winid = nvim_open_win(s:buf, 1, opts)
  endif

  call s:ANSI.define_syntax()
  call win_gotoid(old_winid)

  call translate_it#event_on()
endfunction

" Make window trace to cursor
function! s:trace(...) abort
  if !exists('t:translate_it_winid') || win_getid() == t:translate_it_winid | return | endif
  if !nvim_win_is_valid(t:translate_it_winid)
    unlet t:translate_it_winid
    call s:update()
    return
  endif
  let strs = split(t:cache_str_split, "\n")
  call nvim_buf_set_lines(s:buf, 0, -1, v:true, strs)
  let opts = s:option(strs)
  call nvim_win_set_config(t:translate_it_winid, opts)
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

function! translate_it#trans_show(str, source, target, more_opts) abort
  let cmd_opts = []

  let cmd = s:get_executable()
  if cmd is 0
    echoerr '[translate-it] Executable was not found.'
    echoerr '[translate-it] Check the variable g:translate_it#translate_shell.'
    return
  endif

  if type(a:source) == v:t_string && a:source !=# ''
    call add(cmd_opts, '-f')
    call add(cmd_opts, a:source)
  endif

  if type(a:target) == v:t_string && a:target !=# ''
    call add(cmd_opts, '-t')
    call add(cmd_opts, a:target)
  endif

  call s:trans([cmd] + s:def_opts + a:more_opts + cmd_opts, a:str)
        \.catch({ex -> execute('echom json_encode(ex)', '') })
endfunction

function! translate_it#cword(source, target, more_opts) abort
  call translate_it#trans_show(expand('<cword>'), a:source, a:target, ['-dictionary'] + a:more_opts)
endfunction

function! translate_it#visual(source, target, more_opts) abort
  let str = translate_it#get_visual_text()
  call translate_it#trans_show(s:joinlines(str), a:source, a:target, ['-brief'] + a:more_opts)
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

