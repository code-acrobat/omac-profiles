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

Requires GNU `realpath` and opencode v2. Sandboxed mode needs an omac
built with the service-port hotfix (TNG/oh-my-agentic-coder#329).

## Usage

```
omac_profile <harness> <name> <plain|omac|cleanup> [--] [args...]
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

An MCP example in opencode's native schema, one remote and one local
server:

```json
{
  "mcp": {
    "context7": { "type": "remote", "url": "https://mcp.context7.com/mcp" },
    "playwright": { "type": "local", "command": ["npx", "-y", "@playwright/mcp@latest"] }
  }
}
```

**Local servers inside the sandbox:** `npx -y <pkg>` servers download
from npm's registry at spawn time, through omac's filtering proxy. Older
toolchains don't authenticate to that proxy (verified failing: npm 9 on
node 18 — the server dies with `Connection closed` or `407`), so vendor
the package into the profile instead:

```sh
prefix=~/.opencode/profiles/work/data/mcp/playwright
mkdir -p "$prefix" && npm install --prefix "$prefix" @playwright/mcp
```

Then point the `command` at the installed entry (check `bin` in the
package's `package.json`):
`"command": ["node", "<prefix>/node_modules/<pkg>/<entry>"]`.
The profile data dir is granted to the sandbox, needs no network at
spawn, and is removed by `cleanup`.

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

Architecture, the omac hotfix integration and debugging live in
[AGENTS.md](./AGENTS.md).
