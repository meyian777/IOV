# LabVoice Founder Vault

## Objective

Protect founder-only information so application developers, operators, AI
agents, source-control readers, and infrastructure administrators cannot read
the plaintext without an explicit founder authentication event.

## Security boundary

- Never store the decryption key in source code, Git, application assets,
  prompts, logs, analytics, backups, or the same database as the ciphertext.
- Keep public biography and private founder records as separate data classes.
- Deny private-profile access by default, including to LabVoice and coding
  agents.
- Decrypt only after fresh founder authentication and only for the requested
  operation.
- Keep authorization short-lived and auditable; erase plaintext from memory as
  soon as practical.

## Recommended production design

1. Encrypt founder records with a random data-encryption key using an
   authenticated cipher.
2. Wrap that key with a hardware-backed key controlled through macOS Keychain,
   Secure Enclave, or a cloud KMS/HSM.
3. Require founder authentication with a passkey or hardware security key.
4. Issue a short-lived capability token limited to one operation.
5. Perform decryption inside a small isolated vault service.
6. Return only the minimum approved fields; never return the encryption key.
7. Record access metadata without recording private content.
8. Support founder-controlled correction, export, key rotation, and deletion.

## Current development state

The local founder profile is encrypted with Fernet and its key is stored in the
ignored local environment file. This protects it from Git and casual source
access, but it is not yet the final founder-only security boundary. Production
work must move the key into hardware-backed storage and add passkey
authentication before private data is exposed through any API.
