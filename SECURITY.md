# Security

## Reporting a vulnerability

If you discover a security issue, please open a GitHub issue with minimal
reproduction steps or contact the repository owner privately. Do not publish
exploit details before a fix is available.

## Secrets policy

This repository is intended to be **public**. It must never contain:

- API keys, tokens, or passwords
- Apple Developer provisioning profiles or `.p12` certificates
- `GoogleService-Info.plist` or other vendor credential files
- Personal email addresses, phone numbers, or home addresses in docs or code

If you add a feature that needs credentials (for example, a future Spoonacular
admin ingest tool), keep them in local-only files listed in `.gitignore`
(`*.env`, `Secrets.swift`) and document the required keys in README setup
instructions without embedding real values.

## What is safe to commit

- Bundle identifiers and App Group IDs (`com.abhishekbiju.mealkit`) — these are
  public identifiers, not secrets
- Public model download URLs (Hugging Face GGUF / WhisperKit bundles)
- Architecture decision records and product documentation
