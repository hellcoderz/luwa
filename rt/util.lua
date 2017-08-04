chex = func(i32, i32, function(f, ch)
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
		f:iff(function()
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

pushstr = func(i32, i32, i32, function(f, dst, ch)
	local s, cap, len = f:locals(i32, 3)
	f:load(dst)
	f:load(dst)
	f:i32load(buf.len)
	f:tee(len)
	f:i32(1)
	f:add()
	f:i32store(buf.len)

	f:load(dst)
	f:i32load(buf.ptr)
	f:tee(s)
	f:i32load(str.len)
	f:tee(cap)
	f:load(len)
	f:eq()
	f:iff(function()
		f:load(dst)
		f:storeg(otmp)

		f:load(cap)
		f:load(cap)
		f:add()
		f:tee(cap)
		f:call(newstr)
		f:tee(s)
		f:loadg(otmp)
		f:tee(dst)
		f:i32load(buf.ptr)
		f:load(len)
		f:i32(13)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(str.len)

		f:load(dst)
		f:load(s)
		f:i32store(buf.ptr)
	end)

	f:load(s)
	f:load(len)
	f:add()
	f:load(ch)
	f:i32store8(str.base)

	f:load(dst)
end)

pushvec = func(i32, i32, i32, function(f, dst, o)
	local s, cap, len = f:locals(i32, 3)
	f:load(dst)
	f:load(dst)
	f:i32load(buf.len)
	f:tee(len)
	f:i32(4)
	f:add()
	f:tee(cap)
	f:i32store(buf.len)

	f:load(dst)
	f:i32load(buf.ptr)
	f:tee(s)
	f:load(len)
	f:add()
	f:load(o)
	f:i32store(vec.base)

	f:load(cap)
	f:load(s)
	f:i32load(vec.len)
	f:tee(cap)
	f:eq()
	f:iff(function()
		f:load(dst)
		f:storeg(otmp)

		f:load(cap)
		f:load(cap)
		f:add()
		f:tee(cap)
		f:call(newvec)
		f:tee(s)
		f:loadg(otmp)
		f:tee(dst)
		f:i32load(buf.ptr)
		f:load(len)
		f:i32(9)
		f:add()
		f:call(memcpy8)

		f:load(s)
		f:load(cap)
		f:i32store(vec.len)

		f:load(dst)
		f:load(s)
		f:i32store(buf.ptr)

	end)
	f:load(dst)
end)

popvec = func(i32, i32, function(f, box)
	local len = f:locals(i32)
	f:load(box)
	f:load(box)
	f:i32load(buf.len)
	f:i32(4)
	f:sub()
	f:tee(len)
	f:i32store(buf.len)

	f:load(box)
	f:i32load(buf.ptr)
	f:load(len)
	f:add()
	f:tee(len)
	f:i32load(vec.base)
	f:load(len)
	f:i32(NIL)
	f:i32store(vec.base)
end)

peekvec = func(i32, i32, i32, function(f, box, n)
	local len = f:locals(i32)
	f:load(box)
	f:i32load(buf.ptr)
	f:load(box)
	f:i32load(buf.len)
	f:load(n)
	f:sub()
	f:add()
	f:i32load(vec.base)
end)

function loadvecminus(f, x)
	if x >= vec.base then
		f:i32load(vec.base - x)
	else
		f:i32(x)
		f:sub()
		f:i32load(vec.base)
	end
end
function loadstrminus(f, x, meth)
	if not meth then
		meth = 'i32load'
	end
	if x >= str.base then
		f[meth](f, str.base - x)
	else
		f:i32(x)
		f:sub()
		f[meth](f, str.base)
	end
end

local mkhole = func(i32, i32, void, function(f, start, len)
	f:load(len)
	f:eqz()
	f:brif(f)

	f:load(len)
	f:i32(15)
	f:band()
	f:iff(function()
		f:load(start)
		f:i32(otypes['nil'])
		f:i32store8(obj.type)
		f:load(start)
		f:i32(8)
		f:add()
		f:store(start)
		f:load(len)
		f:i32(8)
		f:sub()
		f:tee(len)
		f:eqz()
		f:brif(f)
	end)
	f:load(start)
	f:i32(otypes.str)
	f:i32store8(str.type)
	f:load(start)
	f:load(len)
	f:i32(13)
	f:sub()
	f:i32store(str.len)
end)

local function gentrunc(ty)
	return func(i32, i32, void, function(f, x, len)
		local oldsz, newsz = f:locals(i32, 2)
		f:load(x)
		f:call(sizeof)
		f:store(oldsz)

		f:load(x)
		f:load(len)
		f:i32store(ty.len)

		f:load(x)
		f:load(len)
		f:i32(ty.base)
		f:add()
		f:call(allocsize)
		f:tee(newsz)
		f:add()
		f:load(oldsz)
		f:load(newsz)
		f:sub()
		f:call(mkhole)
	end)
end

truncvec = gentrunc(vec)
truncstr = gentrunc(str)

local function genunbuf(truncfunc)
	return func(i32, i32, function(f, box)
		local x = f:locals(i32)
		f:load(box)
		f:i32load(buf.ptr)
		f:tee(x)
		f:load(box)
		f:i32load(buf.len)
		f:call(truncfunc)
		f:load(x)
	end)
end

unbufstr = genunbuf(truncstr)
unbufvec = genunbuf(truncvec)

memcpy1rl = func(i32, i32, i32, void, function(f, dst, src, len)
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

memcpy8 = func(i32, i32, i32, void, function(f, dst, src, len)
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
-- TODO return on datastack?
frexp = func(f64, f64, function(f, x)
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
			f:i32(4)
			f:call(nthtmp)
			f:i64load(num.val)
			f:i64(64)
			f:sub()
			f:call(newi64)
			f:i32(4)
			f:call(setnthtmp)
		end, function()
			f:load(x)
		end)
	end)
end)
