#!/usr/bin/lua
package.path = 'rt/?.lua;luart/?.lua;' .. package.path
local make = require 'make'

BOOTRT = function() end

local _stack = require 'stack'
local _table = require '_table'
local _rt = require 'rt'
local _vm = require 'vm'
local _alloc = require 'alloc'
local _gc = require 'gc'
local _lex = require '_lex'

local M = make.mod()
local function export(obj, ...)
	for i=1, select('#', ...) do
		local name = select(i, ...)
		M:export(name, obj[name])
	end
end
local function import(obj, ...)
	for i=1, select('#', ...) do
		M:import(obj[select(i, ...)])
	end
end
export(_stack, 'tmppush', 'tmppop', 'nthtmp', 'setnthtmp')
export(_rt, 'getluastack', 'setluastack')
export(_alloc, 'newi64', 'newf64', 'newtbl', 'newstr', 'newvec', 'newvec1',
	'newstrbuf', 'newvecbuf', 'newfunc', 'newcoro')
export(_gc, 'gcmark')
export(_lex, 'lex')
import(_rt, 'memory', 'igcfix', 'igcmark', 'echo', 'echoptr', 'sin', 'cos', 'tan',
	'asin', 'acos', 'atan', 'atan2', 'exp', 'log')
M:data(_rt.image)
local chunks = M:compile()

io.open('scripts/lex.wasm', 'w'):write(table.unpack(chunks)):close()
