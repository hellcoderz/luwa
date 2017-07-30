gccollect = func(function(f)
	local freetip, livetip, sz, n, m = f:locals(i32, 5)
	f:loadg(markbit)
	f:eqz()
	f:storeg(markbit)

	-- Phase0 marking phase
	f:i32(NIL)
	f:call(gcmark)
	f:i32(FALSE)
	f:call(gcmark)
	f:i32(TRUE)
	f:call(gcmark)
	f:loadg(otmp)
	f:call(gcmark)
	f:loadg(otmpstack)
	f:call(gcmark)
	f:loadg(odatastack)
	f:call(gcmark)

	f:call(igcmark)

	-- Phase1 set reloc pointers
	f:loadg(markbit)
	f:store(freetip)

	f:loop(function(loop)
		f:load(livetip)
		f:call(sizeof)
		f:store(sz)

		f:load(livetip)
		f:i32load(obj.gc)
		f:loadg(markbit)
		f:eq()
		f:iff(function()
			f:load(livetip)
			f:load(freetip)
			f:i32store(obj.gc)

			f:load(freetip)
			f:load(sz)
			f:add()
			f:store(freetip)
		end)

		f:load(livetip)
		f:load(sz)
		f:add()
		f:tee(livetip)
		f:loadg(heaptip)
		f:ne()
		f:brif(loop)
	end)

	-- Phase2 fix reloc pointers
	f:loadg(otmp)
	f:i32load(obj.gc)
	f:i32(-8)
	f:band()
	f:storeg(otmp)

	f:loadg(otmpstack)
	f:i32load(obj.gc)
	f:i32(-8)
	f:band()
	f:storeg(otmpstack)

	f:loadg(odatastack)
	f:i32load(obj.gc)
	f:i32(-8)
	f:band()
	f:storeg(odatastack)

	f:i32(0)
	f:store(livetip)
	f:loop(function()
		f:load(livetip)
		f:call(sizeof) 
		f:store(sz)

		f:load(livetip)
		f:i32load(obj.gc)
		f:i32(1)
		f:band()
		f:loadg(markbit)
		f:eq()
		f:iff(function(terminal)
			f:block(function(buf)
				f:block(function(vec)
					f:block(function(table)
						f:load(livetip)
						f:i32load8u(obj.type)
						f:brtable(terminal, terminal, terminal, terminal, table, terminal, vec, buf)
					end) -- table
					f:load(livetip)
					f:load(livetip)
					f:i32load(tbl.arr)
					f:i32load(obj.gc)
					f:i32(-8)
					f:band()
					f:i32store(tbl.arr)
					f:load(livetip)
					f:load(livetip)
					f:i32load(tbl.hash)
					f:i32load(obj.gc)
					f:i32(-8)
					f:band()
					f:i32store(tbl.hash)
					f:load(livetip)
					f:load(livetip)
					f:i32load(tbl.meta)
					f:i32load(obj.gc)
					f:i32(-8)
					f:band()
					f:i32store(tbl.meta)
					f:br(terminal)
				end) -- vec
				f:load(livetip)
				f:tee(n)
				f:load(livetip)
				f:i32load(vec.len)
				f:add()
				f:store(m)
				f:loop(function(loop)
					f:load(n)
					f:load(m)
					f:eq()
					f:brif(1)

					f:load(n)
					f:load(n)
					f:i32load(vec.base)
					f:i32load(obj.gc)
					f:i32(-8)
					f:band()
					f:i32store(vec.base)

					f:load(n)
					f:i32(4)
					f:add()
					f:store(n)

					f:br(loop)
				end)
				f:br(terminal)
			end) -- buf
			f:load(livetip)
			f:load(livetip)
			f:i32load(buf.ptr)
			f:i32load(obj.gc)
			f:i32(-8)
			f:band()
			f:i32store(buf.ptr)
			f:br(terminal)
		end)

		f:load(livetip)
		f:load(sz)
		f:add()
		f:tee(livetip)
		f:loadg(heaptip)
		f:ne()
		f:brif(0)
	end)

	f:call(igcfix)

	-- Phase3 move it
	f:i32(0)
	f:store(livetip)
	f:block(function()
		f:block(function(foundshift)
		f:loop(function(loop)
			f:load(livetip)
			f:call(sizeof)
			f:store(sz)

			f:load(livetip)
			f:i32load(obj.gc)
			f:i32(1)
			f:band()
			f:loadg(markbit)
			f:eq()
			f:iff(function()
				f:load(livetip)
				f:load(livetip)
				f:i32load(obj.gc)
				f:i32(-8)
				f:band()
				f:tee(n)
				f:ne()
				f:brif(foundshift)
			end)

			f:load(livetip)
			f:load(sz)
			f:add()
			f:tee(livetip)
			f:loadg(heaptip)
			f:eq()
			f:brtable(loop, f)
		end)
		end)

		f:load(n)
		f:load(livetip)
		f:load(sz)
		f:call(memcpy8)

		f:load(livetip)
		f:load(sz)
		f:add()
		f:tee(livetip)
		f:loadg(heaptip)
		f:ne()
		f:iff(function(blif)
			f:loop(function(loop)
				f:load(livetip)
				f:call(sizeof)
				f:store(sz)

				f:load(livetip)
				f:i32load(obj.gc)
				f:i32(1)
				f:band()
				f:loadg(markbit)
				f:eq()
				f:iff(function()
					f:load(livetip)
					f:i32load(obj.gc)
					f:i32(-8)
					f:band()
					f:load(livetip)
					f:load(sz)
					f:call(memcpy8)
				end)

				f:load(livetip)
				f:load(sz)
				f:add()
				f:tee(livetip)
				f:loadg(heaptip)
				f:eq()
				f:brtable(loop, blif)
			end)
		end)

		f:load(freetip)
		f:i32(-8)
		f:band()
		f:storeg(heaptip)
	end)
end)

gcmark = export('gcmark', func(i32, void, function(f, o)
	local m = f:locals(i32)
	-- check liveness bit
	f:load(o)
	f:i32load(obj.gc)
	f:i32(1)
	f:band()
	f:loadg(markbit)
	f:ne()
	f:iff(function()
		f:load(o)
		f:loadg(markbit)
		f:i32store(obj.gc)

		f:block(function(buf)
			f:block(function(vec)
				f:block(function(table)
					f:load(o)
					f:i32load8u(obj.type)
					f:brtable(gcmark, gcmark, gcmark, gcmark, table, gcmark, vec, buf)
				end) -- table
				f:load(o)
				f:i32load(tbl.arr)
				f:call(gcmark)
				f:load(o)
				f:i32load(tbl.hash)
				f:call(gcmark)
				f:load(o)
				f:i32load(tbl.meta)
				f:call(gcmark)
				f:ret()
			end) -- vec
			f:load(o)
			f:load(o)
			f:i32load(vec.len)
			f:add()
			f:store(m)
			f:loop(function(loop)
				f:load(o)
				f:load(m)
				f:eq()
				f:brif(f)

				f:load(o)
				f:i32load(vec.base)
				f:call(gcmark)

				f:load(o)
				f:i32(4)
				f:add()
				f:store(o)

				f:br(loop)
			end)
			f:ret()
		end)
		f:load(o)
		f:i32load(buf.ptr)
		f:call(gcmark)
	end)
end))
