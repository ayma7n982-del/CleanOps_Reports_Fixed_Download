# Worker account and attendance linkage

The user profile is authoritative for account-backed workforce. Its operational
attendance projection is `operations/{uid}`, with `userId == uid`,
`rosterSource == users`, and `_entity == worker`. Provisioning, editing,
transferring, swapping, freezing, activation and deactivation write the profile
and projection in the same Firestore transaction. No trigger or paid backend is
required. Historical attendance documents are not rewritten.

The supervisor listens to the complete worker query for their group. Each
snapshot replaces the scoped cached roster, including an empty snapshot after
a worker leaves. Cache keys include both the account and group. Temporary
coverage decisions remain an overlay and do not change permanent assignments.

Each online municipality refresh repairs older workforce projections from the
latest profile, read again within a transaction. It resolves imported group
numbers only when unambiguous within that municipality, and retires duplicate
import rows only with an explicit unique employee ID. It never matches people
by name. Repeated repairs leave matching documents untouched.

## Validation

- Regression tests cover UID identity, transfer visibility, imported-worker
  deduplication, frozen/deleted states, privacy, and an empty offline cache.
- The Firestore emulator suite includes account + projection provisioning,
  atomic transfer, rollback on denied account mutation, L4 deactivation, and
  rejected spoofed projections and out-of-municipality profile reads.
- Flutter analysis, the full Flutter suite, and the Android APK must pass on the
  exact final commit in GitHub Actions before release. Local Flutter execution
  was blocked by automatic review; no local APK result is claimed.

## Production deployment plan — approval required

1. Review the final commit and successful emulator / Flutter / Android CI runs.
2. Approve deployment of `firebase/firestore.rules` to project `nrc-aid`.
3. Run the existing manual `firestore-deploy.yml` on the reviewed main commit.
   It repeats the full emulator suite before using the protected Firebase secret.
   No Cloud Functions, indexes, SMS, or account deletion is deployed.
4. Install the APK from that exact commit. Sign in with the municipality account
   online once to trigger the automatic legacy repair.
5. With two supervisors, create and transfer one test worker. Confirm they leave
   the first roster and enter the second, with the same UID. Verify the empty
   old roster after restarting offline, and verify freeze/deactivation hides them.
6. Preserve existing attendance history. If the rollout fails, stop distribution
   and restore the preceding reviewed client/rules only after checking other
   concurrent changes; do not roll back unrelated fixes.

Rules changes are limited to scoped L2 document reads already allowed as list
queries, the optional group display name at workforce creation, and L4 writes
of a projection whose identity and every operational field match the workforce
profile after the atomic commit. Supervisor read scopes are unchanged.
