dataframe = {
	type = str.base + 0,
	pc = str.base + 1,
	retb = str.base + 5, -- index of where return values should begin
	retc = str.base + 9, -- # of values requested from call, -1 for no limit
	base = str.base + 13, -- index top objframe
	localc = str.base + 17, -- # of locals
	sizeof = 21,
}
objframe = {
	bc = vec.base + 0,
	consts = vec.base + 4,
	frees = vec.base + 8,
	locals = vec.base + 12,
	sizeof = 16,
}
calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}

init = export('init', func(i32, function(f, fn)
	-- Transition oluastack to having a stack frame from fn
	-- Assumes stack was previous setup

	local a, b, stsz = f:locals(i32, 3)

	f:load(fn)
	f:call(tmppush)

	f:i32(63)
	f:call(newstrbuf)
	f:tee(a)
	f:loadg(oluastack)
	f:load(a)
	f:i32store(coro.data)
	f:i32load(buf.ptr)
	f:tee(a)
	assert(dataframe.retb == dataframe.pc + 4)
	f:i64(0)
	f:i64store(dataframe.pc)

	f:load(a)
	assert(dataframe.base == dataframe.retc + 4)
	f:i64(0xffffffff) -- -1, 0
	f:i64store(dataframe.retc)

	f:load(a)
	f:i32(4)
	f:call(nthtmp)
	f:tee(fn)
	f:i32load(functy.localc)
	f:i32store(dataframe.localc)

	-- leak old stack until it's overwritten
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:tee(a)
	f:i32(0)
	f:i32store(buf.len)

	f:load(fn)
	f:i32load(functy.localc)
	f:i32(2)
	f:shl()
	f:i32(objframe.sizeof)
	f:add()
	f:tee(stsz)
	f:load(a)
	f:i32load(buf.ptr)
	f:tee(b)
	f:i32load(vec.len)
	f:leu() -- leu over ltu because vec buffer relies on a nil topslot
	f:iff(function()
		f:load(fn)
		f:storeg(otmp)

		f:load(stsz)
		f:call(newvec)
		f:store(b)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:load(b)
		f:i32store(buf.ptr)

		f:loadg(otmp)
		f:store(fn)
	end)

	f:load(b)
	f:load(fn)
	f:i32load(functy.bc)
	f:i32store(objframe.bc)

	f:load(b)
	f:load(fn)
	f:i32load(functy.consts)
	f:i32store(objframe.consts)

	f:load(b)
	f:load(fn)
	f:i32load(functy.frees)
	f:i32store(objframe.frees)
end))

-- TODO settle on base/retc units & absolute vs relative. Then fix mismatchs everywhere
eval = export('eval', func(i32, function(f)
	local a, b, c, d, e,
		meta_callty, meta_retb, meta_retc, meta_key, meta_off,
		datastack, bc, baseptr, valstack, valvec,
		pc, localc, base = f:locals(i32, 5+5+5+3)

	local function loadframe(tmp)
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:tee(datastack)
		f:i32load(buf.ptr)
		f:load(datastack)
		f:i32load(buf.len)
		f:add()
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(tmp)
		f:i32load(dataframe.base)
		f:store(base)

		f:load(tmp)
		f:i32load(dataframe.localc)
		f:store(localc)

		f:load(tmp)
		f:i32load(dataframe.pc)
		f:store(pc)
	end
	local function readArg()
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32load(str.base)
		f:load(pc)
		f:i32(4)
		f:add()
		f:store(pc)
	end

	loadframe(c)

	f:switch(function(scopes)
		-- valstack = ls.stack
		-- baseptr = ls.obj.ptr + base
		-- bc = baseptr.bc
		-- switch bc[pc++]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(valstack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		f:tee(baseptr)
		f:i32load(objframe.bc)
		f:tee(bc)
		f:load(pc)
		f:add()
		f:i32load8u(str.base)
		f:load(pc)
		f:i32(1)
		f:add()
		f:store(pc)
		f:call(echo)
	end, 1, 'loadnil', function(scopes)
		f:load(valstack)
		f:i32(NIL)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, 2, 'loadfalse', function(scopes)
		f:load(valstack)
		f:i32(FALSE)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, 3, 'loadtrue', function(scopes)
		f:load(valstack)
		f:i32(TRUE)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, 4, 'eq', function(scopes)
		f:load(valvec)
		f:load(valstack)
		f:i32load(buf.len)
		f:tee(b)
		f:add()
		f:tee(a)
		loadvecminus(f, 4)
		f:tee(c)
		f:load(a)
		loadvecminus(f, 8)
		f:tee(d)
		f:call(eq)
		f:iff(i32, function()
			f:i32(TRUE)
		end, function()
			-- if neq, check if both tables
			-- if both tables, check if same meta
			-- if same meta, push metaeqframe
			f:load(c)
			f:i32load8u(obj.type)
			f:i32(types.tbl)
			f:eq()
			f:load(d)
			f:i32load8u(obj.type)
			f:i32(types.tbl)
			f:eq()
			f:band()
			f:iff(function()
				f:load(c)
				f:i32load(tbl.meta)
				f:load(d)
				f:i32load(tbl.meta)
				f:tee(c)
				f:eq()
				f:iff(function()
					f:load(c)
					f:i32(GS.__eq)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:i32(calltypes.bool)
						f:store(meta_callty)
						f:load(valstack)
						f:i32load(buf.len)
						f:i32(8)
						f:sub()
						f:store(meta_retb)
						f:i32(1)
						f:store(meta_retc)
						f:i32(GS.__eq)
						f:store(meta_key)
						f:i32(8)
						f:store(meta_off)
						f:br(scopes.meta)
					end)
				end)
			end)
			f:i32(FALSE)
		end)
		-- s[-2:] = boolres
		f:store(c)
		f:load(valstack)
		f:load(b)
		f:i32(4)
		f:sub()
		f:i32store(buf.len)
		f:load(valvec)
		f:load(b)
		f:add()
		f:tee(b)
		f:i32(NIL)
		f:i32store(vec.base - 4)
		f:load(b)
		f:load(c)
		f:i32store(vec.base - 8)
		f:br(scopes.nop)
	end, 5, 'add', function(scopes)
		-- pop x, y
		-- metacheck
		-- typecheck
		f:br(scopes.nop)
	end, 6, 'idx', function(scopes)
		f:loop(function(loop)
			-- TODO Lua limits chains to 2000 length to try detect infinite loops
			f:i32(8)
			f:call(nthtmp)
			f:tee(a)
			f:i32load(obj.type)
			f:tee(b)
			f:i32(types.tbl)
			f:eq()
			f:iff(function()
				f:load(a)
				f:i32load(tbl.meta)
				f:tee(b)
				f:iff(function()
					f:load(b)
					f:i32(GS.__index)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:load(d)
						f:i32load(obj.type)
						f:i32(types.functy)
						f:eq()
						f:iff(function()
							f:i32(calltypes.norm)
							f:store(meta_callty)
							f:load(valstack)
							f:i32load(buf.len)
							f:i32(8)
							f:sub()
							f:store(meta_retb)
							f:i32(1)
							f:store(meta_retc)
							f:i32(GS.__index)
							f:store(meta_key)
							f:i32(8)
							f:store(meta_off)
							f:br(scopes.meta)
						end)
						f:i32(8)
						f:load(d)
						f:call(setnthtmp)
						f:br(loop)
					end)
				end)
				f:load(a)
				f:i32(4)
				f:call(nthtmp)
				f:call(tblget)
				f:i32(8)
				f:call(setnthtmp)
				f:call(tmppop)
				f:br(scopes.nop)
			end, function()
				f:load(b)
				f:i32(types.str)
				f:eq()
				f:iff(function()
					f:loadg(ostrmt)
					f:i32(8)
					f:call(setnthtmp)
					f:br(loop)
				end)
				f:unreachable()
			end)
		end)
	end, 7, 'not', function(scopes)
		f:load(valvec)
		f:load(valstack)
		f:i32load(buf.len)
		f:add()
		f:tee(a)
		f:i32(TRUE)
		f:i32(FALSE)
		f:load(a)
		loadvecminus(f, 4)
		f:i32(TRUE)
		f:geu()
		f:select()
		f:i32store(vec.base - 4)
		f:br(scopes.nop)
	end, 8, 'len', function(scopes)
		f:load(valvec)
		f:load(valstack)
		f:i32load(buf.len)
		f:add()
		loadvecminus(f, 4)
		f:tee(a)
		f:i32load8u(obj.type)
		f:tee(b)
		f:i32(types.str)
		f:eq()
		f:iff(i32, function()
			f:load(a)
			f:i32load(str.len)
		end, function()
			f:load(b)
			f:i32(types.tbl)
			f:eq()
			f:iff(i32, function()
				f:load(a)
				f:i32load(tbl.meta)
				f:tee(b)
				f:iff(function()
					f:load(b)
					f:i32(GS.__len)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:i32(calltypes.norm)
						f:store(meta_callty)
						f:load(valstack)
						f:i32load(buf.len)
						f:i32(4)
						f:sub()
						f:store(meta_retb)
						f:i32(1)
						f:store(meta_retc)
						f:i32(GS.__len)
						f:store(meta_key)
						f:i32(4)
						f:store(meta_off)
						f:br(scopes.meta)
					end)
				end)
				f:load(a)
				f:i32load(tbl.len)
			end, function()
				f:unreachable()
			end)
		end)
		f:i64extendu()
		f:call(newi64)
		f:i32(4)
		f:call(setnthtmp)
		f:br(scopes.nop)
	end, 9, 'mktbl', function(scopes)
		f:call(newtbl)
		f:store(a)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:load(a)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, 10, 'tblset', function(scopes)
		-- s[-3][s[-2]] = s[-1]
		f:load(valvec)
		f:load(valstack)
		f:i32load(buf.len)
		f:add()
		f:tee(a)
		loadvecminus(f, 12)
		f:load(a)
		loadvecminus(f, 8)
		f:load(a)
		loadvecminus(f, 4)
		f:call(tblset)

		-- del s[-2:]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:i32load(buf.ptr)
		f:load(a)
		f:i32load(buf.len)
		f:tee(b)
		f:add()
		assert(vec.base >= 8 and NIL == 0)
		f:i64(0)
		f:i64store(vec.base - 8)
		f:load(a)
		f:load(b)
		f:i32(8)
		f:sub()
		f:i32store(buf.len)
	end, 11, 'tbladd', function(scopes)
		readArg()
		f:i64extendu()
		f:call(newi64)
		f:store(c)

		-- s[-2][c] = s[-1]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:i32load(buf.ptr)
		f:load(a)
		f:i32load(buf.len)
		f:add()
		f:tee(a)
		loadvecminus(f, 8)
		f:load(c)
		f:load(a)
		loadvecminus(f, 4)
		f:call(tblset)

		-- del s[-1]
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(a)
		f:i32load(buf.ptr)
		f:load(a)
		f:i32load(buf.len)
		f:tee(b)
		f:add()
		assert(vec.base >= 4)
		f:i32(NIL)
		f:i32store(vec.base - 4)
		f:load(a)
		f:load(b)
		f:i32(4)
		f:sub()
		f:i32store(buf.len)
	end, 12, 'ret', function(scopes)
	-- pop stack frame

		f:load(datastack)
		f:load(datastack)
		f:i32load(buf.len)
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(baseptr)
		f:i32store(buf.len)

		f:load(datastack)
		f:load(baseptr)
		f:add()
		f:i32load(dataframe.retc)
		f:i32(-1)
		f:ne()
		f:load(valstack)
		f:i32load(buf.len)
		f:tee(b)
		f:load(datastack)
		f:load(baseptr)
		f:add()
		f:i32load(dataframe.retc)
		f:load(base)
		f:add()
		f:tee(c)
		f:ne()
		f:band()
		-- check ne to avoid lt/gt checks most of the time
		f:iff(function()
			f:load(b)
			f:load(c)
			f:gtu()
			f:iff(function()
				-- shrink stack
				f:loop(function(loop)
					f:load(valstack)
					f:call(popvec)
					f:drop()
					f:load(b)
					f:i32(1)
					f:sub()
					f:tee(b)
					f:load(c)
					f:gtu()
					f:brif(loop)
				end)
			end, function()
				-- pad stack with nils
				f:loop(function(loop)
					f:load(valstack)
					f:i32(NIL)
					f:call(pushvec)
					f:store(valstack)
					f:load(b)
					f:i32(1)
					f:add()
					f:tee(b)
					f:load(c)
					f:ltu()
					f:brif(loop)
				end)
			end)
		end)
		f:block(function(loadframe)
			f:block(function(boolify)
				f:block(function(endprog)
					-- read callty from freed memory
					f:loadg(oluastack)
					f:i32load(coro.data)
					f:tee(a)
					f:i32load(buf.ptr)
					f:load(a)
					f:i32load(buf.len)
					f:add()
					f:i32load(dataframe.type)
					f:brtable(loadframe, endprog, loadframe, loadframe, loadframe, boolify)
				end) -- endprog
				f:loadg(oluastack)
				f:i32load(coro.caller)
				f:tee(a)
				f:iff(function()
					f:loadg(oluastack)
					f:i32(corostate.dead)
					f:i32store(coro.state)

					-- a = dst
					-- b = dst.stack.len
					-- c = src.stack.len
					-- concat src's stack to dst's stack
					f:load(a)
					f:i32load(coro.stack)
					f:tee(a)
					f:i32load(buf.len)
					f:store(b)
					f:load(a)
					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:i32load(buf.len)
					f:tee(c)
					f:call(extendvec)
					f:tee(a)
					f:i32load(buf.ptr)
					f:load(b)
					f:add()
					f:i32(vec.base)
					f:add()
					f:loadg(oluastack)
					f:i32load(coro.stack)
					f:i32load(buf.ptr)
					f:i32(vec.base)
					f:add()
					f:load(c)
					f:call(memcpy4)

					f:load(a)
					f:storeg(oluastack)
					f:br(loadframe)
				end, function()
					f:load(valstack)
					f:call(unbufvec)
					f:ret()
				end)
			end) -- boolify
			f:load(valstack)
			f:i32load(buf.ptr)
			f:load(b)
			f:add()
			f:tee(b)
			f:i32(FALSE)
			f:i32(TRUE)
			f:load(b)
			loadvecminus(f, 4)
			f:i32(TRUE)
			f:geu()
			f:select()
			f:i32store(vec.base - 4)
		end) -- loadframe
		loadframe(c)
		f:br(scopes.nop)
	end, 13, 'call', function(scopes)
	-- push stack frame header
		f:br(scopes.nop)
	end, 14, 'retcall', function(scopes)
	-- pop stack frame, then call
		f:br(scopes.nop)
	end, 15, 'loadconst', function(scopes)
		f:load(valstack)
		f:load(baseptr)
		f:i32load(objframe.const)
		readArg()
		f:add()
		f:i32load(vec.base)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, 16, 'loadlocal', function(scopes)
		f:load(valstack)
		f:load(baseptr)
		readArg()
		f:i32load(objframe.locals)
		f:call(pushvec)
		f:drop()
		f:br(scopes.nop)
	end, 17, 'storelocal', function(scopes)
		f:load(baseptr)
		readArg()
		f:add()
		f:load(valstack)
		f:call(popvec)
		f:i32store(objframe.locals)
		f:br(scopes.nop)
	end, 19, 'jif', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:geu()
		f:brtable(scopes.pcp4, scopes.jmp)
	end, 20, 'jifnot', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:ltu()
		f:brtable(scopes.pcp4, scopes.jmp)
	end, 21, 'jiforpop', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:geu()
		f:brif(scopes.jmp)
		f:call(tmppop)
		f:br(scopes.pcp4)
	end, 22, 'jifnotorpop', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:ltu()
		f:brif(scopes.jmp)
		f:call(tmppop)
		f:br(scopes.pcp4)
	end, 23, 'pop', function(scopes)
		readArg()
		f:store(a)

		f:loop(function(loop)
			f:load(a)
			f:eqz()
			f:brif(scopes.nop)
			f:call(tmppop)
			f:load(a)
			f:i32(1)
			f:sub()
			f:store(a)
			f:br(loop)
		end)
	end, 24, 'neg', function(scopes)
		assert(types.int == 0 and types.float == 1 and types.tbl == 4 and types.str == 5)
		f:loop(function(loop)
			f:switch(function()
				f:i32(4)
				f:call(nthtmp)
				f:tee(a)
				f:i32load8u(obj.type)
			end, types.int, function()
				f:i64(0)
				f:load(a)
				f:i64load(num.val)
				f:sub()
				f:call(newi64)
				f:i32(4)
				f:call(setnthtmp)
				f:br(scopes.nop)
			end, types.float, function()
				f:load(a)
				f:f64load(num.val)
				f:neg()
				f:call(newf64)
				f:i32(4)
				f:call(setnthtmp)
				f:br(scopes.nop)
			end, types.tbl, function()
				f:load(a)
				f:i32load(tbl.meta)
				f:tee(b)
				f:iff(function()
					f:load(b)
					f:i32(GS.__unm)
					f:call(tblget)
					f:tee(d)
					f:iff(function()
						f:i32(calltypes.norm)
						f:store(meta_callty)
						f:load(valstack)
						f:i32load(buf.len)
						f:i32(4)
						f:sub()
						f:store(meta_retb)
						f:i32(1)
						f:store(meta_retc)
						f:i32(GS.__unm)
						f:store(meta_key)
						f:i32(4)
						f:store(meta_off)
						f:br(scopes.meta)
					end)
				end)
			end, types.str, function()
				f:load(a)
				f:call(tonum)
				f:i32(4)
				f:call(setnthtmp)
				f:br(loop)
			end, 2, 3, -1)
			f:unreachable()
		end)
	end, 25, 'bnot', function(scopes)
		f:loop(function(loop)
			f:i32(4)
			f:call(nthtmp)
			f:tee(a)
			f:i32load8u(obj.type)
			f:tee(b)
			f:iff(function()
				f:load(a)
				f:i64load(num.base)
				f:i64(-1)
				f:xor()
				f:call(newi64)
				f:i32(4)
				f:call(setnthtmp)
				f:br(scopes.nop)
			end, function()
				f:load(b)
				f:i32(types.tbl)
				f:eq()
				f:iff(function()
					f:load(a)
					f:i32load(tbl.meta)
					f:tee(b)
					f:iff(function()
						f:load(b)
						f:i32(GS.__bnot)
						f:call(tblget)
						f:tee(d)
						f:iff(function()
							f:i32(calltypes.norm)
							f:store(meta_callty)
							f:load(valstack)
							f:i32load(buf.len)
							f:i32(4)
							f:sub()
							f:store(meta_retb)
							f:i32(1)
							f:store(meta_retc)
							f:i32(GS.__bnot)
							f:store(meta_key)
							f:i32(4)
							f:store(meta_off)
							f:br(scopes.meta)
						end)
					end)
				end, function()
					f:load(a)
					f:call(toint)
					f:i32(4)
					f:call(setnthtmp)
					f:br(loop)
				end)
			end)
			f:unreachable()
		end)
	end, 26, 'ge', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(setnthtmp)
		f:i32(8)
		f:call(setnthtmp)
		f:br(scopes.lt)
	end, 27, 'gt', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(setnthtmp)
		f:i32(8)
		f:call(setnthtmp)
		f:br(scopes.le)
	end, 28, 'le', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:tee(c)
		f:i32(8)
		f:call(nthtmp)
		f:tee(b)
		f:i32load8u(obj.type)
		f:tee(d)
		f:i32(4)
		f:shl()
		f:bor()
		f:tee(e)
		assert(types.int == 0)
		f:eqz()
		f:iff(i32, function()
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(a)
			f:i64load(num.val)
			f:load(b)
			f:i64load(num.val)
			f:les()
			f:select()
		end, function()
			f:load(e)
			f:i32(types.float|types.float<<4)
			f:eq()
			f:iff(i32, function()
				f:i32(TRUE)
				f:i32(FALSE)
				f:load(a)
				f:f64load(num.val)
				f:load(b)
				f:f64load(num.val)
				f:le()
				f:select()
			end, function()
				f:load(e)
				f:i32(types.str|types.str<<4)
				f:eq()
				f:iff(i32, function()
					f:i32(TRUE)
					f:i32(FALSE)
					f:load(a)
					f:load(b)
					f:call(strcmp)
					f:i32(-1)
					f:eq()
					f:select()
				end, function()
					f:load(e)
					f:i32(types.int|types.float<<4)
					f:eq()
					f:iff(i32, function()
						f:i32(TRUE)
						f:i32(FALSE)
						f:load(a)
						f:i64load(num.base)
						f:f64converts()
						f:load(b)
						f:f64load(num.base)
						f:le()
						f:select()
					end, function()
						f:load(e)
						f:i32(types.float|types.int<<4)
						f:eq()
						f:iff(i32, function()
							f:i32(TRUE)
							f:i32(FALSE)
							f:load(a)
							f:i64load(num.base)
							f:f64converts()
							f:load(b)
							f:f64load(num.base)
							f:le()
							f:select()
						end, function()
							-- TODO metamethod stuff
							f:unreachable()
						end)
					end)
				end)
			end)
		end)
		f:i32(8)
		f:call(setnthtmp)
		f:call(tmppop)
		f:br(scopes.nop)
	end, 29, 'lt', function(scopes)
		f:i32(4)
		f:call(nthtmp)
		f:tee(a)
		f:i32load8u(obj.type)
		f:tee(c)
		f:i32(8)
		f:call(nthtmp)
		f:tee(b)
		f:i32load8u(obj.type)
		f:tee(d)
		f:i32(4)
		f:shl()
		f:bor()
		f:tee(e)
		assert(types.int == 0)
		f:eqz()
		f:iff(i32, function()
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(a)
			f:i64load(num.val)
			f:load(b)
			f:i64load(num.val)
			f:lts()
			f:select()
		end, function()
			f:load(e)
			f:i32(types.float|types.float<<4)
			f:eq()
			f:iff(i32, function()
				f:i32(TRUE)
				f:i32(FALSE)
				f:load(a)
				f:f64load(num.val)
				f:load(b)
				f:f64load(num.val)
				f:lt()
				f:select()
			end, function()
				f:load(e)
				f:i32(types.str|types.str<<4)
				f:eq()
				f:iff(i32, function()
					f:i32(TRUE)
					f:i32(FALSE)
					f:load(a)
					f:load(b)
					f:call(strcmp)
					f:i32(-1)
					f:eq()
					f:select()
				end, function()
					f:load(e)
					f:i32(types.int|types.float<<4)
					f:eq()
					f:iff(i32, function()
						f:i32(TRUE)
						f:i32(FALSE)
						f:load(a)
						f:i64load(num.base)
						f:f64converts()
						f:load(b)
						f:f64load(num.base)
						f:lt()
						f:select()
					end, function()
						f:load(e)
						f:i32(types.float|types.int<<4)
						f:eq()
						f:iff(i32, function()
							f:i32(TRUE)
							f:i32(FALSE)
							f:load(a)
							f:i64load(num.base)
							f:f64converts()
							f:load(b)
							f:f64load(num.base)
							f:lt()
							f:select()
						end, function()
							-- TODO metamethod stuff
							f:unreachable()
						end)
					end)
				end)
			end)
		end)
		f:i32(8)
		f:call(setnthtmp)
		f:call(tmppop)
		f:br(scopes.nop)
	end, 31, 'syscall', function(scopes)
		f:switch(function()
			readArg()
		end, 0, function()
			f:call(std_pcall)
			f:br(scopes.nop)
		end, 1, function()
			f:call(std_select)
			f:br(scopes.nop)
		end, 2, function()
			f:call(coro_status)
			f:br(scopes.nop)
		end, 3, function()
			f:call(coro_running)
			f:br(scopes.nop)
		end, 4, function()
			f:call(std_getmetatable)
			f:br(scopes.nop)
		end, 5, function()
			f:call(std_setmetatable)
			f:br(scopes.nop)
		end)
		f:call(coro_create)
		f:br(scopes.nop)
	end, 18, 'jmp', function(scopes)
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32load(str.base)
		f:store(pc)
		f:br(scopes.nop)
	end, 'meta', function(scopes)
		-- d = func; metamethod, callty,
		-- push objframe
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(b)
		f:i32load(buf.len)
		f:store(a)
		f:load(b)
		f:i32(objframe.sizeof)
		f:load(d)
		f:i32load(functy.localc)
		f:tee(b)
		f:i32(2)
		f:shl()
		f:add()
		f:call(extendvec)

		-- writeobjframe
		f:tee(c)
		f:i32load(buf.ptr)
		f:load(c)
		f:i32load(buf.len)
		f:add()
		f:tee(c)
		assert(functy.consts == functy.bc + 4)
		assert(objframe.consts == objframe.bc + 4)

		-- reload metafunc
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(d)
		f:i32load(buf.ptr)
		f:load(d)
		f:i32load(buf.len)
		f:add()
		f:load(meta_off)
		f:sub()
		f:i32load(vec.base)
		f:store(d)

		f:load(meta_key)
		f:iff(function()
			f:load(d)
			f:i32load(tbl.meta)
			f:load(meta_key)
			f:call(tblget)
			f:store(d)
		end)

		f:load(d)
		f:i64load(functy.bc)
		f:i64store(objframe.bc)

		f:load(c)
		f:load(d)
		f:i32load(functy.frees)
		f:i32store(objframe.frees)

		-- push dataframe
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:i32(dataframe.sizeof)
		f:call(extendstr)

		-- write dataframe
		f:tee(datastack)
		f:i32load(buf.ptr)
		f:load(datastack)
		f:i32load(buf.len)
		f:add()
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(d)
		f:load(meta_callty)
		f:i32store8(dataframe.type)

		f:load(d)
		f:i32(0)
		f:i32store(dataframe.pc)

		f:load(d)
		f:load(meta_retb)
		f:i32store(dataframe.retb)

		f:load(d)
		f:load(b)
		f:i32store(dataframe.localc)

		f:load(d)
		f:load(meta_retc)
		f:i32store(dataframe.retc)

		f:load(d)
		f:load(a)
		f:i32store(dataframe.base)

		f:br(scopes.nop)
	end, 'pcp4', function()
		f:load(pc)
		f:i32(4)
		f:add()
		f:store(pc)
	end, 0, 'nop')

	-- check whether to yield (for now we'll yield after each instruction)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(datastack)
	f:i32load(buf.ptr)
	f:load(datastack)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
	f:load(pc)
	f:i32store(dataframe.pc)

	f:i32(0)
end))
