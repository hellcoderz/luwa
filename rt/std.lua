chex = func(i32, function(f)
	local ch = f:params(i32)
	f:load(ch)
	f:i32(48)
	f:sub()
	f:tee(ch)
	f:i32(10)
	f:ltu()
	f:iff(i32, function()
		f:load(ch)
	end, function()
		f:load(ch)
		f:i32(17)
		f:sub()
		f:tee(ch)
		f:i32(6)
		f:geu()
		f:iff (function()
			f:i32(-1)
			f:load(ch)
			f:i32(32)
			f:sub()
			f:tee(ch)
			f:i32(6)
			f:geu()
			f:brif(f)
			f:drop()
		end)
		f:load(ch)
		f:i32(10)
		f:add()
	end)
end)

pushstr = func(i32, function(f)
	local ch, tmpid, len = f:params(i32, i32, i32)
	local s, cap, l1 = f:locals(i32, 3)
	f:load(len)
	f:i32(1)
	f:add()
	f:tee(l1)
	f:load(tmpid)
	f:call(nthtmp)
	f:tee(s)
	f:i32load(str.len)
	f:tee(cap)
	f:eq()
	f:iff (function()
		f:load(cap)
		f:load(cap)
		f:add()
		f:tee(cap)
		f:call(newstr)
		f:load(tmpid)
		f:call(nthtmp)
		f:tee(s)
		f:load(len)
		f:i32(13)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(str.len)

		f:load(s)
		f:load(tmpid)
		f:call(setnthtmp)
	end)

	f:load(s)
	f:load(len)
	f:add()
	f:load(ch)
	f:i32store8(str.base)
	f:load(l1)
end)

pushvec = func(i32, function(f)
	local o, tmpid, len = f:params(i32, i32, i32)
	local v, cap, l1 = f:locals(i32, 3)
	f:load(len)
	f:i32(4)
	f:add()
	f:tee(l1)
	f:load(tmpid)
	f:call(nthtmp)
	f:tee(v)
	f:i32load(vec.len)
	f:tee(cap)
	f:eq()
	f:iff(function()
		f:load(o)
		f:storeg(otmp)

		f:load(cap)
		f:load(cap)
		f:add()
		f:tee(cap)
		f:call(newvec)
		f:load(tmpid)
		f:call(nthtmp)
		f:tee(v)
		f:load(len)
		f:i32(9)
		f:add()
		f:call(memcpy8)

		f:load(v)
		f:load(cap)
		f:i32store(vec.len)

		f:load(v)
		f:load(tmpid)
		f:call(setnthtmp)

		f:loadg(otmp)
		f:store(o)
	end)

	f:load(v)
	f:load(len)
	f:add()
	f:load(o)
	f:i32store(vec.base)
	f:load(l1)
end)

memcpy1rl = func(function(f)
	local dst, src, len = f:params(i32, i32, i32)
	f:loop(function(loop)
		f:load(len)
		f:eqz()
		f:brif(f)

		f:load(dst)
		f:load(len)
		f:i32(1)
		f:sub()
		f:tee(len)
		f:add()
		f:load(src)
		f:load(len)
		f:add()
		f:i32load8u()
		f:i32store8()

		f:br(loop)
	end)
end)

memcpy8 = func(function(f)
	local dst, src, len = f:params(i32, i32, i32)
	local n = f:locals(i32)
	f:loop(function(loop)
		f:load(n)
		f:load(len)
		f:geu()
		f:brif(f)

		f:load(dst)
		f:load(n)
		f:add()
		f:load(src)
		f:load(n)
		f:add()
		f:i64load()
		f:i64store()

		f:load(n)
		f:i32(8)
		f:add()
		f:store(n)

		f:br(loop)
	end)
end)

-- returns exponent on otmpstack
frexp = func(f64, function(f)
	local x = f:params(f64)
	local xi, ee = f:locals(i64, 2)
	f:load(x)
	f:i64reinterpret()
	f:tee(xi)
	f:i64(23)
	f:shru()
	f:i64(0xff)
	f:band()
	f:tee(ee)
	f:eqz()
	f:eqz()
	f:iff(f64, function()
		f:load(x)
		f:load(ee)
		f:i64(0x7ff)
		f:eq()
		f:brif(f)
		f:drop()

		f:load(ee)
		f:i64(0x3fe)
		f:sub()
		f:call(newi64)
		f:call(tmppush)

		f:load(xi)
		f:i64(0x800fffffffffffff)
		f:band()
		f:i64(0x3fe0000000000000)
		f:bor()
		f:f64reinterpret()
	end, function()
		f:load(x)
		f:f64(0)
		f:eq()
		f:iff(f64, function()
			f:load(x)
			f:f64(0x1p64)
			f:mul()
			f:call(frexp)
			f:i32(1)
			f:call(nthtmp)
			f:i64load(num.val)
			f:i64(64)
			f:sub()
			f:call(newi64)
			f:i32(1)
			f:call(setnthtmp)
		end, function()
			f:load(x)
		end)
	end)
end)

math_frexp = export("math_frexp", func(i32, function(f)
	-- TODO come up with a DRY type checking strategy
	f:i32(1)
	f:call(nthtmp)
	f:f64load(num.val)
	f:call(frexp)
	-- Replace param x with ret of frexp
	-- 2nd retval is already in place
	f:call(newf64)
	f:i32(2)
	f:call(setnthtmp)
	f:i32(0)
end))
