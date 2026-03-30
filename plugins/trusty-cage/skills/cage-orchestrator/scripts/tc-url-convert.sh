#!/usr/bin/env bash
################################################################################
# SSH → HTTPS Git URL Converter
#
# Converts SSH-format git remote URLs to HTTPS format for use with trusty-cage.
# trusty-cage requires HTTPS URLs to clone repositories inside containers
# (no SSH keys available in the isolated environment).
#
# USAGE:
#   ./tc-url-convert.sh <git-remote-url>
#
# EXAMPLES:
#   ./tc-url-convert.sh git@github.com:user/repo.git
#   # Output: https://github.com/user/repo.git
#
#   ./tc-url-convert.sh https://github.com/user/repo.git
#   # Output: https://github.com/user/repo.git (passthrough)
#
# EXIT CODES:
#   0 - Success
#   1 - No URL provided
################################################################################

set -euo pipefail

_url="${1:-}"

if [ -z "$_url" ]; then
    echo "Usage: $(basename "$0") <git-remote-url>" >&2
    exit 1
fi

# Already HTTPS — passthrough
if [[ "$_url" == https://* ]]; then
    echo "$_url"
    exit 0
fi

# SSH format: git@github.com:user/repo.git → https://github.com/user/repo.git
if [[ "$_url" =~ ^git@([^:]+):(.+)$ ]]; then
    _host="${BASH_REMATCH[1]}"
    _path="${BASH_REMATCH[2]}"
    echo "https://${_host}/${_path}"
    exit 0
fi

# Unrecognized format — pass through and let the caller deal with it
echo "$_url"
