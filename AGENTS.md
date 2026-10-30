# CleanOps coding agent instructions (Codex and contributors)

This is the **only approved repository** for the CleanOps solid-waste operations project:
`ayma7n982-del/CleanOps_Reports_Fixed_Download`, branch `main`.

## Non-negotiable requirements

1. Never revert previously accepted changes in unrelated modules: reports/PDF, decision hub, SOS, group supervision, workers, equipment/cart redirects, smart search, and Firebase account deletion.
2. Preserve the currently approved Flutter visual language and components in `lib/presentation/widgets/app_design.dart`, including responsive mobile layouts. Favor reusing the existing theme, cards, and shortcuts.
3. Enforce security **in Firebase rules or trusted server code**, not just by hiding Flutter buttons. Role scopes: `donor_manager`, `jsc_coordinator`, `municipality_coordinator`, `group_supervisor`, `worker`. A supervisor broadcasts **only within their own group**; management/escalation routes remain explicitly scoped.
4. Preserve offline-first Firestore messaging and automatic reconnect behavior. Never mark a message as delivered until confirmed by the server; distinguish locally queued, rejected, sent, and recipient-acknowledged states. Avoid duplicate retries and false success banners.
5. Do not deploy to the `nrc-aid` Firebase production project, change production rules, trigger external SMS, or commit secrets without explicit authorization, successful emulator tests, and a reviewed deployment plan. The production credentials and SMS provider credentials belong in protected secrets, never in client Dart or source control.
6. Verify GitHub Actions on the exact final commit. An earlier successful run, cancelled run, or syntax-only validation does **not** establish that a new change works. Do not claim a successful APK without a successful APK build for the relevant commit.
7. When rules are modified, add negative (out-of-scope and spoofing) security tests as well as successful legitimate cases. Pay special attention to message receipts, attachments, direct targets, and scheduled messages.
8. Keep source changes small and auditable. Report exact commit SHA or PR link, tests actually run, limitations, and anything needing Firebase console or provider setup.

## Messaging implementation map

- Core Flutter state, local cache and server writes: `lib/core/services/messaging_service.dart`
- UI, composer, search, replies, scheduled messages, attachments, SMS: `lib/presentation/screens/messages_center.dart`
- Role-based Firestore rules: `firebase/firestore.rules`
- Storage attachment rules: `firebase/storage.rules`
- Firebase emulator regression tests: `firebase/tests/*.test.cjs`
- Firebase Cloud Functions: `functions/index.ts`
- Composite indexes: `firebase/firestore.indexes.json`
- CI validation: `.github/workflows/firestore-rules.yml`, `message-storage-rules.yml`, `flutter-validate.yml`, `cleanops-android-ci.yml`, `cleanops-validation.yml`

## Validation

For Dart and Android:
```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

For Cloud Functions:
```bash
npm --prefix functions install
npm --prefix functions run build
```

For Firestore and Storage security (with Firebase CLI, Node.js, Java installed):
```bash
npm --prefix firebase/tests install
firebase emulators:exec --project cleanops-messaging-rules-test --only firestore \
  "npm --prefix firebase/tests test"
firebase emulators:exec --project cleanops-messaging-storage-test --only firestore,storage \
  "npm --prefix firebase/tests run test:storage"
```

## Outstanding production verification

- Confirm that the tested Firestore and Storage rules, functions, and indexes are intentionally deployed in production after review.
- Test offline messages on multiple Android accounts, then reconnect; check no duplicate sends and accurate status changes.
- Test supervisor, worker, municipality, council, donor message routes and per-user read/acknowledgement on real Firebase accounts.
- Verify that `sendExternalSms` is properly configured with protected Twilio secrets and is deployed, before showing SMS as available. Provider acceptance is **not** handset delivery.
- Keep WhatsApp separate: do not claim a WhatsApp integration unless a real, authorized provider connection and webhook are present.
