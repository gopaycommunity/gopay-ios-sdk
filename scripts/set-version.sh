#!/usr/bin/env bash
#
# Propagates a release version into the source files semantic-release doesn't know about.
#
# semantic-release owns package.json (via @semantic-release/npm) and CHANGELOG.md (via
# @semantic-release/changelog). Everything else that carries the version has to be rewritten
# here, and listed in the `assets` of @semantic-release/git so the release commit includes it:
#
#   * GopaySDK.podspec        — spec.version, what CocoaPods integrators resolve
#   * sdk/sdk/GopaySDK.swift  — GopaySDK.version, what the SDK reports at runtime
#
# Invoked automatically by @semantic-release/exec's prepareCmd. Safe to run by hand too:
#
#   ./scripts/set-version.sh 1.6.0
#
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
    echo "usage: $(basename "$0") <version>" >&2
    exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "error: '$version' is not a semver version" >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rewrites the quoted value following `pattern` in `file`, and fails loudly if it matched nothing —
# a silent no-op here would ship a release with a stale version baked in.
replace() {
    local file="$1" pattern="$2"
    local path="$root/$file"

    VERSION="$version" perl -0777 -pi -e \
        "die qq(no assignment matching /${pattern}/ in \$ARGV\\n) unless s/(${pattern}\\s*=\\s*)\"[^\"]*\"/\$1\"\$ENV{VERSION}\"/g" \
        "$path"

    echo "  $file"
}

echo "Setting version $version in:"
replace "GopaySDK.podspec" 'spec\.version'
replace "sdk/sdk/GopaySDK.swift" 'public static let version'
