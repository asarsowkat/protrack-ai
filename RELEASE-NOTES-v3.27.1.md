# ProTrackAI v3.27.1: progress by phase in monthly reports too (October 2026)

The **Progress** tab of a monthly internal report, and of a monthly client report, now shows the **Progress by phase** table, the same as a weekly report:
- each phase with its weight, planned, actual and variance;
- the weighted planned and actual;
- for site phases, the comparison with the daily reports;
- the overall progress.

**Why it was missing:** the code was already the same for weekly and monthly. But a report version saved before v3.23 had no table kept with it. That is the case for the sample monthly reports (August released, September awaiting approval). Instead of the table, these versions showed "This version was saved before progress by phase was kept with the report".

**Now:**
- **Worked out for older versions.** For such a version, the table is worked out from the updated P6 schedule in force at the end of its period: the same schedule the report was compared with. A note above the table says so.
- **Kept at approval.** When that version is approved, the table is kept with it as shown. The executive report then shows it too.
- **Nothing invented.** If no updated schedule exists up to the end of the period, nothing is worked out. In the demo, the Riyadh–Qassim August report has none: the first updated schedule is dated 20 September 2026.

Weekly reports, drafts and versions saved from v3.23 on are unchanged.

## Checks

- **Updated suite:** the intermediate milestones and progress by phase suite has 3 new checks for monthly reports (20 checks, all passing).
- **Other report suites:** E&P, baseline comparison, reporting status, executive report, margin mail and RASA all pass.
- **No server change.** On the server, a version saved after the v30 update already keeps its table.
