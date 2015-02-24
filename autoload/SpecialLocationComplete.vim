" SpecialLocationComplete.vim: Insert mode completion for special custom patterns.
"
" DEPENDENCIES:
"   - CompleteHelper.vim autoload script
"   - Complete/Repeat.vim autoload script
"   - ingo/query/get.vim autoload script
"
" Copyright: (C) 2015 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"   1.00.003	19-Feb-2015	Support a:options.emptyBasePattern.
"				Add SpecialLocationComplete#SetKey() and
"				SpecialLocationComplete#GetKey() for testing.
"				Allow passing a key to
"				SpecialLocationComplete#Expr() to enable custom
"				direct mappings.
"   1.00.002	16-Feb-2015	Need to get repeat...Expr from a:options; there
"				are no local variables.
"	001	13-Feb-2015	file creation
let s:save_cpo = &cpo
set cpo&vim

function! s:GetConfig( key )
    if exists('w:SpecialLocationCompletions') && has_key(w:SpecialLocationCompletions, a:key)
	return ['w', w:SpecialLocationCompletions[a:key]]
    elseif exists('b:SpecialLocationCompletions') && has_key(b:SpecialLocationCompletions, a:key)
	return ['b', b:SpecialLocationCompletions[a:key]]
    elseif exists('g:SpecialLocationCompletions') && has_key(g:SpecialLocationCompletions, a:key)
	return ['g', g:SpecialLocationCompletions[a:key]]
    else
	return ['', {}]
    endif
endfunction
function! s:GetAllConfigKeys()
    let l:keys = []
    for l:key in
    \   (exists('w:SpecialLocationCompletions') ? sort(keys(w:SpecialLocationCompletions)) : []) +
    \   (exists('b:SpecialLocationCompletions') ? sort(keys(b:SpecialLocationCompletions)) : []) +
    \   (exists('g:SpecialLocationCompletions') ? sort(keys(g:SpecialLocationCompletions)) : [])
	if index(l:keys, l:key) == -1
	    call add(l:keys, l:key)
	endif
    endfor
    return l:keys
endfunction
function! s:CreateHint( key )
    return [a:key, get(s:GetConfig(a:key)[1], 'description', '')]
endfunction
function! s:PrintAvailableKeys()
    let l:keys = s:GetAllConfigKeys()
    if empty(l:keys)
	return 0
    endif

    echohl ModeMsg
    echo '-- Special location completion:'

    for [l:key, l:description] in map(l:keys, 's:CreateHint(v:val)')
	if empty(l:description)
	    echon ' ' . l:key
	else
	    echon ' ' . l:key
	    echohl None
	    echon '(' . l:description . ')'
	    echohl ModeMsg
	endif
    endfor

    echohl None
    return 1
endfunction

function! s:GetOptions()
    let [l:scope, l:options] = s:GetConfig(s:key)
    if empty(l:options)
	throw 'SpecialLocationComplete: No such key'
    elseif ! has_key(l:options, 'complete')
	" Default to a completion scope that corresponds to the config scope.
	if l:scope ==# 'w'
	    let l:options.complete = '.,w'
	elseif l:scope ==# 'b'
	    let l:options.complete = '.'
	elseif l:scope ==# 'g'
	    let l:options.complete = &complete
	else
	    throw 'ASSERT: Unknown scope: ' . string(l:scope)
	endif
    endif

    return l:options
endfunction
function! s:ExpandTemplate( template, value, ... )
    return substitute(a:template, '%' . (a:0 ? '[sS]' : 's'), "\\='\\V' . (a:0 && submatch(0) ==# '%S' ? a:1 : a:value) . '\\m'", 'g')
endfunction
function! SpecialLocationComplete#GetKey()
    call inputsave()
	let l:key = ingo#query#get#Char()
    call inputrestore()
    return l:key
endfunction
function! SpecialLocationComplete#SetKey( key )
    let s:key = a:key
endfunction
let s:repeatCnt = 0
function! SpecialLocationComplete#SpecialLocationComplete( findstart, base )
    if ! exists('s:key')
	if ! s:PrintAvailableKeys()
	    return -1
	endif

	let s:key = SpecialLocationComplete#GetKey()

	if a:findstart
	    " Invoked by CompleteHelper#Repeat#TestForRepeat(); continue to
	    " determine the base.
	else
	    " Just invoked to query for s:key.
	    return ''
	endif
    endif

    try
	let l:options = s:GetOptions()

	if s:repeatCnt
	    if a:findstart
		return col('.') - 1
	    else
		if has_key(l:options, 'repeatPatternTemplate')
		    " Need to translate the embedded ^@ newline into the \n atom.
		    let l:previousFullCompleteExpr = substitute(escape(s:fullText, '\'), '\n', '\\n', 'g')
		    let l:previousAddedCompleteExpr = substitute(escape(s:addedText, '\'), '\n', '\\n', 'g')

		    let l:repeatPattern = s:ExpandTemplate(l:options.repeatPatternTemplate, l:previousFullCompleteExpr, l:previousAddedCompleteExpr)
		else
		    let l:repeatPatternArguments = [s:fullText]
		    if has_key(l:options, 'repeatAnchorExpr')
			call add(l:repeatPatternArguments, l:options.repeatAnchorExpr)
			if has_key(l:options, 'repeatPositiveExpr')
			    call add(l:repeatPatternArguments, l:options.repeatPositiveExpr)
			    if has_key(l:options, 'repeatNegativeExpr')
				call add(l:repeatPatternArguments, l:options.repeatNegativeExpr)
			    endif
			endif
		    endif
		    let l:repeatPattern = call('CompleteHelper#Repeat#GetPattern', l:repeatPatternArguments)
		endif

		let l:options.processor = function('CompleteHelper#Repeat#Processor')

		let l:matches = []
		call CompleteHelper#FindMatches(l:matches,
		\   l:repeatPattern,
		\   l:options
		\)
		if empty(l:matches)
		    call CompleteHelper#Repeat#Clear()
		endif
		return l:matches
	    endif
	endif

	if a:findstart
	    " Locate the start of the configured characters.
	    let l:base = get(l:options, 'base', '\k\*\%#')

	    let l:startCol = searchpos(l:base, 'bn', line('.'))[1]
	    if l:startCol == 0
		let l:startCol = col('.')
	    endif
	    return l:startCol - 1 " Return byte index, not column.
	else
	    " Find matches.
	    let l:pattern = (empty(a:base) && has_key(l:options, 'emptyBasePattern') ?
	    \   get(l:options, 'emptyBasePattern') :
	    \   s:ExpandTemplate(get(l:options, 'patternTemplate', '\<%s\k\+'), escape(a:base, '\'))
	    \)

	    let l:matches = []
	    call CompleteHelper#FindMatches(l:matches, l:pattern, l:options)
	    return l:matches
	endif
    catch /^SpecialLocationComplete:/
	return -1
    endtry
endfunction

function! SpecialLocationComplete#Expr( ... )
    if a:0
	let s:key = a:1
    else
	" If this is not a repeat, CompleteHelper#Repeat#TestForRepeat() invokes
	" 'completefunc' to determine the future base. We need to query the user
	" (once!) before that.
	let l:save_key = (exists('s:key') ? s:key : '')
	unlet! s:key
    endif

    set completefunc=SpecialLocationComplete#SpecialLocationComplete

    let s:repeatCnt = 0 " Important!
    let [s:repeatCnt, s:addedText, s:fullText] = CompleteHelper#Repeat#TestForRepeat()

    if s:repeatCnt && exists('l:save_key')
	" In the repeat case, above 'completefunc' hasn't yet been invoked.
	" Restore the previous key to enable proper repeat without re-querying
	" it from the user.
	let s:key = l:save_key
    endif

    return "\<C-x>\<C-u>"
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
