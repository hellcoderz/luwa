local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, vec, buf, coro, corostate, newcoro = alloc.types, alloc.obj, alloc.vec, alloc.buf, alloc.coro, alloc.corostate, alloc.newcoro

local stack = require 'stack'
local tmppush = stack.tmppush

local vm = require 'vm'
local dataframe, calltypes = vm.dataframe, vm.calltypes

coro_create = func(function(f)
	--[[
	-- expects oluastack to've been in stack-only mode
	local a, newst, localc, localc4 = f:locals(i32, 4)

	f:load(fn)
	f:i32load(functy.localc)
	f:tee(localc)
	f:i32(2)
	f:shl()
	f:tee(localc4)

	-- Must alloc enough so pushing fn props won't cause more allocs
	f:load(fn)
	f:call(tmppush)
	f:i32(12)
	f:call(extendtmp)
	f:call(newcoro)
	f:i32(4)
	f:call(setnthtmp)
	f:i32(63)
	f:call(newstrbuf)
	f:i32(8)
	f:call(setnthtmp)
	f:i32(56)
	f:add() -- adds localc4
	f:call(newvecbuf)
	f:i32(12)
	f:call(setnthtmp)

	f:i32(4)
	f:call(nthtmp)
	f:tee(newst)
	f:i32(8)
	f:call(nthtmp)
	f:i32store(coro.data)

	f:load(newst)
	f:i32(12)
	f:call(nthtmp)
	f:tee(a)
	f:i32store(coro.stack)

	-- obj frame
	f:load(a)
	f:i32(16)
	f:call(nthtmp)
	f:tee(fn)
	f:i32load(functy.bc)
	f:call(pushvec)
	f:load(fn)
	f:i32load(functy.consts)
	f:call(pushvec)
	f:load(fn)
	f:i32load(functy.frees)
	f:call(pushvec)
	f:load(a)
	f:i32load(buf.len)
	f:load(localc4)
	f:add()
	f:i32store(buf.len)

	-- data frame
	f:i32(8)
	f:call(nthtmp)
	f:tee(a)
	f:i32(dataframe.sizeof)
	f:i32store(buf.len)

	f:load(a)
	f:i32load(buf.ptr)
	f:tee(a)
	f:i32(calltypes.init)
	f:i32store8(dataframe.type)

	assert(dataframe.retb == dataframe.pc + 4)
	f:load(a)
	f:i64(0)
	f:i64store(dataframe.pc)

	assert(dataframe.base == dataframe.retc + 4)
	f:load(a)
	f:i64(0xffffffff) -- -1, 0
	f:i64store(dataframe.retc)

	f:load(a)
	f:load(localc)
	f:i32store(dataframe.localc)

	-- leak old stack until overwritten
	f:load(newst)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:tee(a)
	f:i32(0)
	f:i32store(buf.len)

	f:load(a)
	f:i32store(coro.stack)

	f:load(newst)
	f:storeg(oluastack)
	]]--
end)

coro_resume = func(function(f)
end)

coro_yield = func(function(f)
end)

coro_running = func(function(f)
	f:loadg(oluastack)
	f:call(tmppush)
	f:i32(TRUE)
	f:i32(FALSE)
	f:loadg(oluastack)
	f:i32load(coro.caller)
	f:select()
	f:call(tmppush)
end)

coro_status = func(function(f)
	local a = f:locals(i32)

	f:call(loadframebase)
	f:i32load(dataframe.base)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:add()
	f:i32load(vec.base)
	f:tee(a)
	f:i32load8u(obj.type)
	f:i32(types.coro)
	f:eq()
	f:iff(i32, function(res)
		f:switch(function()
			f:load(a)
			f:i32load(coro.state)
		end, corostate.dead, function()
			f:i32(GS.dead)
			f:br(res)
		end, corostate.norm, function()
			f:i32(GS.normal)
			f:br(res)
		end, corostate.live, function()
			f:i32(GS.running)
			f:br(res)
		end, corostate.wait)
		f:i32(GS.suspended)
	end, function()
		-- error
		f:unreachable()
	end)
	f:call(tmppush)
end)

return {
	coro_create = coro_create,
	coro_resume = coro_resume,
	coro_yield = coro_yield,
	coro_running = coro_running,
	coro_status = coro_status,
}
