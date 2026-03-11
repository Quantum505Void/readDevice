import { gcm } from "@noble/ciphers/aes.js";

if (typeof window !== "undefined" && window.crypto && !window.crypto.subtle) {
  const rawKeys = new Map<object, Uint8Array>();
  function toU8(v: ArrayBuffer | ArrayBufferView): Uint8Array {
    if (v instanceof Uint8Array) return v;
    if (v instanceof ArrayBuffer) return new Uint8Array(v);
    return new Uint8Array((v as ArrayBufferView).buffer, (v as ArrayBufferView).byteOffset, (v as ArrayBufferView).byteLength);
  }
  const subtle = {
    importKey(_f: string, k: ArrayBuffer | ArrayBufferView): Promise<object> {
      const key = {};
      rawKeys.set(key, toU8(k instanceof ArrayBuffer ? k : k));
      return Promise.resolve(key);
    },
    encrypt(a: { iv: Uint8Array }, k: object, d: ArrayBuffer | ArrayBufferView): Promise<ArrayBuffer> {
      const cipher = gcm(rawKeys.get(k)!, a.iv);
      return Promise.resolve((cipher.encrypt(toU8(d))).buffer as ArrayBuffer);
    },
    decrypt(a: { iv: Uint8Array }, k: object, d: ArrayBuffer | ArrayBufferView): Promise<ArrayBuffer> {
      const cipher = gcm(rawKeys.get(k)!, a.iv);
      return Promise.resolve((cipher.decrypt(toU8(d))).buffer as ArrayBuffer);
    },
    getRandomValues: (arr: Uint8Array) => crypto.getRandomValues(arr),
  };
  Object.defineProperty(window.crypto, "subtle", { value: subtle, configurable: true, writable: true });
  console.log("[electrobun-crypto-polyfill] AES-GCM installed");
}
