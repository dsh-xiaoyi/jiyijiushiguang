# Roadmap

Planned work, in order. Times are local (Asia/Shanghai).

## 2026-10-25 (Sat)

- [ ] `bridge/` — receiver plugin, poller, watchdog; every host/port/user/token replaced by a placeholder
- [ ] `bridge/docs/architecture.md` — the two-leg model (live DSH session ↔ store ↔ file poller ↔ DSH route)
- [ ] `bridge/docs/security.md` — loopback-only, one token per pair, ACL hardening, threat model
- [ ] `bridge/docs/permissions.md` — exactly which permissions each piece needs, and why
- [ ] `bridge/docs/tokens.md` — why tokens are per pair, how to rotate them without breaking the fleet
- [ ] `bridge/docs/troubleshooting.md` — the traps we actually hit (random ports, list binding, BOM, ACL)

## 2026-10-25 (Sat, evening)

- [ ] `guard/` — the four rule families: backup-first, verify-after-change, install re-check, rollback
- [ ] `guard/checks/` — encoding + parse + command-existence + parity checks (configurable)

## 2026-10-26 (Sun, morning)

- [ ] `rescue/docs/diagnose.md` — where the evidence lives: plugin-manager logs, patch backups,
      `package.json`, session cache sizes, `fiberPhase`
- [ ] `rescue/docs/decision-tree.md` — symptom → evidence → action
- [ ] `rescue/docs/rollback.md` — R1 config, R2 plugin, R3 disable-only, R4 database, R5 whole profile
- [ ] `rescue/docs/winrm.md` — remote forensics: setup, credential handling, the three execution modes
      and the traps in each

## 2026-10-26 (Sun, afternoon)

- [ ] `memory-guide/docs/01-install-sql.md` … `07-privacy.md` — tutorials only, no data
- [ ] `memory-guide/docs/03-rules.md` — the rule-library method (the most valuable part)

## Before going public

- [ ] `tools/scrub-audit.ps1` returns 0 on the whole tree
- [ ] five random files read end to end by a human
- [ ] `docs/SECURITY.md` present and honest
- [ ] no data exports, logs, screenshots or session dumps
- [ ] git history starts from the final shape (never "add then delete a secret")
