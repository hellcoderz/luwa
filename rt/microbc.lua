local alloc = require 'alloc'
local types = alloc.types
local mtypes = {}
local mops = {}
local ops = {}

local function out(ast)
	if not ast.arg then
		local mop = mops[ast.op]
		local sig = mop.sig
		local sigty = type(sig)
		if sigty == 'function' then
			sig = sig(ast)
		end
		ast.arg = sig.arg
		ast.out = sig.out
	end
	return ast.out
end
local function verify(mop)
	local arg = mop.arg
	if not arg then
		assert(#mop == 0, 'Argless constructor received args')
	end
	for i=1,#arg do
		local a = arg[i]
		if a ~= 'atom' then
			assert(out(mop[i]) == a, 'Constructor arg type mismatch')
		end
	end
end
local function mkMop(op, sig)
	local id = #mops+1
	mops[id] = op
	mops[op] = id
	if type(sig) == 'table' then
		return function(...)
			local node = { op = id, ... }
			for k,v in pairs(sig) do
				node[k] = v
			end
			verify(node)
			return node
		end
	else
		return function(...)
			local node = { op = id, ... }
			local meta = sig(node)
			for k,v in pairs(meta) do
				node[k] = v
			end
			verify(node)
			return node
		end
	end
end
local function mkOp(op, f)
	ops[op] = f
end
local function GenericUnOp(args)
	assert(#args == 1, 'GenericUnOp: expects 1 param')
	local _a = out(args[1])
	return {
		arg = { _a },
		out = _a,
	}
end
local function GenericBinOp(args)
	assert(#args == 2, 'GenericBinOp: expects 2 params')
	local _a, _b = out(args[1]), out(args[2])
	assert(_a == _b, 'GenericBinOp: received mixed types')
	return {
		arg = { _a, _b },
		out = _a,
	}
end
local Nop = mkMop('Nop', {})
local Seq = mkMop('Seq', function(args)
	arg = {}
	for i=1,#args-1 do
		arg[i] = out(arg[i])
	end
	return {
		arg = arg,
		out = out(args[#args]),
	}
end)
local Void = mkMop('Void', function(args)
	assert(#args == 1, 'Void expects 1 param')
	return {
		arg = {out(args[1])}
	}
end)
local Int = mkMop('Int', {
	arg = {'atom'},
	out = 'i32',
})
local Int64 = mkMop('Int64', {
	arg = {'atom'},
	out = 'i64',
})
local Flt = mkMop('Flt', {
	arg = {'atom'},
	out = 'f32',
})
local Flt64 = mkMop('Flt64', {
	arg = {'atom'},
	out = 'f64',
})
local Str = mkMop('Str', {
	arg = {'atom'},
	out = 'obj',
})
local ToString = mkMop('ToString', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local Load = mkMop('Load', {
	arg = {'i32', 'atom'},
	out = 'i32',
})
local LoadInt = mkMop('LoadInt', {
	arg = {'obj'},
	out = 'i64',
})
local LoadFlt = mkMop('LoadFlt', {
	arg = {'obj'},
	out = 'f64',
})
local Free = mkMop('Free', {
	arg = {'i32'},
	out = 'obj',
})
local Const = mkMop('Const', {
	arg = {'i32'},
	out = 'i32',
})
local Local = mkMop('Local', {
	arg = {'i32'},
	out = 'i32',
})
local Param = mkMop('Param', {
	arg = {'i32'},
	out = 'i32',
})
local Store = mkMop('Store', {
	arg = { 'i32', 'i32' },
})
local Reg32 = mkMop('Reg32', {
	out = 'r32',
})
local LoadReg = mkMop('LoadReg', {
	arg = { 'r32' },
	out =  'i32' 
})
local StoreReg = mkMop('StoreReg', {
	arg = { 'r32', 'i32' }
})
local Eq = mkMop('Eq', GenericBinOp)
local Lt = mkMop('Lt', GenericBinOp)
local Le = mkMop('Le', GenericBinOp)
local Ge = mkMop('Ge', GenericBinOp)
local Gt = mkMop('Gt', GenericBinOp)
local Add = mkMop('Add', GenericBinOp)
local Sub = mkMop('Sub', GenericBinOp)
local Mul = mkMop('Mul', GenericBinOp)
local Div = mkMop('Div', GenericBinOp)
local BAnd = mkMop('BAnd', GenericBinOp)
local BOr = mkMop('BOr', GenericBinOp)
local BXor = mkMop('BXor', GenericBinOp)
local Negate = mkMop('Negate', GenericUnOp)
local Or = mkMop('Or', {
	arg = {'i32', 'i32'},
	out = 'i32',
})
local And = mkMop('And', {
	arg = {'i32', 'i32'},
	out = 'i32',
})
local NegateInt = mkMop('NegateInt', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local NegateFloat = mkMop('NegateFloat', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local StrConcat = mkMop('StrConcat', {
	alloc = true,
	arg = {'obj','obj'},
	out = 'obj',
})
-- TODO need to work out concept of 'deferred' block in arg sig
-- ie we're mixing up idea of input vs argument
local If = mkMop('If', function(args)
	local _then, _else = out(args[2]), args[3] and out(args[3])
	assert(_then == _else, "If's branches with unequal type")
	assert(#_then < 2, "If's branches have excess results")
	return {
		arg = { 'i32', _then, _else },
		out = _then,
	}
end)
local ForRange = mkMop('ForRange', {
	arg = { 'r32', 'i32', 'i32', nil }
})
local Arg = mkMop('Arg', {
	arg = { 'atom' },
	out =  'i32' ,
})
local Push = mkMop('Push', {
	arg = {'obj'},
})
local Pop = mkMop('Pop', {
	arg = {},
	out = 'obj',
})
local Peek = mkMop('Peek', {
	arg = {},
	out = 'obj',
})
local SetPc = mkMop('SetPc', {
	exit = true,
	arg = {'i32'},
})
local Truthy = mkMop('Truthy', {
	arg = {'obj'},
	out = 'i32',
})
local Box = mkMop('Box', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local CloneFunc = mkMop('CloneFunc', {
	alloc = true,
	arg = {'obj'},
	out = 'obj',
})
local ObjMetalessEq = mkMop('ObjMetalessEq', {
	arg = {'obj', 'obj'},
	out = 'i32',
})
local IntObjFromInt = mkMop('IntObjFromInt', {
	alloc = true,
	arg = {'i32'},
	out = 'obj',
})
local IntObjFromInt64 = mkMop('IntObjFromInt64', {
	alloc = true,
	arg = {'i64'},
	out = 'obj',
})
local FltObjFromFlt = mkMop('FltObjFromFlt', {
	alloc = true,
	arg = {'f64'},
	out = 'obj',
})
local LoadStrLen = mkMop('LoadStrLen', {
	arg = {'obj'},
	out = 'i32',
})
local Error = mkMop('Error', {
	alloc = true,
})
local Syscall = mkMop('Syscall', {
	alloc = true,
	arg = {'i32'},
})
local Int64Flt = mkMop('Int64Flt', {
	arg = {'i64'},
	out = 'f64',
})
local FltInt64 = mkMop('Flt64Int', {
	arg = {'f64'},
	out = 'i64',
})
local Meta = mkMop('Meta', {
	arg = {'obj'},
	out = 'obj',
})
local Type = mkMop('Type', {
	arg = {'obj'},
	out = 'i32',
})
local IsTbl = mkMop('IsTbl', {
	arg = {'obj'},
	out = 'i32',
})
local IsNumOrStr = mkMop('IsNumOrStr', {
	arg = {'obj'},
	out = 'i32',
})
local TblGet = mkMop('TblGet', {
	arg = {'obj', 'obj'},
	out = 'obj',
})
local TblSet = mkMop('TblSet', {
	alloc = true,
	arg = {'obj', 'obj', 'obj'},
})
local LoadTblLen = mkMop('LoadTblLen', {
	arg = {'obj'},
	out = 'i32',
})
local LoadFuncParamc = mkMop('LoadFuncParamc', {
	arg = {'obj'},
	out = 'i32',
})
local NewVec = mkMop('NewVec', {
	alloc = true,
	arg = {'i32'},
	out = 'obj',
})
local function CallSignature(args)
	local arg = {}
	for i=1,#args do
		arg[i] = 'obj'
	end
	return { arg = arg }
end
local function CallMetaSignature(args)
	local arg = { 'atom' }
	for i=2,#args do
		arg[i] = 'obj'
	end
	return { arg = arg }
end
local CallMetaMethod = mkMop('CallMetaMethod', CallMetaSignature)
local CallBinMetaMethod = mkMop('CallBinMetaMethod', CallMetaSignature)
local CallBool = mkMop('CallBool', CallSignature)
local FillRange = mkMop('FillRange', {
	arg = {'i32', 'obj', 'i32'},
})
local MemCpy4 = mkMop('MemCpy4', {
	arg = {'i32', 'i32', 'i32'},
})
local VargLen = mkMop('VargLen', {
	arg = {},
	out = 'i32',
})
local VargPtr = mkMop('VargPtr', {
	arg = {},
	out = 'i32',
})
-- AllocateTemp's result should not live through an allocation barrier
local AllocateTemp = mkMop('AllocateTemp', {
	arg = {'i32'},
	out = 'i32',
})
-- TODO AllocateDataFrames
local Typeck = mkMop('Typeck', function(args)
	local a1 = args[1]
	local alen = #args
	assert(type(a1) == 'number' and a1>0, 'Typeck expects first param to be a positive number')
	local arg = {'atom'}
	for i=2,a1+1 do
		arg[i] = 'obj'
	end
	local hasDefault = (alen - 1) % (a1 + 1) == 0
	local out = out(args[#args])
	assert(hasDefault or not out, 'Typeck without default expects no out type')
	for i=a1+2,alen,a1+1 do
		arg[#arg+1] = out
		if i ~= alen then
			for j=0,a1-1 do
				assert(type(args[i+j]) == 'number', 'Typeck expects type ids')
			end
		end
	end
	return {
		arg = arg,
		out = out,
	}
end)
-- TODO WriteDataFrame
local FillFromStack = mkMop('FillFromStack', {
	arg = {'obj', 'i32'},
})
local function Nil() return Int(0) end
local function False() return Int(4) end
local function True() return Int(8) end
mkOp(bc.Nop, Nop())
mkOp(bc.LoadNil, Push(Nil()))
mkOp(bc.LoadFalse, Push(False()))
mkOp(bc.LoadTrue, Push(True()))
mkOp(bc.LoadParam, Push(Load(Param(Arg(0)))))
mkOp(bc.StoreParam, Store(Param(Arg(0)), Pop()))
mkOp(bc.LoadLocal, Push(Load(Local(Arg(0)))))
mkOp(bc.StoreLocal, Store(Local(Arg(0)), Pop()))
mkOp(bc.LoadFree, Push(Load(Free(Arg(0)))))
mkOp(bc.LoadFreeBox, Push(Load(Load(Free(Arg(0))))))
mkOp(bc.StoreFreeBox, Store(Load(Free(Arg(0))), Pop()))
mkOp(bc.LoadParamBox, Push(Load(Load(Param(Arg(0))))))
mkOp(bc.StoreParamBox, Store(Load(Param(Arg(0))), Pop()))
mkOp(bc.BoxParam, Store(Param(0), Box(Param(Arg(0)))))
mkOp(bc.BoxLocal, Store(Local(0), Box(Nil())))
mkOp(bc.LoadLocalBox, Push(Load(Load(Local(Arg(0)), vec.base))))
mkOp(bc.StoreLocalBox, Store(Load(Local(Arg(0)), vec.base), Pop()))
mkOp(bc.LoadConst, Push(Load(Const(Arg(0)), vec.base)))
mkOp(bc.Pop, Pop())
mkOp(bc.Syscall, Syscall(Arg(0)))
mkOp(bc.Jmp, SetPc(Arg(0)))
mkOp(bc.JifNot,
	If(
		Truthy(Pop()),
		SetPc(Arg(0))
	)
)
mkOp(bc.Jif,
	IfNot(
		Truthy(Pop()),
		SetPc(Arg(0))
	)
)
mkOp(bc.JifNotOrPop,
	If(
		Truthy(Peek()),
		SetPc(Arg(0)),
		Pop()
	)
)
mkOp(bc.JifOrPop,
	If(
		Truthy(Peek()),
		Pop(),
		SetPc(Arg(0))
	)
)
mkOp(bc.LoadFunc, (function()
	local func = CloneFunc(Const(Arg(1)))
	return Seq(
		func,
		If(
			Arg(0),
			Store(
				Add(func, Int(functy.frees)),
				FillFromStack(NewVec(Arg(0)), Arg(0))
			)
		),
		Push(func)
	)
end)())
mkOp(bc.LoadVarg, (function()
	local tmp = AllocateTemp(Arg(0))
	local vlen = VargLen()
	local vptr = VargPtr()
	return Seq(vptr,
		If(
			Lt(vlen, Arg(0)),
			function(f)
				local vlen4 = Mul(vlen, Int(4))
				return Seq(
					MemCpy4(tmp, vptr, vlen4),
					FillRange(Add(tmp, vlen4), Nil(), Mul(Sub(Arg(0), vlen), Int(4)))
				)
			end,
			MemCpy4(tmp, vptr, Mul(Arg(0), Int(4)))
		)
	)
end)())
mkOp(bc.AppendVarg, AppendRange(Pop(), VargPtr(), Arg(0)))
mkOp(bc.Call, (function()
	local nret = Arg(0)
	local baseframe = DataFrameTop()
	local rollingbase = Reg32()
	local ri = Reg32()
	local n0 = StoreReg(rollingbase, DataFrameTopBase())
	local n1 = AllocateDataFrames(Arg(1))
	-- TODO StoreName 'func'
	local n2 = ForRange(ri, Int(0), Arg(1), (function()
		local rival = LoadReg(ri)
		local newrollingbase = Add(LoadReg(rollingbase), Mul(LoadArg(rival), Int(4)))
		return Seq(
			StoreReg(rollingbase, newrollingbase),
			WriteDataFrame(
				Add(baseframe, rival),
				If(rival, Int(3), Int(1)), -- type = i ? call : norm
				Int(0), -- pc
				newrollingbase, -- base
				Mul(LoadFuncParamc(func), Int(4)), -- dotdotdot
				Int(-4), -- retb
				Int(-1), -- retc
				0, --  TODO calc locals
				0 -- TODO calc frame
			)
		)
	end)())
	local n3 = PushObjFrameFromFunc(func)
	local n4 = SetPc(Int(0))
	return Seq(n0, n1, n2, n3, n4)
end)())
mkOp(bc.ReturnCall, Nop())
mkOp(bc.AppendCall, Nop())
mkOp(bc.ReturnCallVarg, Nop())
mkOp(bc.AppendCallVarg, Nop())

mkOp(bc.Not, Push(If(Truthy(Pop()), False(), True())))

mkOp(bc.Len, (function()
	local a = Pop()
	local aty = Type(a)
	return If(
		Eq(aty, Int(types.str)),
		Push(IntObjFromInt(LoadStrLen(a))),
		If(
			Eq(aty, Int(types.tbl)),
			(function()
				local ameta = Meta(a)
				If(ameta,
					CallMetaMethod('__len', ameta, a), -- TODO helper function this
					Push(IntObjFromInt(LoadTblLen(a)))
				)
			end)(),
			Error()
		)
	)
end)())

mkOp(bc.Neg, (function()
	local a = Pop()
	return Typeck(1, a,
		types.int,
		Push(IntObjFromInt64(Negate64(LoadInt(a)))),
		types.float,
		Push(FltObjFromFlt(Negate64f(LoadFlt(a)))),
		types.tbl,
		(function()
			local ameta = Meta(a)
			If(ameta,
				CallMetaMethod('__neg', ameta, a), -- TODO helper function this
				Error()
			)
		end)(),
		Error()
	)
end)())

mkOp(bc.TblNew, Push(NewTbl()))
mkOp(bc.TblAdd, (function()
	local v = Pop()
	local k = Seq(v, Pop())
	local tbl = Seq(k, Pop())
	return TblSet(tbl, k, v)
end)())
mkOp(bc.TblSet, (function()
	local k = Pop()
	local tbl = Seq(k, Pop())
	local v = Seq(tbl, Pop())
	return TblSet(tbl, k, v)
end)())

mkOp(bc.CmpEq, (function()
	local a = Pop()
	local b = Seq(a, Pop())
	return If(
		ObjMetalessEq(a, b),
		Push(True()),
		If(
			And(
				Eq(Type(a), Int(types.tbl)),
				Eq(Type(b), Int(types.tbl))
			),
			(function()
				local amt = Meta(a)
				local bmt = Meta(b)
				If(
					And(amt, bmt),
					(function()
						local amteq = TblGet(amt, Str('__eq'))
						local bmteq = TblGet(bmt, Str('__eq'))
						If(
							Eq(amteq, bmteq),
							BoolCall(amteq, a, b),
							-- CALL META
							Push(False())
						)
					end)(),
					Push(False())
				)
			end)(),
			Push(False())
		)
	)
end)())

local function cmpop(op, cmpop, strlogic)
	mkOp(op, (function()
		local a = Pop()
		local b = Seq(a, Pop())
		return Typeck(2, a, b,
			types.int,
			types.int,
			Push(If(
				cmpop(LoadInt(a), LoadInt(b)),
				True(), False()
			)),
			types.float,
			types.float,
			Push(If(
				cmpop(LoadFlt(a), LoadFlt(b)),
				True(), False()
			)),
			types.str,
			types.str,
			Push(If(
				cmpop(StrCmp(a, b), Int(0)),
				True(), False()
			)),
			types.int,
			types.float,
			Push(If(
				cmpop(Int64Flt(LoadInt(a)), LoadFlt(b)),
				True(), False()
			)),
			types.float,
			types.int,
			Push(If(
				cmpop(LoadFlt(a), Int64Flt(LoadInt(b))),
				True(), False()
			)),
			(function()
				-- TODO metamethod fallbacks, error otherwise
			end)()
		)
	end)())
end
cmpop(bc.CmpLe, Le)
cmpop(bc.CmpLt, Lt)
cmpop(bc.CmpGe, Ge)
cmpop(bc.CmpGt, Gt)

local function binmathop(op, floatlogic, intlogic, metamethod)
	mkOp(op, (function()
		local a = Pop()
		local b = Seq(a, Pop())
		return Typeck(2, a, b,
			types.int,
			types.int,
			Push(intlogic(LoadInt(a), LoadInt(b))),
			types.float,
			types.float,
			Push(floatlogic(LoadFlt(a), LoadFlt(b))),
			types.int,
			types.float,
			Push(floatlogic(Int64Flt(LoadInt(a)), LoadFlt(b))),
			types.float,
			types.int,
			Push(floatlogic(LoadFlt(a), Int64Flt(LoadInt(b))))
		)
	end)())
end
local function binmathop_mono(op, mop, metamethod)
	return binmathop(op, mop, mop, metamethod)
end
binmathop_mono(bc.Add, Add, '__add')
binmathop_mono(bc.Sub, Sub, '__sub')
binmathop_mono(bc.Mul, Mul, '__mul')
binmathop(bc.Div,
	function(a, b)
		return Div(Flt64Int(a), Flt64Int(b))
	end,
	function(a, b)
		return Div(a, b)
	end,
	'__div')
mkOp(bc.IDiv, (function()
	local a = Pop()
	local b = Seq(a, Pop())
	return Typeck(2, a, b,
		types.int,
		types.int,
		Push(Div(LoadInt(a), LoadInt(b))),
		types.float,
		types.float,
		Push(Div(Flt64Int(LoadFlt(a)), Flt64Int(LoadFlt(b)))),
		types.int,
		types.float,
		Push(Div(LoadInt(a), Flt64Int(LoadFlt(b)))),
		types.float,
		types.int,
		Push(Div(Flt64Int(LoadFlt(a)), LoadInt(b)))
	)
end)())
binmathop(bc.Pow,
	function(f, a, b)
		return Pow(Flt64Int(a), Flt64Int(b))
	end,
	function(f, a, b)
		return Pow(a, b)
	end,
	'__pow')
binmathop_mono(bc.Mod, 'Mod', '__mod')
local function binbitop(op, mop, metamethod)
	mkOp(op, (function()
		local a = Pop()
		local b = Seq(a, Pop())
		-- TODO assert floats are integer compatible
		return Typeck(2, a, b,
			types.int,
			types.int,
			Push(mop(LoadInt(a), LoadInt(b))),
			types.float,
			types.float,
			Push(mop(Flt64Int(LoadFlt(a)), Flt64Int(LoadFlt(b)))),
			types.int,
			types.float,
			Push(mop(LoadInt(a), Flt64Int(LoadFlt(b)))),
			types.float,
			types.int,
			Push(mop(Flt64Int(LoadFlt(a)), LoadInt(b)))
		)
	end)())
end
binbitop(bc.BAnd, BAnd, '__band')
binbitop(bc.BOr, BOr, '__bor')
binbitop(bc.BXor, BXor, '__bxor')
binbitop(bc.Shr, Shr, '__shr')
binbitop(bc.Shl, Shl, '__shl')
mkOp(bc.BNot, (function()
	local a = Pop()
	return Typeck(1, a,
		types.int,
		Push(BXor(LoadInt(a), Int64(-1))),
		types.float,
		Push(BXor(Flt64Int(LoadFlt(a)), Int64(-1))),
		CallMetaMethod('__bnot', Meta(a), a)
	)
end)())

mkOp(bc.Concat, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return Typeck(2, a, b,
		types.str,
		types.str,
		Push(StrConcat(a, b)),
		If(
			And(IsNumOrStr(a), IsNumOrStr(b)),
			Push(StrConcat(ToString(a), ToString(b))),
			CallBinMetaMethod('__concat', a, b)
		)
	)
end)())

mkOp(bc.Idx, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	local ameta = Meta(a)
	return If(ameta,
		CallMetaMethod('__index', ameta, a, b),
		If(IsTbl(a),
			TblGet(a, b),
			Error()
		)
	)
end)())

mkOp(bc.Append, (function()
	local b = Pop()
	local a = Seq(b, Pop())
	return TblSet(a, TblLen(a), b)
end)())

return {
	mops = mops,
	ops = ops,
}
