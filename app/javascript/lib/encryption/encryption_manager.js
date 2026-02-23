import KeyStore from "lib/encryption/key_store"
import KeyBundleService from "lib/encryption/key_bundle_service"
import { arrayBufferToBase64, base64ToArrayBuffer, concatBuffers } from "lib/encryption/utils"

const PRE_KEY_BATCH_SIZE = 100
const E2E_PREFIX = "e2e:v1:"

export default class EncryptionManager {
  #store
  #service
  #initialized = false

  constructor() {
    this.#store = new KeyStore()
    this.#service = new KeyBundleService()
  }

  // Initialize: generate keys if needed, upload to server
  async initialize() {
    if (this.#initialized) return

    await this.#store.open()
    let identity = await this.#store.getIdentityKeyPair()

    if (!identity) {
      identity = await this.#generateAndUploadKeys()
    }

    this.#initialized = true
  }

  // Encrypt a plaintext message for a direct room recipient
  async encryptForDirect(plaintext, recipientUserId) {
    const session = await this.#store.getSession(recipientUserId)

    let sharedSecret
    if (session?.sharedSecret) {
      sharedSecret = base64ToArrayBuffer(session.sharedSecret)
    } else {
      sharedSecret = await this.#performX3DH(recipientUserId)
    }

    const encoded = new TextEncoder().encode(plaintext)
    const iv = crypto.getRandomValues(new Uint8Array(12))
    const key = await crypto.subtle.importKey("raw", sharedSecret, "AES-GCM", false, ["encrypt"])
    const ciphertext = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, encoded)

    // Wire format: iv (12 bytes) + ciphertext
    const payload = concatBuffers(iv.buffer, ciphertext)
    return E2E_PREFIX + arrayBufferToBase64(payload)
  }

  // Decrypt an encrypted message body
  async decrypt(body, senderUserId) {
    if (!EncryptionManager.isEncrypted(body)) return body

    const payload = base64ToArrayBuffer(body.slice(E2E_PREFIX.length))
    const iv = payload.slice(0, 12)
    const ciphertext = payload.slice(12)

    const session = await this.#store.getSession(senderUserId)
    if (!session?.sharedSecret) {
      throw new Error("No session established with sender")
    }

    const sharedSecret = base64ToArrayBuffer(session.sharedSecret)
    const key = await crypto.subtle.importKey("raw", sharedSecret, "AES-GCM", false, ["decrypt"])
    const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext)

    return new TextDecoder().decode(plaintext)
  }

  // Check if a message body is encrypted
  static isEncrypted(body) {
    return typeof body === "string" && body.startsWith(E2E_PREFIX)
  }

  // Perform X3DH key agreement with a remote user
  async #performX3DH(recipientUserId) {
    const bundle = await this.#service.fetchKeys(recipientUserId)
    const identity = await this.#store.getIdentityKeyPair()

    // Generate an ephemeral X25519 key pair for this handshake
    const ephemeral = await crypto.subtle.generateKey({ name: "X25519" }, false, ["deriveBits"])

    // Import recipient's identity key and signed pre-key as public keys
    const recipientIdentityKey = await crypto.subtle.importKey(
      "raw", bundle.identityKey, { name: "X25519" }, false, []
    )
    const recipientSignedPreKey = await crypto.subtle.importKey(
      "raw", bundle.signedPreKey.key, { name: "X25519" }, false, []
    )

    // Import our own identity private key
    const ourIdentityPrivate = await crypto.subtle.importKey(
      "raw", base64ToArrayBuffer(identity.privateKey), { name: "X25519" }, false, ["deriveBits"]
    )

    // X3DH: DH1 = our identity * their signed pre-key
    const dh1 = await crypto.subtle.deriveBits(
      { name: "X25519", public: recipientSignedPreKey }, ourIdentityPrivate, 256
    )

    // X3DH: DH2 = our ephemeral * their identity
    const dh2 = await crypto.subtle.deriveBits(
      { name: "X25519", public: recipientIdentityKey }, ephemeral.privateKey, 256
    )

    // X3DH: DH3 = our ephemeral * their signed pre-key
    const dh3 = await crypto.subtle.deriveBits(
      { name: "X25519", public: recipientSignedPreKey }, ephemeral.privateKey, 256
    )

    // Derive shared secret: HKDF(DH1 || DH2 || DH3)
    const dhConcat = concatBuffers(dh1, dh2, dh3)
    const sharedSecret = await this.#hkdf(dhConcat, 32)

    // Save remote identity key
    await this.#store.saveRemoteIdentityKey(recipientUserId, arrayBufferToBase64(bundle.identityKey))

    // Save session with shared secret
    await this.#store.saveSession(recipientUserId, {
      sharedSecret: arrayBufferToBase64(sharedSecret)
    })

    return sharedSecret
  }

  // Generate identity key, signed pre-key, and one-time pre-keys, then upload
  async #generateAndUploadKeys() {
    // Generate X25519 identity key pair
    const identityKeyPair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"])
    const identityPublicRaw = await crypto.subtle.exportKey("raw", identityKeyPair.publicKey)
    const identityPrivateRaw = await crypto.subtle.exportKey("raw", identityKeyPair.privateKey)

    // Generate signed pre-key (also X25519)
    const signedPreKeyPair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"])
    const signedPreKeyPublicRaw = await crypto.subtle.exportKey("raw", signedPreKeyPair.publicKey)
    const signedPreKeyPrivateRaw = await crypto.subtle.exportKey("raw", signedPreKeyPair.privateKey)

    // Sign the signed pre-key with HMAC (using identity private key as HMAC key)
    const hmacKey = await crypto.subtle.importKey("raw", identityPrivateRaw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
    const signature = await crypto.subtle.sign("HMAC", hmacKey, signedPreKeyPublicRaw)

    // Generate one-time pre-keys
    const preKeys = []
    for (let i = 1; i <= PRE_KEY_BATCH_SIZE; i++) {
      const preKeyPair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"])
      const preKeyPublicRaw = await crypto.subtle.exportKey("raw", preKeyPair.publicKey)
      const preKeyPrivateRaw = await crypto.subtle.exportKey("raw", preKeyPair.privateKey)

      preKeys.push({
        id: i,
        publicKey: preKeyPublicRaw,
        privateKey: preKeyPrivateRaw
      })

      await this.#store.savePreKey({ id: i, publicKey: arrayBufferToBase64(preKeyPublicRaw), privateKey: arrayBufferToBase64(preKeyPrivateRaw) })
    }

    // Save identity key pair
    const identity = {
      publicKey: arrayBufferToBase64(identityPublicRaw),
      privateKey: arrayBufferToBase64(identityPrivateRaw)
    }
    await this.#store.saveIdentityKeyPair(identity)

    // Save signed pre-key
    await this.#store.saveSignedPreKey({
      id: 1,
      publicKey: arrayBufferToBase64(signedPreKeyPublicRaw),
      privateKey: arrayBufferToBase64(signedPreKeyPrivateRaw),
      signature: arrayBufferToBase64(signature)
    })

    // Upload to server
    await this.#service.uploadKeys({
      identityKey: identityPublicRaw,
      signedPreKey: signedPreKeyPublicRaw,
      signedPreKeySignature: signature,
      signedPreKeyId: 1,
      preKeys: preKeys.map(pk => ({ id: pk.id, publicKey: pk.publicKey }))
    })

    return identity
  }

  // HKDF-SHA256 key derivation
  async #hkdf(inputKeyMaterial, length) {
    const key = await crypto.subtle.importKey("raw", inputKeyMaterial, "HKDF", false, ["deriveBits"])
    const derived = await crypto.subtle.deriveBits(
      { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(32), info: new TextEncoder().encode("campfire-e2ee") },
      key, length * 8
    )
    return derived
  }
}
