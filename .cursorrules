# WeOwn `ai` — Agent Rules (pointer)

The canonical agent rule set for this repo is **`AGENTS.md`** at the repo root.
Read it now — before any other action — and obey it for the whole session.
Full review/compliance checklist: `.github/copilot-instructions.md`.

If you read nothing else, these three rules are absolute:

1. **THIS REPO IS PUBLIC** on github.com. Never commit secrets, API keys, real
   IPs, cluster/bucket/DNS identifiers, or PII — placeholders only
   (`<CLUSTER_NAME>`, RFC 5737 `203.0.113.x`, `example.com`). History is forever:
   a value committed once requires rotation + `git filter-repo`.
2. **Never read a secret into agent context.** No `cat .env`, `env`/`printenv`,
   `docker inspect` / `docker exec ... env`, `kubectl get secret -o yaml`,
   Infisical/Vault/keychain reads, `/proc/*/environ`, shell history. Anything
   that enters context is sent to a model API and persists in transcripts — it
   cannot be un-read. Need a secret for a task? Write a script with `read -rs`
   prompts and hand it to the human to run (Secure Handoff — see `AGENTS.md`).
3. **#OnlyHumanApproves**: never push, merge, deploy, `tofu apply`, or touch
   production without explicit human approval.
