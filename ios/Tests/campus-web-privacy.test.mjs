import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../CCSUT/CampusWebPrivacy.swift', import.meta.url), 'utf8');
const script = source.match(/static let script = #"""\n([\s\S]*?)\n\s*"""#/)[1];

function page(host = 'ehall.ccsut.cn') {
  const text = {nodeValue:'联系电话 18000000000', parentElement:{tagName:'DIV'}};
  const field = {value:'18000000000', type:'tel', name:'phone', placeholder:'手机号', style:{}};
  const state = {text,field,changed:null};
  const document = {
    documentElement:{},
    createTreeWalker() { let read=false; return {nextNode(){if(read)return null;read=true;return text;}}; },
    querySelectorAll(){return [field];},
    addEventListener(){},
  };
  class MutationObserver {
    constructor(callback){state.changed=callback;}
    observe(){}
  }
  vm.runInNewContext(script,{location:{hostname:host},document,NodeFilter:{SHOW_TEXT:4},MutationObserver,window:{}});
  return state;
}

test('official text and contact fields are masked without changing submission values',()=>{
  const state=page();
  assert.equal(state.text.nodeValue,'联系电话 ••••');
  assert.equal(state.field.style.webkitTextSecurity,'disc');
  assert.equal(state.field.value,'18000000000');
});
test('dynamically rendered identity and bank text is also masked',()=>{
  const state=page();
  state.text.nodeValue='证件 11000020000101001X / 银行卡 6222000000000000000';
  state.changed();
  assert.equal(state.text.nodeValue,'证件 •••• / 银行卡 ••••');
});
test('privacy script does not modify unrelated origins',()=>{
  const state=page('outside.invalid');
  assert.equal(state.text.nodeValue,'联系电话 18000000000');
  assert.equal(state.changed,null);
});
