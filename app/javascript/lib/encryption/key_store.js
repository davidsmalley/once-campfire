const DB_NAME = "campfire_e2ee"
const DB_VERSION = 1

const STORES = {
  identityKeys: "identityKeys",
  signedPreKeys: "signedPreKeys",
  preKeys: "preKeys",
  sessions: "sessions",
  senderKeys: "senderKeys"
}

export default class KeyStore {
  #db = null

  async open() {
    if (this.#db) return this.#db

    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION)

      request.onupgradeneeded = (event) => {
        const db = event.target.result
        for (const storeName of Object.values(STORES)) {
          if (!db.objectStoreNames.contains(storeName)) {
            db.createObjectStore(storeName, { keyPath: "id" })
          }
        }
      }

      request.onsuccess = () => {
        this.#db = request.result
        resolve(this.#db)
      }

      request.onerror = () => reject(request.error)
    })
  }

  // Identity key pair (our own long-term key)

  async getIdentityKeyPair() {
    return this.#get(STORES.identityKeys, "local")
  }

  async saveIdentityKeyPair(keyPair) {
    return this.#put(STORES.identityKeys, { id: "local", ...keyPair })
  }

  // Remote identity keys (other users' public identity keys)

  async getRemoteIdentityKey(userId) {
    return this.#get(STORES.identityKeys, `remote_${userId}`)
  }

  async saveRemoteIdentityKey(userId, publicKey) {
    return this.#put(STORES.identityKeys, { id: `remote_${userId}`, publicKey })
  }

  // Signed pre-keys

  async getSignedPreKey(id) {
    return this.#get(STORES.signedPreKeys, id)
  }

  async saveSignedPreKey(signedPreKey) {
    return this.#put(STORES.signedPreKeys, signedPreKey)
  }

  // One-time pre-keys

  async getPreKey(id) {
    return this.#get(STORES.preKeys, id)
  }

  async savePreKey(preKey) {
    return this.#put(STORES.preKeys, preKey)
  }

  async removePreKey(id) {
    return this.#delete(STORES.preKeys, id)
  }

  // Sessions (keyed by remote user ID)

  async getSession(userId) {
    return this.#get(STORES.sessions, `session_${userId}`)
  }

  async saveSession(userId, sessionData) {
    return this.#put(STORES.sessions, { id: `session_${userId}`, ...sessionData })
  }

  // Sender keys (for group encryption)

  async getSenderKey(id) {
    return this.#get(STORES.senderKeys, id)
  }

  async saveSenderKey(senderKey) {
    return this.#put(STORES.senderKeys, senderKey)
  }

  // Clear all stores (for key reset)

  async clear() {
    const db = await this.open()
    const tx = db.transaction(Object.values(STORES), "readwrite")
    for (const storeName of Object.values(STORES)) {
      tx.objectStore(storeName).clear()
    }
    return new Promise((resolve, reject) => {
      tx.oncomplete = resolve
      tx.onerror = () => reject(tx.error)
    })
  }

  // Private helpers

  async #get(storeName, key) {
    const db = await this.open()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, "readonly")
      const request = tx.objectStore(storeName).get(key)
      request.onsuccess = () => resolve(request.result || null)
      request.onerror = () => reject(request.error)
    })
  }

  async #put(storeName, value) {
    const db = await this.open()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, "readwrite")
      tx.objectStore(storeName).put(value)
      tx.oncomplete = resolve
      tx.onerror = () => reject(tx.error)
    })
  }

  async #delete(storeName, key) {
    const db = await this.open()
    return new Promise((resolve, reject) => {
      const tx = db.transaction(storeName, "readwrite")
      tx.objectStore(storeName).delete(key)
      tx.oncomplete = resolve
      tx.onerror = () => reject(tx.error)
    })
  }
}
