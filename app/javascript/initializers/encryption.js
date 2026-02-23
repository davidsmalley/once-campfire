import EncryptionManager from "lib/encryption/encryption_manager"

document.addEventListener("turbo:load", async () => {
  const userId = document.querySelector('meta[name="current-user-id"]')?.content
  if (!userId) return

  try {
    const manager = new EncryptionManager()
    await manager.initialize()
    window.__encryptionManager = manager
  } catch (error) {
    console.error("E2EE initialization failed:", error)
  }
})
