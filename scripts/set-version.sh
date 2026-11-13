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
#   * README.md               — the versions in Installation, so a copied install gets this
#                               release's API: the Swift package's `from:` is the release itself,
#                               the pod's `~>` is its major line (see `replace_pod` below)
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

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
    echo "error: '$version' is not a semver version" >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Rewrites the quoted value of the line assigning `pattern` in `file`, and fails loudly if it
# matched nothing, since a silent no-op would ship a release with a stale version baked in.
replace() {
    local file="$1" pattern="$2"
    local path="$root/$file"

    VERSION="$version" perl -0777 -pi -e \
        "die qq(no assignment matching /${pattern}/ in \$ARGV\\n) unless s/^([ \\t]*${pattern}[ \\t]*=[ \\t]*)\"[^\"\\n]*\"[ \\t]*\$/\$1\"\$ENV{VERSION}\"/mg" \
        "$path"

    echo "  $file"
}

# Rewrites the `from:` of every `.package(url: "…gopay-ios-sdk.git", from: "<version>")` in
# `file` to the release, failing the same way when there is none.
replace_package() {
    local file="$1"
    local path="$root/$file"

    VERSION="$version" perl -0777 -pi -e \
        "die qq(no gopay-ios-sdk package dependency in \$ARGV\n) unless s/(\\.package\\(url: \"[^\"\n]*gopay-ios-sdk\\.git\", from: \")[^\"\n]*(\")/\$1\$ENV{VERSION}\$2/g" \
        "$path"

    echo "  $file (Swift package, from: \"$version\")"
}

# Rewrites the requirement of every `pod 'GopaySDK', '~> <major.minor>'` in `file` to the
# release's major line, `~> <major>.0`, failing the same way when there is none.
#
# The major line and not the release's own minor: `~> 3.0` takes the newest 3.x CocoaPods has,
# so a fresh install gets this release wherever it is on Trunk, and the line never asks for a
# version that is not there. That matters because Trunk is read-only from December 2, 2026:
# a release after that date exists as a Swift package only, and `~> 3.2` would then fail to
# resolve.
replace_pod() {
    local file="$1"
    local path="$root/$file"
    local line="${version%%.*}.0"

    POD_LINE="$line" perl -0777 -pi -e \
        "die qq(no GopaySDK pod requirement in \$ARGV\n) unless s/(pod 'GopaySDK', '~> )[^'\n]*(')/\$1\$ENV{POD_LINE}\$2/g" \
        "$path"

    echo "  $file (pod, '~> $line')"
}

echo "Setting version $version in:"
replace "GopaySDK.podspec" 'spec\.version'
replace "sdk/sdk/GopaySDK.swift" 'public static let version'
replace_package "README.md"
replace_pod "README.md"
