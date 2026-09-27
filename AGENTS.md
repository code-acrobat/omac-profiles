# AGENTS.md

Guidance for agents working in this repo later (debugging, extending).

## What this repo is, and why

opencode v2 is client/server: the TUI connects to a background service that
owns `opencode.db` (sessions, provider credentials). One shared service per
machine binds a fixed default port (49374). The wrapper "branches off" a
named profile by pointing the harness's config/data dirs at
`~/.opencode/profiles/<name>/` (or the per-harness root below), giving each
profile its own database, config and skills.

One generic `omac_profile` script serves every harness; there are no
per-harness wrappers:

```
omac_profile <harness> <name> <plain|omac> [--] [args...]
```

- `plain` runs the harness directly. opencode gets `--standalone` prepended
  (upstream v2 flag, not a patch: private per-run server on an OS-assigned
  port that dies with the client, so the profile never collides with the
  shared service on 49374). Skipped if the user passes
  `--server`/`--standalone` themselves.
- `omac` runs through the omac sandbox. After the wrapper's `--`, args are
  harness args (`omac start <harness> -- <args>`). Without `--`: no args =
  TUI, a leading `-flag` goes to `omac start`, a leading word in
  {start, continue, resume, serve} is an omac subcommand.

## Where the omac hotfix comes in

- Issue TNG/oh-my-agentic-coder#328, fix PR #329 ("pin opencode v2
  background service to a granted port"), installed locally as
  `~/.local/bin/omac` (0.1.0-dev from the fix branch).
- Without it, the sandboxed v2 service tries to bind 49374 inside
  Landlock (Linux MAC sandbox) and dies with `EACCES`, exit 1.
- The hotfix picks a free loopback port P, seeds a private opencode
  config with `{"port": P}`, sets `OPENCODE_CONFIG_DIR` and
  `XDG_STATE_HOME` to sandbox-tmp dirs, and grants `--open-port P`.
- The wrapper only supplies the profile XDG dirs. It must never set
  `OPENCODE_CONFIG_DIR` itself — inside the sandbox, the pin owns it.
- claude needs no hotfix: no background service (`ServerLaunch: nil`),
  and omac's `HomeEnv: CLAUDE_CONFIG_DIR` re-grants the sandbox path.

## The harness table

opencode v2 is the initial, fully supported harness; more harnesses
will follow as one table row each. Everything harness-specific lives in
`lib/profile.sh`:

| harness     | root                         | env exports (`profile_use`)            | plain prelude    |
|-------------|------------------------------|----------------------------------------|------------------|
| opencode    | `~/.opencode/profiles/<n>`   | XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME | `--standalone` |
| claude-code | `~/.claude-profiles/<n>`     | CLAUDE_CONFIG_DIR                      | (none)           |

Adding a harness = one row each in `profile_harness` (alias
normalization), `profile_root`, `profile_use`, `profile_ensure`, plus the
plain-mode exec branch in `bin/omac_profile`. Candidates: codex
(`CODEX_HOME`), copilot (`COPILOT_HOME`), pi (`PI_CODING_AGENT_DIR`),
codewhale (`CODEWHALE_HOME`) — omac already forwards and re-grants each of
these (`HomeEnv` in omac's harness descriptors).

## Design decisions (do not regress)

1. Profile root under `~/.opencode/` for opencode: omac grants that prefix
   to the sandbox (Landlock path rules cover children), so profile data,
   registry and approvals are sandbox-visible with zero omac changes.
   Anything outside the prefix would be forwarded but denied (EACCES).
2. `config/omac` must be a REAL directory, never a symlink: omac mounts
   the approvals-store root (`$XDG_CONFIG_HOME/omac`) into the sandbox
   (bwrap, its launcher); a symlink destination resolves outside the
   container mount tree and bwrap fails with
   `Can't create file at .../config/omac: No such file or directory`.
   `profile_ensure` replaces a stray symlink with a real dir.
3. Full branch-off for omac's own layer: registry, skill-config, prefs and
   approvals resolve under `$XDG_CONFIG_HOME/omac` when set, so every
   opencode profile gets its own skills and approvals by construction.
   Built-in skills auto-provision on first run; approvals re-ask per
   profile. Intentional: a profile carries only the skills that apply.
4. claude exports stay minimal (`CLAUDE_CONFIG_DIR` only): claude's own
   files stay in its config home and omac's registry layer stays
   machine-global for claude profiles (the claude binary is not installed
   on the test machine — verify before adding more exports, and keep
   omac's `omac/` dir out of the claude home).
5. `XDG_STATE_HOME` export (opencode) isolates service registration, locks
   and the audit trail: profile runs audit to
   `<profile>/state/omac/audit/audit.jsonl` instead of the central
   `~/.local/state/omac/audit/`. Per-profile trails are intentional under
   branch-off; know where to look when reviewing.
6. `XDG_CACHE_HOME` is not redirected: caches are not secret and sharing
   avoids re-downloads. Extension point for cache isolation and for
   opencode.json/plugin/MCP seeding: `profile_ensure()` in
   `lib/profile.sh`.

## Debugging

Symptom → cause:

- `permission denied 127.0.0.1:49374` inside omac → local omac build
  predates the hotfix; rebuild from the fix branch.
- `bwrap: Can't create file at .../config/omac` → symlink regression,
  see decision 2.
- `omac: unknown subcommand ...` from omac mode → arg routing; harness
  args must follow `--` (see interface above).
- `unregistered skills found in this workdir` → the workdir ships skill
  dirs this profile's registry does not know (omac's own repo ships
  `.opencode/skills/{echo-rest,self-audit}`). Unrelated to profiles; test
  in a separate scratch workspace or register the skill.
- `omac_profile: unsupported harness` → add a row in `lib/profile.sh`.
- Plain wrapper hits `EADDRINUSE` / ~15s incumbent timeout → something
  else took 49374, i.e. `--standalone` was skipped.
- claude mode exits 127 → claude CLI not installed.

Verify:

```sh
bash -n bin/omac_profile lib/profile.sh
omac_profile opencode <name> plain -- --version          # v2.x
cd <clean workdir> && omac_profile opencode <name> omac -- api get /api/info
# expect {"urls":["http://127.0.0.1:<pinned-port>"]}, EXIT=0,
# and sha256sum ~/.local/state/opencode/service.json unchanged
```

Standing rule: never run `opencode service set/unset/stop/restart` or
`pkill 'serve --service'` in the host environment — the shared host
service on 49374 may back an active session.

## Repo hygiene

Keep this repo standalone: it is meant to be cloned on its own, and it
never belongs inside another repository's tree (in particular not
inside the omac checkout, where `git status` would pick it up as
untracked noise). Before publishing changes, re-scan file content and
history for personal data (`grep -rniE '<your patterns>' .` +
`git log -p`).
