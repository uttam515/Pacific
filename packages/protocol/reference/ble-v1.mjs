/** Contract reference only. Not connected to a BLE radio or native app. */
export const BLE_MAX_BYTES=2048;
export function fragment(bytes,transferId){
 bytes=Buffer.from(bytes);
 if(!Number.isInteger(transferId)||transferId<1||transferId>0xffffffff)throw new Error('TRANSFER_ID');
 if(bytes.length<1||bytes.length>BLE_MAX_BYTES)throw new Error('BLE_SIZE_LIMIT');
 const count=Math.ceil(bytes.length/8);
 return Array.from({length:count},(_,index)=>{const payload=bytes.subarray(index*8,index*8+8);const f=Buffer.alloc(12+payload.length);f.write('OG',0,'ascii');f[2]=1;f[3]=0;f.writeUInt32BE(transferId,4);f.writeUInt16BE(index,8);f.writeUInt16BE(count,10);payload.copy(f,12);return f});
}
function decode(frame){
 const f=Buffer.from(frame);
 if(f.length<13||f.length>20||f[0]!==0x4f||f[1]!==0x47||f[2]!==1||f[3]!==0)throw new Error('FRAME_HEADER');
 const id=f.readUInt32BE(4),index=f.readUInt16BE(8),count=f.readUInt16BE(10);
 if(id<1||count<1||count>256||index>=count||(index<count-1&&f.length!==20))throw new Error('FRAME_BOUNDS');
 return {id,index,count,payload:f.subarray(12)};
}
/** Make a NEW instance per authenticated connection/direction. */
export class Assembler{
 #active;#retired=0;
 #abort(){if(this.#active)this.#retired=Math.max(this.#retired,this.#active.id);this.#active=undefined}
 accept(frame,now=Date.now()){
  if(this.#active&&(now-this.#active.last>=15000||now-this.#active.started>=120000)){this.#abort();throw new Error('TRANSFER_EXPIRED')}
  const p=decode(frame);
  if(p.id<=this.#retired)throw new Error('TRANSFER_RETIRED');
  if(this.#active&&this.#active.id!==p.id)throw new Error('TRANSFER_BUSY');
  this.#active??={id:p.id,count:p.count,started:now,last:now,chunks:new Map()};
  const a=this.#active;
  if(a.count!==p.count){this.#abort();throw new Error('COUNT_CHANGED')}
  const previous=a.chunks.get(p.index);
  if(previous&&!previous.equals(p.payload)){this.#abort();throw new Error('CHUNK_CHANGED')}
  if(!previous){a.chunks.set(p.index,p.payload);a.last=now}
  if(a.chunks.size!==a.count)return null;
  const bytes=Buffer.concat(Array.from({length:a.count},(_,index)=>a.chunks.get(index)));
  this.#abort();return bytes;
 }
}
