#!/usr/bin/env bash
# Post or update one sticky pull request comment holding the plan.
#
# Inputs (environment): PGL_PROJECT, PGL_PLAN, PGL_DRIFT, PGL_EXCLUDED,
#   GH_TOKEN, and the GitHub context variables.
set -euo pipefail

pr=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")
if [ -z "$pr" ]; then
  echo "Not a pull request event; skipping the comment"
  exit 0
fi

marker="<!-- pglifecycle-deploy:${PGL_PROJECT} -->"
body=$marker$'\n'"### pglifecycle deploy plan — \`${PGL_PROJECT}\`"$'\n\n'

if [ "$PGL_DRIFT" = false ]; then
  body+="No changes: the database matches the project."$'\n'
else
  if [ "$PGL_EXCLUDED" -gt 0 ]; then
    body+="⚠️ ${PGL_EXCLUDED} destructive statement(s) were excluded from this plan."$'\n\n'
  fi
  # A comment body is capped at 65536 characters; keep well inside it
  # and point at the artifact for the rest.
  sql=$(head -c 60000 "$PGL_PLAN")
  if [ "$(wc -c < "$PGL_PLAN")" -gt 60000 ]; then
    sql+=$'\n-- (truncated; see the workflow run for the full plan)'
  fi
  body+='```sql'$'\n'"${sql}"$'\n''```'$'\n'
fi

id=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${pr}/comments" --paginate \
  --jq "map(select(.body | startswith(\"${marker}\"))) | .[0].id // empty" | head -n1)

if [ -n "$id" ]; then
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" \
    -f body="$body" --silent
  echo "Updated comment ${id} on #${pr}"
else
  gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${pr}/comments" \
    -f body="$body" --silent
  echo "Commented on #${pr}"
fi
