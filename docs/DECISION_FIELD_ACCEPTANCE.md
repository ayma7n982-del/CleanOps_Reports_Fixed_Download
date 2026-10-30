# Decision hub field acceptance evidence

Automated QA is not evidence of a physical phone or production end-user session.
No phone, ADB connection, or L2/L3/L4/supervisor sign-in session is available to this
agent environment. Do not mark the following cases passed without the evidence.

## Physical Android cases (pending actual device)

Record APK commit, Android version, device model, time, role, and result. Do not
record passwords. Use designated test accounts and a designated test group whose
supervisor is participating; never broadcast test actions to operational staff.

1. L2 sees only its municipality; L3/L4 see their permitted scope; supervisor and
   worker cannot open the hub. Open every tab, charts, and PDF entry.
2. At narrow phone width and large system font, select 7/14/30 days and one/all
   groups. Verify numerical labels agree with the exported PDF selected scope.
3. Issue one PPE test directive to the participating test group. Record decision
   ID and server-issued state. On the supervisor device verify live reception,
   acknowledge, then complete with a clearly marked test evidence note. Reopen on
   management device and verify all server timestamps and the final status.
4. Turn on airplane mode before issuing a different test directive. Confirm the
   local pending state, not server confirmation. Close/reopen the app while still
   offline. Reconnect and verify exactly one document with the same decision ID,
   one supervisor banner and confirmed state. Reconnect a second time and verify
   no duplicate. Check a rejected out-of-scope request never shows success.

Retain these designated test decisions as explicitly marked audit history; do not
delete real records or alter actual field operations to manufacture a passing test.

## PDF acceptance

`decision-acceptance.yml` reads minimal production fields with protected service
credentials and never writes to Firebase. It removes original names/identifiers,
contact data and notes. Only generated sanitized PDF reports are uploaded for one
day; temporary source JSON is not uploaded. These administrative reads do not
validate end-user permissions or native Android offline persistence.

Production PDFs keep actual available counts, statuses and weights, including empty
sources and capped reads. Missing status-event history and assumed 08:00–16:00
shift are disclosed. Separate `STRESS_SYNTHETIC_*` reports use 24 groups, 288
workers, long Arabic group/location names and long decision cards. Never describe
these synthetic groups as actual production records. Render every generated page;
inspect dense pages, section transitions, charts, exact values and footer bounds.
