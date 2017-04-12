"use strict";
const lex = require("./lex"),
	ast = require("./ast"),
	bc = require("./bc"),
	runbc = require("./runbc");

function varint (v, value) {
	while (true) {
		let b = value & 127;
		value >>= 7;
		if ((!value && ((b & 0x40) == 0)) || ((value == -1 && ((b & 0x40) == 0x40)))) {
			return v.push(b);
		}
		else {
			v.push(b | 128);
		}
	}
}

function varuint (v, value) {
	while (true) {
		let b = value & 127;
		value >>= 7;
		if (value) {
			v.push(b | 128);
		} else {
			return v.push(b);
		}
	}
}

function pushString(v, str) {
	for (let i=0; i<str.length; i++) {
		v.push(str.charCodeAt(i));
	}
}

function pushArray(sink, data) {
	return Array.prototype.push.apply(sink, data);
}

exports.eval = function(line, e = require("./env")()) {
	let l = new lex.Lex(line);
	let a = ast.parse(l);
	let b = bc.assemble(l, a);
	return runbc.run(b, e);
}

exports.runSource = function(source, imp){
	var l, a, b;
	console.time("lua");
	console.log(l = new lex.Lex(source), a = ast.parse(l), b = bc.assemble(l, a), runbc.run(b));
	console.timeEnd("lua");
}
