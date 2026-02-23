import { arrayBufferToBase64, base64ToArrayBuffer } from "lib/encryption/utils"

export default class KeyBundleService {
  #csrfToken

  constructor() {
    this.#csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  }

  async uploadKeys({ identityKey, signedPreKey, signedPreKeySignature, signedPreKeyId, preKeys }) {
    const response = await fetch("/api/v1/users/me/keys", {
      method: "POST",
      headers: this.#headers,
      body: JSON.stringify({
        identity_key: arrayBufferToBase64(identityKey),
        signed_pre_key: arrayBufferToBase64(signedPreKey),
        signed_pre_key_signature: arrayBufferToBase64(signedPreKeySignature),
        signed_pre_key_id: signedPreKeyId,
        pre_keys: preKeys.map(pk => ({
          key_id: pk.id,
          public_key: arrayBufferToBase64(pk.publicKey)
        }))
      })
    })

    if (!response.ok) throw new Error("Failed to upload keys")
  }

  async fetchKeys(userId) {
    const response = await fetch(`/api/v1/users/${userId}/keys`, {
      headers: this.#headers
    })

    if (!response.ok) throw new Error("Failed to fetch keys")

    const data = await response.json()
    return {
      userId: data.user_id,
      identityKey: base64ToArrayBuffer(data.identity_key),
      signedPreKey: {
        id: data.signed_pre_key.id,
        key: base64ToArrayBuffer(data.signed_pre_key.key),
        signature: base64ToArrayBuffer(data.signed_pre_key.signature)
      },
      preKey: data.pre_key ? {
        id: data.pre_key.id,
        key: base64ToArrayBuffer(data.pre_key.key)
      } : null
    }
  }

  async deleteKeys() {
    const response = await fetch("/api/v1/users/me/keys", {
      method: "DELETE",
      headers: this.#headers
    })

    if (!response.ok) throw new Error("Failed to delete keys")
  }

  get #headers() {
    return {
      "Content-Type": "application/json",
      "X-CSRF-Token": this.#csrfToken
    }
  }
}
