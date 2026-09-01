#!/usr/bin/env bash
# Run `pglifecycle deploy`, publish the plan, and report drift.
#
# Inputs (environment): PGL_PROJECT, PGL_OUTPUT, PGL_DUMP, PGL_ALLOW_DROP,
#   PGL_NO_PRIVILEGES, PGL_ROLE, PGL_ARGS, and the PG* connection
#   variables the CLI reads directly.
# Outputs (GITHUB_OUTPUT): plan, drift, excluded
set -euo pipefail

# An unset input still reaches the step as an empty variable, and the CLI
# reads these directly: an empty PGPORT fails to parse and an empty
# PGHOST would be used as the host. Drop them so the CLI defaults apply.
for var in PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD; do
  if [ -z "${!var:-}" ]; then
    unset "$var"
  fi
done

plan=${PGL_OUTPUT:-pglifecycle-plan.sql}
args=(deploy --output "$plan")

if [ -n "${PGL_DUMP:-}" ]; then args+=(--dump "$PGL_DUMP"); fi
if [ -n "${PGL_ROLE:-}" ]; then args+=(--role "$PGL_ROLE"); fi
if [ "${PGL_ALLOW_DROP:-false}" = true ]; then args+=(--allow-drop); fi
if [ "${PGL_NO_PRIVILEGES:-false}" = true ]; then args+=(--no-privileges); fi

# Extra flags arrive as one string and are split on whitespace, so a
# value containing spaces has to be quoted by the caller's shell rules.
if [ -n "${PGL_ARGS:-}" ]; then
  eval "args+=(${PGL_ARGS})"
fi

args+=("$PGL_PROJECT")

pglifecycle "${args[@]}"

# render_script() writes this line only when the plan includes no
# statements, and reports excluded destructive statements in the header.
drift=true
if grep -qF -- '-- no changes: the database matches the project' "$plan"; then
  drift=false
fi
excluded=$(sed -n 's/^-- destructive statements: \([0-9]*\) excluded.*/\1/p' "$plan")
excluded=${excluded:-0}
# A plan whose only changes were withheld as destructive is still drift.
if [ "$excluded" -gt 0 ]; then drift=true; fi

{
  echo "plan=${plan}"
  echo "drift=${drift}"
  echo "excluded=${excluded}"
} >> "$GITHUB_OUTPUT"

{
  echo "### pglifecycle deploy plan"
  echo
  if [ "$drift" = false ]; then
    echo "The database matches \`${PGL_PROJECT}\`."
  else
    echo '```sql'
    cat "$plan"
    echo '```'
  fi
} >> "$GITHUB_STEP_SUMMARY"
