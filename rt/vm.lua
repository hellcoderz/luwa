dataframe = {
	type = str.base + 0,
	pc = str.base + 1,
	base = str.base + 5, -- Base. params here
	dotdotdot = str.base + 9, -- base+dotdotdot = excess params here. Ends at base+locals
	retb = str.base + 11, -- base+retb = put return vals here
	retc = str.base + 13, -- base+retc = stack should be post return. 0xffff for piped return
	locals = str.base + 15, -- base+locals = locals here
	frame = str.base + 17, -- base+frame = objframe here
	sizeof = 19,
}
objframe = {
	bc = vec.base + 0,
	consts = vec.base + 4,
	frees = vec.base + 8,
	tmpbc = 12,
	tmpconsts = 8,
	tmpfrees = 4,
	sizeof = 12,
}
calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}

init = export('init', func(i32, void, function(f, fn)
	-- Transition oluastack to having a stack frame from fn
	-- Assumes stack was previously setup

	local a, stsz, newstsz = f:locals(i32, 3)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.len)
	f:store(stsz)

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
	assert(dataframe.base == dataframe.pc + 4)
	f:i64(0)
	f:i64store(dataframe.pc)

	f:load(a)
	assert(dataframe.retb == dataframe.dotdotdot + 2)
	f:i32(0)
	f:i32store(dataframe.dotdotdot)

	f:load(a)
	f:i32(-1)
	f:i32store16(dataframe.retc)

	f:load(a)
	f:load(stsz)
	f:i32store(dataframe.locals)

	f:load(a)
	f:load(stsz)
	f:load(fn)
	f:i32load(functy.localc)
	f:i32(2)
	f:shl()
	f:add()
	f:tee(newstsz)
	f:i32store(dataframe.frame)

	f:load(newstsz)
	f:call(extendtmp)
	f:call(tmppop)

	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:i32load(buf.ptr)
	f:load(stsz)
	f:add()
	f:tee(newstsz)
	f:i32load(vec.base)
	f:tee(fn)

	-- inject niling slot in case setnthtmp overwrites again
	-- ie when there are no locals
	f:load(newstsz)
	f:i32(NIL)
	f:i32store(vec.base)

	f:i32load(functy.bc)
	f:i32(objframe.tmpbc)
	f:call(setnthtmp)

	f:load(fn)
	f:i32load(functy.consts)
	f:i32(objframe.tmpconsts)
	f:call(setnthtmp)

	f:load(fn)
	f:i32load(functy.consts)
	f:i32(objframe.tmpfrees)
	f:call(setnthtmp)
end))

-- TODO settle on base/retc units & absolute vs relative. Then fix mismatchs everywhere
eval = export('eval', func(i32, function(f)
	local a, b, c, d, e,
		meta_callty, meta_retb, meta_retc, meta_key, meta_off,
		framebase, objbase, base, bc, pc = f:locals(i32, 5+5+5)

	local function loadframebase()
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:tee(framebase)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load(buf.len)
		f:add()
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(framebase)
	end

	local function loadframe()
		loadframebase()
		f:i32load(dataframe.base)
		f:store(base)

		f:load(framebase)
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

	loadframe()

	f:switch(function(scopes)
		-- baseptr = ls.obj.ptr + base
		-- bc = baseptr.bc
		-- switch bc[pc++]
		loadframebase()
		f:i32load16u(dataframe.frame)
		f:load(base)
		f:add()
		f:tee(objbase)
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
		f:i32(NIL)
		f:call(tmppush)
		f:br(scopes.nop)
	end, 2, 'loadfalse', function(scopes)
		f:i32(FALSE)
		f:call(tmppush)
		f:br(scopes.nop)
	end, 3, 'loadtrue', function(scopes)
		f:i32(TRUE)
		f:call(tmppush)
		f:br(scopes.nop)
	end, 4, 'eq', function(scopes)
		f:i32(8)
		f:call(nthtmp)
		f:tee(c)
		f:i32(4)
		f:call(nthtmp)
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
						f:i32(8)
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
		f:i32(8)
		f:call(setnthtmp)
		f:call(tmppop)
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
							f:i32(8)
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
		f:i32(TRUE)
		f:i32(FALSE)
		f:i32(4)
		f:call(nthtmp)
		f:i32(TRUE)
		f:geu()
		f:select()
		f:i32(4)
		f:call(setnthtmp)
		f:br(scopes.nop)
	end, 8, 'len', function(scopes)
		f:i32(4)
		f:call(nthtmp)
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
						f:i32(4)
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
		f:i32(12)
		f:call(nthtmp)
		f:i32(8)
		f:call(nthtmp)
		f:i32(4)
		f:call(nthtmp)
		f:call(tblset)

		f:call(tmppop)
		f:call(tmppop)
		f:br(scopes.nop)
	end, 11, 'tbladd', function(scopes)
		readArg()
		f:i64extendu()
		f:call(newi64)
		f:store(c)

		-- s[-2][c] = s[-1]
		f:i32(8)
		f:call(nthtmp)
		f:load(c)
		f:i32(4)
		f:call(nthtmp)
		f:call(tblset)

		f:call(tmppop)
		f:br(scopes.nop)
	end, 12, 'ret', function(scopes)
	-- pop stack frame
		f:br(scopes.nop)
	end, 13, 'call', function(scopes)
	-- push stack frame header
		f:br(scopes.nop)
	end, 14, 'retcall', function(scopes)
	-- pop stack frame, then call
		f:br(scopes.nop)
	end, 15, 'loadconst', function(scopes)
		f:load(objbase)
		f:i32load(objframe.const)
		readArg()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, 16, 'loadlocal', function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load(dataframe.locals)
		f:load(base)
		f:add()
		readArg()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, 17, 'storelocal', function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load(dataframe.locals)
		f:load(base)
		f:add()
		readArg()
		f:add()
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
		f:br(scopes.nop)
	end, 32, 'loadparam', function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg()
		f:add()
		f:i32load(vec.base)
		f:call(tmppush)
		f:br(scopes.nop)
	end, 33, 'storeparam', function(scopes)
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:i32load(buf.ptr)
		f:load(base)
		f:add()
		readArg()
		f:add()
		f:i32(4)
		f:call(nthtmp)
		f:i32store(vec.base)
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
						f:i32(4)
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
							f:i32(4)
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
	end, 30, 'loadvarg', function(scopes)
		f:i32(0)
		f:store(a)
		readArg()
		f:i32(2)
		f:shl()
		f:store(b)
		f:loop(function(loop)
			-- TODO handle nils when b > dotdotdot.len
			f:load(a)
			f:load(b)
			f:eq()
			f:brif(scopes.nop)

			f:load(framebase)
			f:i32load16u(dataframe.dotdotdot)
			f:load(base)
			f:add()
			f:loadg(oluastack)
			f:i32load(coro.stack)
			f:i32load(buf.ptr)
			f:add()
			f:load(a)
			f:add()
			f:i32load(vec.base)
			f:call(tmppush)

			f:load(a)
			f:i32(4)
			f:add()
			f:store(a)
			f:br(loop)
		end)
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
		-- TODO fill in nils when paramc > metaparamc
		-- d is func
		-- push objframe
		-- a, c, e = stack.len, localc*4, paramc*4
		f:loadg(oluastack)
		f:i32load(coro.stack)
		f:tee(b)
		f:i32load(buf.len)
		f:tee(a)
		f:load(meta_retb)
		f:sub()
		f:store(base)

		f:load(b)
		f:i32(objframe.sizeof)
		f:load(d)
		f:i32load(functy.localc)
		f:i32(2)
		f:shl()
		f:tee(b)
		f:add()
		f:load(d)
		f:i32load(functy.paramc)
		f:i32(2)
		f:shl()
		f:tee(e)
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

		f:load(d)
		f:i32load(functy.paramc)

		-- push dataframe
		f:loadg(oluastack)
		f:i32load(coro.data)
		f:i32(dataframe.sizeof)
		f:call(extendstr)

		-- write dataframe
		f:tee(framebase)
		f:i32load(buf.ptr)
		f:load(framebase)
		f:i32load(buf.len)
		f:add()
		f:i32(dataframe.sizeof)
		f:sub()
		f:tee(framebase)
		f:load(meta_callty)
		f:i32store8(dataframe.type)

		f:load(framebase)
		f:i32(0)
		f:i32store(dataframe.pc)

		f:load(framebase)
		f:load(base)
		f:i32store(dataframe.base)

		f:load(framebase)
		f:load(e)
		f:i32store16(dataframe.dotdotdot)

		f:load(framebase)
		f:i32(0)
		f:i32store16(dataframe.retb)

		f:load(framebase)
		f:load(meta_retc)
		f:i32store16(dataframe.retc)

		f:load(framebase)
		f:load(a)
		f:load(base)
		f:sub()
		f:tee(a)
		f:i32store16(dataframe.locals)

		f:load(framebase)
		f:load(a)
		f:load(c)
		f:add()
		f:i32store16(dataframe.frame)

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
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
	f:load(pc)
	f:i32store(dataframe.pc)

	f:i32(0)
end))
