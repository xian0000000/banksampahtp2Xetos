import { createDualStore } from "./dual-core.js";
import assert from "node:assert/strict";

function fake(name){
  const s = { name, data:{}, mode:"up", log:[] };
  const gate = () => s.mode==="up" ? Promise.resolve() : s.mode==="down" ? Promise.reject(new Error("down")) : new Promise(()=>{});
  const setPath=(p,v)=>{ const k=p.split("/"); let o=s.data; k.slice(0,-1).forEach(x=>o=o[x]??={}); if(v===null) delete o[k.at(-1)]; else o[k.at(-1)]=v; };
  s.get=async p=>{await gate(); return p.split("/").reduce((o,k)=>o?.[k], s.data) ?? null;};
  s.update=async u=>{await gate(); s.log.push(["u",u]); for(const[p,v] of Object.entries(u)) setPath(p,v);};
  s.set=async(p,v)=>{await gate(); setPath(p,v);};
  s.remove=async p=>{await gate(); setPath(p,null);};
  return s;
}
const mem=()=>{const m={};return{getItem:k=>m[k]??null,setItem:(k,v)=>{m[k]=v}}};
const mk=(a,b,st=mem())=>createDualStore({backends:[a,b],storage:st,timeoutMs:40,cooldownMs:1000});

// 1. both up
{ const a=fake("S1"),b=fake("S2"),d=mk(a,b);
  const r=await d.update({"users/u1/nama":"Budi"}); assert.deepEqual(r,[true,true]);
  assert.deepEqual(a.data,b.data); }
// 2. S2 hang -> write ok, queued; recover -> converge, order preserved
{ const a=fake("S1"),b=fake("S2"),d=mk(a,b);
  b.mode="hang";
  const r1=await d.set("kategori/k1",{nama:"Plastik",harga:2000});
  const r2=await d.update({"kategori/k1/harga":3000});
  const r3=await d.remove("kategori/k1");
  const r4=await d.set("kategori/k2",{nama:"Kertas"});
  assert.deepEqual(r1,[true,false]); assert.equal(d.status()[1].pending,4);
  b.mode="up"; await d.flushAll();
  assert.equal(d.status()[1].pending,0);
  assert.deepEqual(a.data,b.data); assert.deepEqual(Object.keys(b.data.kategori),["k2"]); }
// 3. both down -> throws, no ghost write
{ const a=fake("S1"),b=fake("S2"),d=mk(a,b); a.mode="down"; b.mode="hang";
  await assert.rejects(()=>d.set("x",1)); assert.equal(d.status()[0].pending,0); assert.equal(d.status()[1].pending,0);
  a.mode="up"; b.mode="up"; await d.flushAll(); assert.equal(a.data.x,undefined); }
// 4. read failover + prefers the more complete server
{ const a=fake("S1"),b=fake("S2"),d=mk(a,b);
  await d.set("pengumuman/p1",{judul:"hi"});
  a.mode="hang"; const v=await d.read("pengumuman/p1"); assert.deepEqual(v,{judul:"hi"});
  a.mode="up"; b.mode="hang"; await d.set("pengumuman/p2",{judul:"baru"}); // S2 tertinggal
  b.mode="up"; const w=await d.read("pengumuman/p2"); assert.deepEqual(w,{judul:"baru"}); }
// 5. outbox survives reload
{ const st=mem(); const a=fake("S1"),b=fake("S2"); let d=mk(a,b,st); b.mode="down";
  await d.set("a/b",1); const b2=fake("S2"); const d2=mk(a,b2,st); assert.equal(d2.status()[1].pending,1);
  await d2.flushAll(); assert.equal(b2.data.a.b,1); }
// 6. full resync
{ const a=fake("S1"),b=fake("S2"),d=mk(a,b); a.data={users:{u:{n:1}},kategori:{k:1}}; b.data={users:{old:1},junk:1};
  const r=await d.syncAll(0,1,["users","kategori","junk"]); assert.equal(r.copied,3); assert.equal(r.failed.length,0); assert.deepEqual(b.data,{users:{u:{n:1}},kategori:{k:1}}); }
// 7. resync: satu node ditolak -> dilaporkan, node lain tetap tersalin
{ const a=fake("S1"),b=fake("S2"),d=mk(a,b); a.data={users:{u:1},kategori:{k:1}};
  const orig=b.set; b.set=async(p,v)=>{ if(p==="users") throw new Error("Permission denied"); return orig(p,v); };
  const r=await d.syncAll(0,1,["users","kategori"]);
  assert.equal(r.copied,1); assert.equal(r.failed[0].node,"users"); assert.match(r.failed[0].step,/S2/); assert.deepEqual(b.data,{kategori:{k:1}}); }
console.log("semua tes lolos");
