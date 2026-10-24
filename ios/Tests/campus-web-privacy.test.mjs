import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../CCSUT/CampusWebPrivacy.swift', import.meta.url), 'utf8');
const script = source.match(/static let script = #"""\n([\s\S]*?)\n\s*"""#/)[1];

function page(host = 'ehall.ccsut.cn', split = false) {
  const block={tagName:'DIV'};
  const nodes = (split ? ['180','0000','0000'] : ['联系电话 18000000000']).map(value=>({
    nodeValue:value, parentElement:{tagName:'SPAN',parentElement:block},
  }));
  const text=nodes[0];
  class Input {
    constructor(){this.type='text';this.name='contactValue';this.placeholder='';this.style={};this.tagName='INPUT';}
    get value(){return this._value || '';}
    set value(value){this._value=value;}
  }
  class TextArea extends Input {}
  const field = new Input();
  if(!split){field.value='18000000000';field.type='tel';field.name='phone';}
  const state = {text,nodes,field,changed:null};
  const document = {
    documentElement:{},
    createTreeWalker() { let index=0; return {nextNode(){return nodes[index++] || null;}}; },
    querySelectorAll(){return [field];},
    addEventListener(){},
  };
  class MutationObserver {
    constructor(callback){state.changed=callback;}
    observe(){}
  }
  vm.runInNewContext(script,{location:{hostname:host},document,NodeFilter:{SHOW_TEXT:4},MutationObserver,window:{},HTMLInputElement:Input,HTMLTextAreaElement:TextArea});
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
test('a phone number split across adjacent inline elements is masked',()=>{
  const state=page('ehall.ccsut.cn',true);
  assert.equal(state.nodes.map(node=>node.nodeValue).join('').includes('18000000000'),false);
});
test('programmatic value assignment is masked before any input event',()=>{
  const state=page('ehall.ccsut.cn',true);
  state.field.value='18000000000';
  assert.equal(state.field.style.webkitTextSecurity,'disc');
  assert.equal(state.field.value,'18000000000');
});
