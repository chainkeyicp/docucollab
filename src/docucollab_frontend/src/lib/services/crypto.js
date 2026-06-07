// E2E Encryption Service using Web Crypto API
// AES-256-GCM for document encryption, RSA-OAEP for key exchange

const DB_NAME = "docucollab_keys";
const DB_VERSION = 1;
let keyScope = "legacy";

export function setKeyScope(principalText) {
  keyScope = principalText || "legacy";
}

export function clearKeyScope() {
  keyScope = "legacy";
}

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("keys")) {
        db.createObjectStore("keys");
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function dbGet(key) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("keys", "readonly");
    const req = tx.objectStore("keys").get(key);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function dbPut(key, value) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("keys", "readwrite");
    tx.objectStore("keys").put(value, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

function scopedKey(key) {
  return `${keyScope}:${key}`;
}

async function dbGetScoped(key) {
  const current = scopedKey(key);
  const scoped = await dbGet(current);
  if (scoped) return scoped;

  if (keyScope !== "legacy") {
    const legacy = await dbGet(key);
    if (legacy) {
      await dbPut(current, legacy);
      return legacy;
    }
  }

  return null;
}

async function dbPutScoped(key, value) {
  await dbPut(scopedKey(key), value);
}

// === AES-GCM Document Encryption ===

export async function generateDocumentKey() {
  return await crypto.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"]
  );
}

export async function encryptDocument(arrayBuffer, aesKey) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    aesKey,
    arrayBuffer
  );
  // Prepend IV to ciphertext
  const result = new Uint8Array(iv.length + ciphertext.byteLength);
  result.set(iv, 0);
  result.set(new Uint8Array(ciphertext), iv.length);
  return result;
}

export async function decryptDocument(encryptedData, aesKey) {
  const iv = encryptedData.slice(0, 12);
  const ciphertext = encryptedData.slice(12);
  return await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    aesKey,
    ciphertext
  );
}

export async function encryptText(plainText, aesKey) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plainText);
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    aesKey,
    encoded
  );
  return {
    encrypted: new Uint8Array(encrypted),
    iv,
  };
}

export async function decryptText(encryptedBytes, ivBytes, aesKey) {
  const encrypted = encryptedBytes instanceof Uint8Array
    ? encryptedBytes
    : new Uint8Array(encryptedBytes);
  const iv = ivBytes instanceof Uint8Array
    ? ivBytes
    : new Uint8Array(ivBytes);
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    aesKey,
    encrypted
  );
  return new TextDecoder().decode(decrypted);
}

export async function exportKey(aesKey) {
  return new Uint8Array(await crypto.subtle.exportKey("raw", aesKey));
}

export async function importKey(rawBytes) {
  return await crypto.subtle.importKey(
    "raw",
    rawBytes,
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"]
  );
}

// === RSA-OAEP Key Exchange ===

export async function generateKeyPair() {
  return await crypto.subtle.generateKey(
    {
      name: "RSA-OAEP",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["wrapKey", "unwrapKey"]
  );
}

export async function exportPublicKey(publicKey) {
  const spki = await crypto.subtle.exportKey("spki", publicKey);
  return new Uint8Array(spki);
}

export async function importPublicKey(spkiBytes) {
  return await crypto.subtle.importKey(
    "spki",
    spkiBytes,
    { name: "RSA-OAEP", hash: "SHA-256" },
    false,
    ["wrapKey"]
  );
}

export async function encryptKeyForRecipient(aesKey, recipientPublicKey) {
  const wrapped = await crypto.subtle.wrapKey("raw", aesKey, recipientPublicKey, { name: "RSA-OAEP" });
  return new Uint8Array(wrapped);
}

export async function decryptKeyWithPrivateKey(encryptedAesKey, privateKey) {
  return await crypto.subtle.unwrapKey(
    "raw",
    encryptedAesKey,
    privateKey,
    { name: "RSA-OAEP" },
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"]
  );
}

// === Key Storage (IndexedDB) ===

export async function saveDocumentKey(docId, aesKey) {
  const raw = await exportKey(aesKey);
  await dbPutScoped(`doc_${docId}`, raw);
}

export async function getDocumentKey(docId) {
  const raw = await dbGetScoped(`doc_${docId}`);
  if (!raw) return null;
  return await importKey(raw);
}

export async function savePrivateKey(privateKey) {
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", privateKey);
  await dbPutScoped("privateKey", new Uint8Array(pkcs8));
}

export async function getPrivateKey() {
  const pkcs8 = await dbGetScoped("privateKey");
  if (!pkcs8) return null;
  return await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "RSA-OAEP", hash: "SHA-256" },
    true,
    ["unwrapKey"]
  );
}

export async function hasPrivateKey() {
  const pk = await dbGetScoped("privateKey");
  return pk != null;
}

// === Recovery Key Export ===

export async function exportRecoveryKey() {
  const pkcs8 = await dbGetScoped("privateKey");
  if (!pkcs8) throw new Error("No private key found");
  return pkcs8;
}

export async function importRecoveryKey(pkcs8Bytes) {
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8Bytes,
    { name: "RSA-OAEP", hash: "SHA-256" },
    true,
    ["unwrapKey"]
  );
  await dbPutScoped("privateKey", new Uint8Array(pkcs8Bytes));
  return privateKey;
}
