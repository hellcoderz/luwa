tmppush = export('tmppush', func(i32, void, function(f, o)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(o)
	f:call(pushvec)
	f:drop()
end))

tmppop = export('tmppop', func(function(f)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:call(popvec)
	f:drop()
end))

nthtmp = export('nthtmp', func(i32, i32, function(f, i)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(i)
	f:call(nthbuf)
end))

setnthtmp = export('setnthtmp', func(i32, i32, void, function(f, nv, i)
	f:load(nv)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(i)
	f:call(setnthbuf)
end))

extendtmp = func(i32, void, function(f, amt)
	f:loadg(oluastack)
	f:i32load(coro.stack)
	f:load(amt)
	f:call(extendvec)
	f:drop()
end)

endofbuf = func(i32, i32, function(f, b)
	f:load(b)
	f:i32load(buf.ptr)
	f:load(b)
	f:i32load(buf.len)
	f:add()
end)

nthbuf = func(i32, i32, i32, function(f, v, n)
	f:load(v)
	f:i32load(buf.ptr)
	f:load(v)
	f:i32load(buf.len)
	f:load(n)
	f:sub()
	f:add()
	f:i32load(vec.base)
end)

setnthbuf = func(i32, i32, i32, void, function(f, o, v, n)
	f:load(v)
	f:i32load(buf.ptr)
	f:load(v)
	f:i32load(buf.len)
	f:load(n)
	f:sub()
	f:add()
	f:load(o)
	f:i32store(vec.base)
end)
