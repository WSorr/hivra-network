# Hivra Flutter App

Flutter client for Hivra Protocol v3.2.

## Capsule UX Rules

### First Launch

- If no capsules exist, the user must create the first capsule (`Proto` or `Genesis`).
- If at least one capsule exists, show the capsule selection screen.

### Capsule Selection Screen

- Show capsule public key, network, and starter count.
- Allow creating a new capsule.
- Allow selecting an existing capsule.

### Multi-Capsule Management

- Multiple capsules are supported.
- Capsules are independent (separate seed and ledger).
- Switching can happen at any time.
- On switch, load selected capsule state and unload previous capsule from memory.

## Run (macOS)

```bash
cd flutter
flutter pub get
flutter run -d macos
```

## Notes

- Current development target is macOS.
- iOS project files can stay in the repo, but they are not required for local macOS runs.
