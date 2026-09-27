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
omac_profile <harness> <name> <plain|omac> [--] [args...]
```

```sh
omac_profile opencode work omac                     # sandboxed TUI
omac_profile opencode work omac -- api get /api/info
omac_profile opencode work plain -- --version       # private per-run server
omac_profile opencode work omac continue
```

`plain` runs the harness directly; `omac` runs it through the omac
sandbox. First run creates the profile directory.

## Profile layout

| harness  | root                       | branched by                                          |
|----------|----------------------------|------------------------------------------------------|
| opencode | `~/.opencode/profiles/<n>` | `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` |

The opencode root sits under `~/.opencode/` on purpose: omac grants that
prefix to the opencode sandbox, so profile dirs are sandbox-visible
without any omac change (its data grant for `~/.local/share/opencode` is
a literal path and would not follow `XDG_DATA_HOME`).

Architecture, the omac hotfix integration and debugging live in
[AGENTS.md](./AGENTS.md).
