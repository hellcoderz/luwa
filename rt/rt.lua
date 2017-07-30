NIL = 0
TRUE = 8
FALSE = 16
HEAPBASE = 24
otmp = global(i32, true)
otmpstack = global(i32, true, HEAPBASE)
otmpstacklen = global(i32, true)
odatastack = global(i32, true, HEAPBASE + 48) -- 48 == allocsize(vec.base + 32)
odatastacklen = global(i32, true)
heaptip = global(i32, true, HEAPBASE + 48 + 48) -- 48 + 48 == allocsize(vec.base + 32) + allocsize(str.base + 32)
markbit = global(i32, true)

memory = importmemory('', 'm', 1)

data(memory, 4, {
	-- nil
	2, 0, 0, 0,
	-- false
	0, 0, 0, 0, 3, 0, 0 ,0,
	-- true
	0, 0, 0, 0, 3, 1, 0, 0,
	-- otmpstack = vec(32)
	0, 0, 0, 0, 6, 32, -- 35 zeroes
})
data(memory, HEAPBASE + 48 + 4, {
	5, 32, -- 35 zeroes
})

igcfix = importfunc('', 'gcfix')
igcmark = importfunc('', 'gcmark')
echo = importfunc('', 'echo', i32, i32)

echodrop = func(i32, void, function(f, x)
	f:load(x)
	f:call(echo)
	f:drop()
end)

echodrop2 = func(i32, i32, i32, function(f, x, y)
	f:load(x)
	f:load(y)
	f:call(echodrop)
	f:call(echo)
end)
