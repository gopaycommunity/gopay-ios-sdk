#!/usr/bin/env bash
#
# Switches the demo app (example/example.xcodeproj) between the SDK in this checkout and the
# released one.
#
#   local     the local Swift package at the repo root, what development and the committed project
#             use
#   released  https://github.com/gopaycommunity/gopay-ios-sdk.git at exactly the version in
#             GopaySDK.podspec, the package an integrator gets by following the README
#
#   ./scripts/demo-sdk-source.sh released
#   ./scripts/demo-sdk-source.sh local
#
# Only the package reference in project.pbxproj changes; the object IDs stay the same, so switching
# back to `local` leaves no diff. Running it twice is a no-op. Commit the project in `local` only.
#
# Assumes the demo has this one remote package: switching back replaces the whole
# XCRemoteSwiftPackageReference section. If the demo gains another package, match the section entry
# by the ID 8B8AF6E62D9154A400E91722 instead.
#
set -euo pipefail

source="${1:-}"
if [[ "$source" != "local" && "$source" != "released" ]]; then
    echo "usage: $(basename "$0") local|released" >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$root/example/example.xcodeproj/project.pbxproj"
resolved="$root/example/example.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
repository="https://github.com/gopaycommunity/gopay-ios-sdk.git"

version="$(sed -nE 's/^[[:space:]]*spec\.version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$root/GopaySDK.podspec")"
if [[ -z "$version" ]]; then
    echo "error: no spec.version in GopaySDK.podspec" >&2
    exit 1
fi

# First back to `local` whatever the current state, then on to `released` if asked. The perl
# substitutions die when they match nothing, so a project Xcode has reshaped fails loudly instead
# of being half switched; the project is only replaced once every substitution went through.
switched="$(mktemp "$project.XXXXXX")"
trap 'rm -f "$switched"' EXIT
SOURCE="$source" VERSION="$version" REPOSITORY="$repository" perl -0777 -p -e '
    my $id = "8B8AF6E62D9154A400E91722";
    my $remote_comment = qq(XCRemoteSwiftPackageReference "gopay-ios-sdk");

    if (/isa = XCRemoteSwiftPackageReference;/) {
        s{\Q$id /* $remote_comment */,\E}{$id /* XCLocalSwiftPackageReference ".." */,}
            or die "packageReferences: no remote reference to switch back\n";
        s{/\* Begin XCRemoteSwiftPackageReference section \*/\n.*?/\* End XCRemoteSwiftPackageReference section \*/}
         {/* Begin XCLocalSwiftPackageReference section */\n\t\t$id /* XCLocalSwiftPackageReference ".." */ = {\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = ..;\n\t\t};\n/* End XCLocalSwiftPackageReference section */}s
            or die "no XCRemoteSwiftPackageReference section to switch back\n";
        s{\n\t\t\tpackage = \Q$id /* $remote_comment */\E;}{}
            or die "GopaySDK product: no package line to drop\n";
    }

    if ($ENV{SOURCE} eq "released") {
        s{\Q$id /* XCLocalSwiftPackageReference ".." */,\E}{$id /* $remote_comment */,}
            or die "packageReferences: no local reference to switch\n";
        s{/\* Begin XCLocalSwiftPackageReference section \*/\n.*?/\* End XCLocalSwiftPackageReference section \*/}
         {/* Begin XCRemoteSwiftPackageReference section */\n\t\t$id /* $remote_comment */ = {\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = \"$ENV{REPOSITORY}\";\n\t\t\trequirement = {\n\t\t\t\tkind = exactVersion;\n\t\t\t\tversion = $ENV{VERSION};\n\t\t\t};\n\t\t};\n/* End XCRemoteSwiftPackageReference section */}s
            or die "no XCLocalSwiftPackageReference section to switch\n";
        s{(isa = XCSwiftPackageProductDependency;\n)(\t\t\tproductName = GopaySDK;)}{$1\t\t\tpackage = $id /* $remote_comment */;\n$2}
            or die "GopaySDK product: no dependency to point at the remote package\n";
    }
' "$project" > "$switched"
cat "$switched" > "$project"

if [[ "$source" == "local" ]]; then
    # Package.resolved only ever pins the released SDK; the local package has no dependencies.
    rm -f "$resolved"
    echo "Demo builds against the local SDK."
else
    echo "Demo builds against $repository at $version."
fi
