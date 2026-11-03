import type { Action, Snapshot } from "./domain";
let database: Promise<IDBDatabase> | undefined;
function open() {
  return (database ??= new Promise<IDBDatabase>((resolve, reject) => {
    const r = indexedDB.open("offgrid-dashboard-v1", 1);
    r.onupgradeneeded = () => r.result.createObjectStore("state");
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  }));
}
export async function get<T>(key: string): Promise<T | undefined> {
  const db = await open();
  return new Promise((resolve, reject) => {
    const r = db.transaction("state").objectStore("state").get(key);
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}
export async function put(key: string, value: unknown) {
  const db = await open();
  return new Promise<void>((resolve, reject) => {
    const tx = db.transaction("state", "readwrite");
    tx.objectStore("state").put(value, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}
export const saveSnapshot = (mode: string, s: Snapshot) =>
  put(`snapshot:${mode}`, s);
export async function enqueue(scope: string, a: Action) {
  const db = await open();
  return new Promise<void>((resolve, reject) => {
    const tx = db.transaction("state", "readwrite"),
      store = tx.objectStore("state");
    const r = store.get(`outbox:${scope}`);
    r.onsuccess = () => store.put([...(r.result || []), a], `outbox:${scope}`);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
export async function removeQueued(scope: string, id: string) {
  const db = await open();
  return new Promise<void>((resolve, reject) => {
    const tx = db.transaction("state", "readwrite"),
      store = tx.objectStore("state");
    const r = store.get(`outbox:${scope}`);
    r.onsuccess = () =>
      store.put(
        (r.result || []).filter((a: Action) => a.operationId !== id),
        `outbox:${scope}`,
      );
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
