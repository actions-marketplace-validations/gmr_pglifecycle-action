#!/usr/bin/env bash
# Download a pglifecycle release binary and put it on PATH.
#
# Inputs (environment):
#   PGL_VERSION     release tag to install, or "latest"
#   PGL_REPOSITORY  owner/repo to install from
#   GH_TOKEN        token used for the release API calls
# Outputs (GITHUB_OUTPUT): version, path
set -euo pipefail

repository=${PGL_REPOSITORY:-gmr/pglifecycle}
version=${PGL_VERSION:-latest}
api="https://api.github.com/repos/${repository}"

# GitHub-hosted runners share outbound addresses, so an unauthenticated
# call can land on an exhausted 60/hour bucket. Authenticate when a
# token is present and accept the risk otherwise.
auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

case "${RUNNER_OS}:${RUNNER_ARCH}" in
  Linux:X64)    target=x86_64-unknown-linux-gnu ;;
  Linux:ARM64)  target=aarch64-unknown-linux-gnu ;;
  macOS:X64)    target=x86_64-apple-darwin ;;
  macOS:ARM64)  target=aarch64-apple-darwin ;;
  *)
    echo "::error::pglifecycle publishes no binary for ${RUNNER_OS}/${RUNNER_ARCH}" >&2
    exit 1
    ;;
esac

if [ "$version" = latest ]; then
  # /releases/latest ignores prereleases and 404s while a project has
  # only prereleases, so fall back to the newest release of any kind.
  tag=$(curl -fsSL "${auth[@]}" "${api}/releases/latest" 2>/dev/null | jq -r .tag_name || true)
  if [ -z "$tag" ] || [ "$tag" = null ]; then
    tag=$(curl -fsSL "${auth[@]}" "${api}/releases?per_page=1" | jq -r '.[0].tag_name // empty')
    if [ -z "$tag" ]; then
      echo "::error::${repository} has published no releases; set the 'version' input" >&2
      exit 1
    fi
    echo "::warning::${repository} has no stable release; installing prerelease ${tag}"
  fi
else
  tag=$version
fi

prefix="${RUNNER_TOOL_CACHE:-$HOME/.cache}/pglifecycle/${tag}/${target}"
if [ ! -x "${prefix}/pglifecycle" ]; then
  url="https://github.com/${repository}/releases/download/${tag}/pglifecycle-${target}.tar.gz"
  echo "Installing pglifecycle ${tag} (${target})"
  mkdir -p "$prefix"
  # No checksum file is published alongside the assets; the download is
  # over TLS from the release the tag names.
  curl -fsSL "$url" | tar xz -C "$prefix"
  chmod +x "${prefix}/pglifecycle"
fi

echo "$prefix" >> "$GITHUB_PATH"
installed=$("${prefix}/pglifecycle" --version)
echo "${installed} installed to ${prefix}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${tag}"
    echo "path=${prefix}/pglifecycle"
  } >> "$GITHUB_OUTPUT"
fi
