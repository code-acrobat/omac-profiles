# Shared helpers for the omac_profile wrapper. Sourced, not executed.

# Canonical harness id (omac names); errors on unknown.
profile_harness() {
  case "$1" in
    opencode | oc) printf 'opencode\n' ;;
    claude | claude-code) printf 'claude-code\n' ;;
    *)
      echo "omac_profile: unsupported harness: $1 (add a row in lib/profile.sh)" >&2
      return 1
      ;;
  esac
}

# Profile root per harness. opencode must stay under ~/.opencode: omac's
# data grant for it is a literal path, so that prefix is what makes profile
# dirs sandbox-visible. claude's grant follows CLAUDE_CONFIG_DIR, any path works.
profile_root() {
  local harness="$1" name="$2"
  case "$name" in
    '' | . | .. | */*)
      echo "omac_profile: invalid profile name: $name" >&2
      return 1
      ;;
  esac
  case "$harness" in
    opencode) printf '%s/.opencode/profiles/%s\n' "$HOME" "$name" ;;
    claude-code) printf '%s/.claude-profiles/%s\n' "$HOME" "$name" ;;
    *)
      echo "omac_profile: unsupported harness: $harness" >&2
      return 1
      ;;
  esac
}

# Export the env vars that branch the profile (per-harness table).
# Keep exports minimal per harness: they also steer omac's own layer
# (registry, approvals, skill-config follow XDG_CONFIG_HOME; the audit
# trail follows XDG_STATE_HOME).
profile_use() {
  local harness="$1" root="$2"
  case "$harness" in
    opencode)
      export XDG_CONFIG_HOME="$root/config" # opencode config + omac registry/approvals
      export XDG_DATA_HOME="$root/data"     # opencode.db: sessions, provider credentials
      export XDG_STATE_HOME="$root/state"   # service registration, locks, audit trail
      ;;
    claude-code)
      export CLAUDE_CONFIG_DIR="$root/config" # claude config, credentials, sessions
      ;;
  esac
}

# Create the profile skeleton. Idempotent, never overwrites existing entries.
profile_ensure() {
  local harness="$1" root="$2"
  mkdir -p "$root/config" "$root/data" "$root/state"
  case "$harness" in
    opencode)
      # Pre-created: omac grants $XDG_CONFIG_HOME/opencode and mounts the
      # approvals dir ($XDG_CONFIG_HOME/omac) into the sandbox; both exist.
      mkdir -p "$root/config/opencode" "$root/config/omac"
      ;;
  esac
  # Extension point: template seeding (opencode.json, plugins, MCP servers), cache isolation.
}
