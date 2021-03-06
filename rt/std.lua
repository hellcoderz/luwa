local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, num, str, tbl, vec, buf, coro, newi64 = alloc.types, alloc.obj, alloc.num, alloc.str, alloc.tbl, alloc.vec, alloc.buf, alloc.coro, alloc.newi64

local stack = require 'stack'
local tmppush, extendtmp = stack.tmppush, stack.extendtmp

local _table = require '_table'
local _obj = require 'obj'

local vm = require 'vm'
local dataframe, calltypes = vm.dataframe, vm.calltypes

local std_error = func(function(f)
end)

local std_next = func(function(f)
	local hash, hlen, kv, key, mx = f:locals(i32, 5)

	f:call(param0)
	f:i32load(vec.base + 4)
	f:tee(key)
	f:call(_obj.hash)

	f:call(param0)
	f:i32load(vec.base)
	f:i32load(tbl.hash)
	f:tee(hash)
	f:i32load(vec.len)
	f:tee(hlen)
	f:remu()
	f:i32(-8)
	f:band()

	f:load(hash)
	f:add()
	f:store(kv)

	f:load(hash)
	f:load(hlen)
	f:add()
	f:store(mx)

	f:load(key)
	f:iff(function(findnext)
		f:loop(function(loop)
			f:load(kv)
			f:i32load(vec.base)
			f:eqz()
			f:iff(function()
				f:i32(NIL)
				f:call(tmppush)
				f:ret()
			end)

			f:load(kv)
			f:i32load(vec.base)
			f:load(key)
			f:call(_obj.eq)
			f:iff(function()
				f:load(kv)
				f:i32(8)
				f:add()
				f:tee(kv)
				f:load(mx)
				f:ne()
				f:brif(findnext)
				f:i32(NIL)
				f:call(tmppush)
				f:ret()
			end)

			f:load(kv)
			f:i32(8)
			f:add()
			f:tee(kv)
			f:load(mx)
			f:ne()
			f:brif(loop)
			f:i32(NIL)
			f:call(tmppush)
			f:ret()
		end)
	end)

	f:loop(function(loop)
		f:load(kv)
		f:i32load(vec.base)
		f:iff(function()
			f:load(kv)
			f:i32load(vec.base)
			f:call(tmppush)
			f:load(kv)
			f:i32load(vec.base + 4)
			f:call(tmppush)
			f:ret()
		end)
		f:load(kv)
		f:i32(8)
		f:add()
		f:tee(kv)
		f:load(mx)
		f:ne()
		f:brif(loop)
	end)
	f:i32(NIL)
	f:call(tmppush)
end)

local std_pcall = func(function(f)
	-- > func, p1, p2, ...
	-- < true, p1, p2, ...
	-- modify datastack: 2, 0, framesz, retc, base+1
	local a, valvec, base = f:locals(i32, 3)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:tee(valvec)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
	f:tee(a)
	-- TODO load localc from p0 & assign to dataframe

	f:i32load(dataframe.base)
	f:tee(base)
	f:add()
	f:i32(TRUE)
	f:i32store(vec.base)

	f:load(a)
	f:i32(calltypes.prot)
	f:i32store8(dataframe.type)

	f:load(a)
	f:i32(0)
	f:i32store(dataframe.pc)

	f:load(a)
	f:load(a)
	f:i32load(dataframe.retb)
	f:i32(4)
	f:add()
	f:i32store(dataframe.retb)
end)

local std_rawget = func(function(f)
	f:call(param0)
	f:i32load(vec.base)
	f:call(param0)
	f:i32load(vec.base + 4)
	f:call(_table.tblget)
	f:call(tmppush)
end)

local std_rawset = func(function(f)
	f:call(param0)
	f:i32load(vec.base)
	f:call(param0)
	f:i32load(vec.base + 4)
	f:call(param0)
	f:i32load(vec.base + 8)
	f:call(_table.tblset)
end)

local std_select = func(function(f)
	-- L.stack[base] == '#' ? L.stack.len - base - 1 : L.stack[base + L.stack[base]:]
	local framebase, base, dotdotdot, p0, stack = f:locals(i32, 5)
	local dddlen, p0v = f:locals(i64, 2)

	f:call(loadframebase)
	f:tee(framebase)
	f:i32load(dataframe.base)
	f:tee(base)

	f:load(framebase)
	f:i32load(dataframe.locals)
	f:load(framebase)
	f:i32load(dataframe.dotdotdot)
	f:tee(dotdotdot)
	f:sub()
	f:i64extendu()
	f:store(dddlen)

	f:load(dotdotdot)
	f:add()
	f:tee(dotdotdot)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:load(base)
	f:add()
	f:i32load(vec.base)
	f:tee(p0)
	f:i32load8u(obj.type)
	f:i32(types.str)
	f:eq()
	f:iff(function()
		assert(str.base & 7 ~= 0)
		f:load(p0)
		f:i32load8u(str.base)
		f:i32(string.byte('#'))
		f:eq()
		f:load(p0)
		f:i32load(str.len)
		f:i32(1)
		f:eq()
		f:band()
		f:iff(function()
			f:load(dddlen)
			f:i64(2)
			f:shru()
			f:call(newi64)
			f:call(tmppush)
			f:ret()
		end)
	end)

	f:load(p0)
	f:call(toint)
	f:tee(p0)
	f:iff(function(err)
		f:load(dddlen)
		f:load(p0)
		f:i64load(num.val)
		f:load(p0v)
		f:sub()
		f:tee(dddlen)
		f:i64(0)
		f:lts()
		f:brif(f)

		f:load(p0v)
		f:i32wrap()
		f:store(p0)

		local exlen, oldtmplen = framebase, base

		-- oldtmplen, exlen = stack.len, dddlen - p0.val
		-- extendtmp exlen
		-- memcpy4 tmp+oldtmplen, tmp+dotdotdot+p0.val, exlen

		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.len)
		f:tee(oldtmplen)

		f:load(dddlen)
		f:i32wrap()
		f:tee(exlen)
		f:call(extendtmp)

		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(stack)
		f:load(oldtmplen)
		f:add()

		f:load(stack)
		f:load(dotdotdot)
		f:add()
		f:load(p0)
		f:add()

		f:load(exlen)
		f:call(memcpy4)
		f:ret()
	end)
	f:unreachable()
end)

local std_type = func(function(f)
	local a = f:locals(i32)
	f:block(i32, function(res)
		f:switch(function()
			f:call(param0)
			f:i32load(vec.base)
			f:tee(a)
			f:i32load8u(obj.type)
		end, types.int, types.float, function()
			f:i32(GS.number)
			f:br(res)
		end, types.single, function()
			f:i32(GS.boolean)
			f:i32(GS['nil'])
			f:load(a)
			f:select()
			f:br(res)
		end, types.tbl, function()
			f:i32(GS.table)
			f:br(res)
		end, types.str, function()
			f:i32(GS.string)
			f:br(res)
		end, types.vec, types.buf, function()
			f:i32(GS.userdata)
			f:br(res)
		end, types.functy, function()
			f:i32(GS['function'])
			f:br(res)
		end, types.coro)
		f:i32(GS.thread)
	end)
	f:call(tmppush)
end)

return {
	error = std_error,
	next = std_next,
	pcall = std_pcall,
	rawget = std_rawget,
	rawset = std_rawset,
	select = std_select,
	type = std_type,
}
