const rtwa = typeof fetch !== 'undefined' ?
	fetch('rt.wasm', {cache:'no-cache'}).then(r => r.arrayBuffer()) :
	new Promise((resolve, reject) =>
		require('fs').readFile(__dirname + '/rt.wasm',
			(err, data) => err ? reject(err) : resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)))
	);
function rtwathen(ab) {
	const mem = new WebAssembly.Memory({initial:16}), ffi = new FFI(mem);
	return WebAssembly.instantiate(ab, {'':{
		m: mem,
		echoptr: x => {
			const memta = new Uint8Array(mem.buffer);
			console.log(x, x&7, x+4 < memta.length && memta[x+4]);
			if (!(x&7) && x+4 < memta.length && memta[x+4] < 9) {
				try{
					console.log(ffi.rawobj2js(x));
				}catch(e){console.log(e)}
			}
			return x;
		},
		echo: x => {
			console.log(x);
			return x;
		},
		sin: Math.sin,
		cos: Math.cos,
		tan: Math.tan,
		asin: Math.asin,
		acos: Math.acos,
		atan: Math.atan,
		atan2: Math.atan2,
		exp: Math.exp,
		log: Math.log,
		pow: Math.pow,
		gcmark: x => {
			for (const h of ffi.handles) {
				ffi.mod.gcmark(h.val);
			}
		},
		gcfix: () => {
			const memta = new Uint8Array(mem.buffer);
			for (const h of ffi.handles) {
				h.val = util.readuint32(memta, h.val)&-8;
			}
		},
	}}).then(mod => {
		ffi.mod = mod.instance.exports;
		return ffi;
	});
}
module.exports = () => rtwa.then(rtwathen);
const util = require('./util');

function Handle(val) {
	this.val = val;
}
function FFI(mem) {
	this.mod = null;
	this.mem = mem;
	this.handles = new Set();
}
FFI.prototype.free = function(h) {
	this.handles.delete(h);
}
FFI.prototype.mkref = function(p) {
	switch (p) {
		case 0: return this.nil;
		case 8: return this.false;
		case 16: return this.true;
		default: {
			const h = new Handle(p);
			this.handles.add(h);
			return h;
		}
	}
}
FFI.prototype.newtbl = function() {
	return this.mkref(this.mod.newtbl());
}
FFI.prototype.newstr = function(s) {
	if (typeof s === "string") s = util.asUtf8(s);
	const o = this.mod.newstr(s.length);
	const memta = new Uint8Array(this.mem.buffer);
	memta.set(s, o+13);
	return this.mkref(o);
}
FFI.prototype.newf64 = function(f) {
	return this.mkref(this.mod.newf64(f));
}
FFI.prototype.nil = new Handle(0);
FFI.prototype.true = new Handle(8);
FFI.prototype.false = new Handle(16);
FFI.prototype.gettypeid = function(h) {
	const memta = new Uint8Array(this.mem.buffer);
	return memta[h.val+4];
}
const tys = ["number", "number", null, "table", "string", "vec", "buf", "function", "thread"];
FFI.prototype.gettype = function(h) {
	return tys[this.gettypeid(h)] || (h.val ? 'boolean' : 'nil');
}
FFI.prototype.strbytes = function(h) {
	const memta = new Uint8Array(this.mem.buffer);
	return new Uint8Array(memta.buffer, h.val+13, util.readuint32(memta, h.val+5));
}
FFI.prototype.rawobj2js = function(p, memta = new Uint8Array(this.mem.buffer), memo = new Map()) {
	if (memo.has(p)) return memo.get(p);
	const result = this.rawobj2jsCore(p, memta, memo);
	memo.set(p, result);
	return result;
}
FFI.prototype.rawobj2jsCore = function(p, memta = new Uint8Array(this.mem.buffer), memo = new Map()) {
	if (p&7) return "Unaligned object @ " + p;
	switch (memta[p+4]) {
		case 0:
			return new Uint32Array(memta.slice(p+5, p+13).buffer);
		case 1:
			return new Float64Array(memta.slice(p+5, p+13).buffer)[0];
		case 2:
			return p ? !!memta[p+5] : null;
		case 3: {
			const hash = util.readuint32(memta, p+21),
				hashlen = util.readuint32(memta, hash+5),
				map = new Map();
			memo.set(p, map);
			for (let i=0; i<hashlen; i+=8) {
				const k = util.readuint32(memta, hash+9+i);
				if (k) {
					const v = util.readuint32(memta, hash+13+i);
					if (v) {
						map.set(this.rawobj2js(k, memta, memo), this.rawobj2js(v, memta, memo));
					}
				}
			}

			return { hash: map, meta: this.rawobj2js(util.readuint32(memta, p+25), memta, memo) };
		}
		case 4:
			return new Uint8Array(memta.buffer, p+13, util.readuint32(memta, p+5));
		case 5: {
			const len = util.readuint32(memta, p+5), ret = [];
			memo.set(p, ret);
			for (let i=0; i<len; i+=4) {
				ret.push(this.rawobj2js(util.readuint32(memta, p + 9 + i), memta, memo));
			}
			return ret;
		}
		case 6:
			return this.rawobj2js(util.readuint32(memta, p + 9), memta, memo);
		case 7:
			return {
				id: util.readuint32(memta, p + 5),
				isdotdotdot: memta[p+9],
				bc: this.rawobj2js(util.readuint32(memta, p + 10), memta, memo),
				consts: this.rawobj2js(util.readuint32(memta, p + 14), memta, memo),
				free: this.rawobj2js(util.readuint32(memta, p + 18), memta, memo),
				localc: util.readuint32(memta, p + 22),
				paramc: util.readuint32(memta, p + 26),
			};
		case 8:
			return {
				id: util.readuint32(memta, p + 5),
				state: memta[p+9],
				caller: this.rawobj2js(util.readuint32(memta, p + 10), memta, memo),
				stack: this.rawobj2js(util.readuint32(memta, p + 14), memta, memo),
				data: this.rawobj2js(util.readuint32(memta, p + 18), memta, memo),
			}
		default:
			return "Unknown type: " + memta[p+4] + " @ " + p;
	}
}
FFI.prototype.obj2js = function(h) {
	return this.rawobj2js(h.val);
}
FFI.prototype.evalWait = function() {
	return new Promise(resolve =>
		(function core(mod) {
			if (mod.eval()) {
				resolve();
			} else {
				setTimeout(core, 0, mod);
			}
		})(this.mod)
	);
}
FFI.prototype.rawexec = function(fn, ...param) {
	// TODO have a flag for when mid computation?

	this.mod.tmpclear();
	for (const v of param) {
		this.mod.tmppush(v);
	}
	this.mod.init(fn);
	return this.evalWait();
}
FFI.prototype.exec = function(fn, ...param) {
	return this.rawexec(fn.val, ...param.map(x => x.val))
}
FFI.prototype.compile = function(env, str) {
	const loadstr = this.newstr('load');
	const loadfn = this.mod.tblget(env.val, loadstr.val);
	this.free(loadstr);
	if (!loadfn) throw new Error("_ENV missing 'load' function");
	return this.rawexec(loadfn, str.val);
}
FFI.prototype.eval = async function(env, str, ...param) {
	const fn = await this.compile(env, str);
	if (!fn) throw new Error("Failed to compile");
	return this.rawexec(fn, ...param.map(x => x.val));
}
