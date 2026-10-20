# 记忆旧时光 · jiyijiushiguang

**Tools and notes for running a fleet of [DeepSeek Harness](https://github.com/deepseek-ai) instances
on Windows: cross-machine messaging, a shared memory store, guard rules, and a rescue playbook.**

> 一套让多台 DSH 协同工作、共享记忆、并且出问题能救回来的工具与方法。
> 面向被"上下文过长"困扰的 DSH 用户 —— 让记忆落在外面的数据库里，而不是靠一次会话撑住。

**Status: work in progress.** The code and guides are being prepared (target: 2026-10-25/26).
Nothing here is usable yet; watch the repo or the issues tab.

---

## What this will contain

| Folder | What it is | Who it is for |
|---|---|---|
| `bridge/` | Cross-machine messaging: a DSH plugin (receiver) + a poller (sender) + a watchdog | Anyone running DSH on more than one machine |
| `guard/` | A structure/rule gate: backup-first, verify-after-change, install re-check, rollback | Anyone letting an AI manage their scripts |
| `rescue/` | DSH fault diagnosis and rollback playbook, incl. reading DSH logs over WinRM | Anyone who has broken their DSH at least once |
| `memory-guide/` | Tutorials only: install your own SQL Server, the schema, the rule-library method, sync/search, handoff | Anyone whose DSH keeps running out of context |

**No data, ever.** This repository contains code, templates and documentation. It does not contain
anyone's memories, credentials, hostnames or logs. Configuration examples use placeholders
(`HOST-A`, `10.0.0.x`, `<PAIR-TOKEN-A-B>`, `<DSH_HOME>`).

## Design principles (learned the hard way)

1. **Loopback only.** The receiver listens on `127.0.0.1`; peers authenticate with one token per pair.
   No cloud relay, no inbound ports.
2. **Self-discovery.** DSH picks a random web port on every start; every client discovers it instead of
   hard-coding one.
3. **Backup before change, verify after change.** Every file we touch leaves a
   `.bak-before-<reason>-<timestamp>` next to it.
4. **One change at a time.** Two simultaneous edits make bisecting impossible.
5. **Secrets never transit chat, logs, or command lines.** They live in a vault and are passed as files
   or through the clipboard.

## Safety

These are personal toolsets, not a product. No support promise, no warranty. They were written for a
specific three-machine Windows topology and are being generalised as fast as time allows.
Read `docs/SECURITY.md` (coming) before you point anything at a machine you care about.

## License

MIT — see [LICENSE](LICENSE).
