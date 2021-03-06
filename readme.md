[![Build](https://travis-ci.org/serprex/luwa.svg?branch=master)](https://travis-ci.org/serprex/luwa)

Luwa's end goal is to JIT to [WASM](https://webassembly.org). Right now it's a bit of a learning environment for me as I've never [written a language implementation](https://esolangs.org/wiki/User:Serprex) that required real parsing

I'll try avoid my usual stream of consciousness here, instead that's at [my devlog](https://patreon.com/serprex)

[`main.js`](main.js) is nodejs entrypoint

WASM runtime is in `rt/`. [`rt/make.lua`](rt/make.lua) is luwa-agnostic macro-assembler logic. [`mkrt.lua`](rt/mkrt.lua) produces an `rt.wasm` which [`rt.js`](rt.js) interfaces

GC is a LISP2 compacting GC. GC performance is a low priority given WASM GC RFC. See [`rt/gc.lua`](rt/gc.lua)

VM needs to be reentrant. Currently running coroutine is oluastack. Builtins which call functions work by returning after setting up a necessary callstack. See [`rt/vm.lua`](rt/vm.lua)

[`rt/prelude.lua`](rt/prelude.lua) implements builtins which do not require hand written wasm
