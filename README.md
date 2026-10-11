# omac_profile — named profiles for agent harnesses

One generic wrapper that gives an agent harness its own config,
credentials and state per named profile, so e.g. a company LLM account
never shares credentials with your personal setup. There is exactly one
script, `omac_profile`; no per-harness wrappers.

**Fully supported today: opencode v2.** More harnesses will follow:
harness specifics are one table row each in `lib/profile.sh`.

## Install

```sh
ln -s "$PWD/bin/omac_profile" ~/bin/omac_profile
```

Requires GNU `realpath`, opencode v2, and omac ≥ v0.10.0. Older omac
versions cannot run opencode v2 inside the sandbox.

## Usage

```
omac_profile <harness> <name> <plain|omac|cleanup|sync> [--] [args...]
```

Two variants to start with; both open the profile `work`:

```sh
omac_profile opencode work plain     # TUI straight on your machine, no sandbox
omac_profile opencode work omac      # TUI inside the omac sandbox
```

- **plain** runs opencode directly. The wrapper adds the upstream
  `--standalone` flag, so every run gets a private per-run server on an
  OS-assigned port that dies with the session. The profile never touches
  the shared service on port 49374. Plain mode covers the TUI and the
  `api`/`auth` commands (see the rough edges below for other
  subcommands).
- **omac** runs through the omac sandbox: sidecars, approvals, network
  policy. The first run creates the profile; a workdir without
  registered skills starts the sandbox without sidecars, which is
  normal.

More examples:

```sh
omac_profile opencode work omac -- api get /api/info
omac_profile opencode work plain -- --version       # v2.x, private server
omac_profile opencode work omac continue            # resume last session
```

## Seed from your host setup

`sync` fills a profile from what is already set up on the host. It
never overwrites a file that exists in the profile, so re-running it
only adds what is missing (`rsync` when available, plain `cp` otherwise):

```sh
omac_profile opencode work sync
```

- your host opencode config (`~/.config/opencode/`) into
  `<profile>/config/opencode/`: `opencode.json`, `auth.json`, plugins,
  themes. `service.json` is left out so the profile never points at the
  host's service.

omac's own layer (approvals, registry) is not copied: every profile
approves for itself and gets the built-in skills on its first run.

## Throwaway profiles

A profile is the blast radius of a session: config, provider
credentials, sessions, skills, approvals and the audit trail all live
in its directory. When something went wrong in a session (a
prompt-injected agent, a leaked credential), delete the profile and
start clean:

```sh
omac_profile opencode work cleanup    # removes ~/.opencode/profiles/work entirely
```

Stop the session first; cleanup only removes files, never running
processes. Running it twice is fine: the second run reports that there
is nothing to remove and exits 0.

## What a profile keeps where

| harness  | root                       | branched by                                          |
|----------|----------------------------|------------------------------------------------------|
| opencode | `~/.opencode/profiles/<n>` | `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` |

The opencode root sits under `~/.opencode/` on purpose: omac grants that
prefix to the opencode sandbox, so profile dirs are sandbox-visible
without any omac change (its data grant for `~/.local/share/opencode` is
a literal path and would not follow `XDG_DATA_HOME`).

Contents of a profile, for `work` at `~/.opencode/profiles/work/`:

| path | contents |
|------|----------|
| `config/opencode/opencode.json` | profile-global config: MCP servers, plugins, model, theme |
| `config/opencode/skills/` | skills for this profile only |
| `config/opencode/plugins/` | plugins for this profile only |
| `config/omac/` | omac registry + approvals for this profile |
| `data/opencode/opencode.db` | sessions and provider credentials (`opencode auth login` lands here) |
| `data/opencode/log/` | opencode logs |
| `state/opencode/` | service registration |
| `state/omac/audit/audit.jsonl` | omac audit trail for this profile |

## What a profile covers (and what it does not)

The concerns a profile exists for:

1. **Credentials and accounts.** Each profile owns its `opencode.db`, so
   provider logins (company vs personal) never share a database.
2. **Blast radius.** Sessions, config, plugins, skills, approvals and the
   audit trail all live under the profile root. After a suspicious
   session, `cleanup` removes the exposure in one step.
3. **Per-profile omac layer.** Approvals, skill registry and audit trail
   branch off via `XDG_CONFIG_HOME`/`XDG_STATE_HOME`; one profile's
   grants never satisfy another's.
4. **Service isolation.** Plain mode's `--standalone` gives every run a
   private server; profiles never touch the shared host service.

### Stateful MCP servers on the host are shared

A `remote` (HTTP) MCP server runs on the host and keeps its own data: a
memory server's knowledge graph, for example. Every profile whose
`opencode.json` points at the same URL **shares that data** — a company
profile would see the personal profile's notes. Neither omac nor this
wrapper can split one host process's data directory per profile.

- Accept the sharing on purpose (fine for stateless lookups like
  context7), or
- Run one instance per profile: its own data dir, its own loopback port,
  that port in `network.open_port` in the machine-global sandbox grants
  (`~/.config/omac/sandbox-profiles/default.json`), and the per-profile
  URL in the profile's config.

## Caches

Tool caches (npm, Go, pip, cargo, XDG) are deliberately not part of a
profile. omac owns them as the single source of truth: a wrapper would
have to track every cache variable of every toolchain, always one tool
release behind omac, and would shadow the variables omac injects.

What omac does, always on in every omac-mode session:

- `NPM_CONFIG_CACHE`, `GOCACHE`, `GOMODCACHE`, `PIP_CACHE_DIR`,
  `CARGO_HOME` and `XDG_CACHE_HOME` are pointed at one directory per
  cache scope under `~/.cache/omac/`; the host's own caches are never
  written from the sandbox.
- The default scope is already `workdir`: every project gets its own
  cache. A work profile in `~/work/...` and a personal profile in
  `~/proj/...` therefore never share an npm (or Go, pip, cargo) cache,
  with zero configuration:

  ```sh
  cd ~/work/repo && omac start opencode        # this project's cache
  cd ~/proj/photo-tool && omac start opencode  # another project, another cache
  ```

Things to know:

- Two profiles working in the **same project** share that project's
  cache: the scope keys on the directory, not the profile. Use separate
  checkouts if that matters.
- Caches live under `~/.cache/omac/`, outside the profile root, so
  `cleanup` does not delete them; `omac cache clear` in the project
  removes that project's cache.
- `--cache-scope config` keys on the host launcher config file, which
  all profiles share; it does not produce per-profile caches.
  `--cache-scope global` shares one cache everywhere; both are opt-in
  sharing, not isolation. `--ephemeral-cache` throws the cache away at
  session end.

If cache separation is your only concern, the default already gives it
to you; profiles add the credential and blast-radius layer on top. Note
that plain mode (no sandbox) runs with your host environment as-is, so
omac's cache redirects do not apply there.

## Tuning config (MCP, plugins, model)

Edit the profile's `config/opencode/opencode.json`. It uses the same
schema as opencode's normal config file, so the easiest start is a copy
of your default one:

```sh
cp ~/.config/opencode/opencode.json ~/.opencode/profiles/work/config/opencode/opencode.json
```

For orientation, the non-profile (default) locations on a Linux box:

| what | default path |
|------|--------------|
| config file | `~/.config/opencode/opencode.json` |
| data (database, logs) | `~/.local/share/opencode/` |
| service registration | `~/.local/state/opencode/` |
| omac approvals + registry | `~/.config/omac/` |

An MCP example in opencode's native schema — prefer `remote` (HTTP)
servers, which run outside the sandbox:

```json
{
  "mcp": {
    "context7": { "type": "remote", "url": "https://mcp.context7.com/mcp" },
    "memory": { "type": "remote", "url": "http://127.0.0.1:3719/mcp" }
  }
}
```

**Prefer HTTP (remote) MCP servers.** A `local` server is spawned inside
the sandbox and has to download itself at spawn time, which fails through
omac's filtering proxy on older toolchains (verified: npm 9 / node 18 →
`407` / `Connection closed`); its state also grows inside shared dirs.
Run the MCP server on the host instead, where it can hold your secrets,
and let the profile talk to its loopback URL:

1. Host: start the MCP server on `127.0.0.1:<port>` (stdio servers can
   be wrapped with any HTTP bridge).
2. Profile: `"type": "remote", "url": "http://127.0.0.1:<port>/mcp"`.
3. Sandbox policy (`~/.config/omac/sandbox-profiles/default.json`,
   machine-global): add the port to `network.open_port`. Ad-hoc connects
   can also be approved through the network prompt.

There is deliberately no install skill for the local→HTTP MCP
conversion: it would handle your MCP tokens inside a model session
(leak surface). Do the steps above by hand, or have your local model
run them against this section as the recipe.

opencode combines config from these places:

1. **Profile-global** — `<profile>/config/opencode/opencode.json`: the
   per-profile place for MCP servers, plugins, model, theme.
2. **Project** — `opencode.json` in your project or a parent directory:
   shared by every profile, because the file lives in the code rather
   than in the profile.
3. **Shared, not per-profile** — the `~/.claude` and `~/.agents`
   compatibility dirs are home-based, and omac's cache dir is shared by
   design.

Verify what opencode actually parsed, from inside the sandbox:

```sh
omac_profile opencode work omac -- debug config   # shows the "mcp" block
```

Known rough edges (opencode v2.0.18):

- `opencode mcp list` on a freshly started service printed
  `No MCP servers configured` even with the config file in place, while
  `debug config` shows the same servers correctly. Treat
  `debug config` as the check.
- Plain mode prepends `--standalone`, which some subcommands reject
  (verified: `mcp`). Without the flag those commands fall back to the
  fixed port 49374 and hang. Run CLI subcommands in omac mode, where
  the service port is pinned per run.

## About

Architecture, integration details and debugging live in
[AGENTS.md](./AGENTS.md).
