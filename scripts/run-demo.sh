#!/usr/bin/env bash
#
# Builds the example app and launches it on a simulator with the gateway settings from `.env`,
# so a demo run needs no source edit and no scheme edit.
#
#   ./scripts/run-demo.sh                      # first booted simulator
#   ./scripts/run-demo.sh -d 'iPhone 17 Pro'   # a specific simulator, booting it if needed
#   ./scripts/run-demo.sh --no-build           # relaunch what is already installed
#
# `.env` is gitignored and holds your credentials; `.env.example` documents the keys. The five
# settings `DemoOverrides` reads are forwarded to the app as `SIMCTL_CHILD_*` variables, which is
# how `simctl` passes an environment to the app it launches, and land on the demo's **Development**
# environment: overrides apply there only, on purpose, so one environment's merchant secret can
# never be sent to another's gateway. The badge in the app shows the host actually in use.
#
# The values reach the app through the process environment, not through the build, so nothing
# secret is compiled into the .app and nothing is written into the version-controlled scheme.
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$root/.env"
bundle_id="com.gopay.sdk"
keys=(BASE_URL CLIENT_ID SHAREABLE_KEY CLIENT_SECRET GOID)

device=""
build=1

usage() {
    cat <<USAGE
usage: ${BASH_SOURCE[0]##*/} [-d DEVICE] [--no-build]
  -d, --device DEVICE   simulator to use, booted if needed (default: the first booted one)
      --no-build        relaunch what is already installed instead of building
Reads $env_file for the five GOPAY_DEMO_* settings; copy .env.example and fill it in.
USAGE
}

while (($#)); do
    case "$1" in
        -d|--device) device="${2:?missing device name}"; shift 2 ;;
        --no-build) build=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ ! -f "$env_file" ]]; then
    echo "error: no $env_file — copy .env.example to .env and fill in your credentials" >&2
    exit 1
fi

# Reads one `KEY=value` out of `.env`, first assignment winning, with one layer of surrounding
# quotes stripped. Deliberately parsed rather than sourced: a file of secrets should not be able to
# run shell code, and sourcing would also drag every unrelated variable in it into this script's
# environment.
#
# A `#` only starts a comment at the beginning of a line. Anything after `=` is the value, `#`
# included, so a credential containing one survives. This matches the Android demo's `lookup`
# exactly, because one `.env` is meant to drive both platforms and a value that differs between
# them shows up as an opaque 401 rather than as a parsing problem.
read_env() {
    local key="$1"
    perl -ne '
        next unless /^\s*(?:export\s+)?\Q'"$key"'\E\s*=\s*(.*)$/;
        my $v = $1;
        $v =~ s/\s+$//;
        if    ($v =~ /^"(.*)"$/) { $v = $1 }
        elsif ($v =~ /^'"'"'(.*)'"'"'$/) { $v = $1 }
        print $v;
        exit 0;
    ' "$env_file"
}

launch_env=()
supplied=()
missing=()

# Every key is optional, the same contract `DemoOverrides` states: whatever `.env` leaves out keeps
# its compiled-in value. Missing keys are worth saying out loud, though, since running against a
# real gateway with only some of them is rarely what anyone meant. Note that the app drops the
# credentials itself when it rejects a supplied GOPAY_DEMO_BASE_URL, so a log listing a URL and
# credentials can still end up with neither applied.
for key in "${keys[@]}"; do
    value="$(read_env "GOPAY_DEMO_${key}")"
    if [[ -z "$value" ]]; then
        missing+=("GOPAY_DEMO_${key}")
        continue
    fi
    launch_env+=("SIMCTL_CHILD_GOPAY_DEMO_${key}=${value}")
    supplied+=("$key")
done

# Values are never echoed: this runs in shared terminals.
if ((${#supplied[@]})); then
    echo "Supplied from .env: ${supplied[*]}"
else
    echo "warning: $env_file supplies none of the GOPAY_DEMO_* keys, so the app keeps every compiled-in value" >&2
fi
if ((${#missing[@]})); then
    echo "warning: no value in $env_file for: ${missing[*]}" >&2
fi

if [[ -n "$device" ]]; then
    udid="$(xcrun simctl list devices available | sed -n "s/^ *${device} (\([0-9A-Fa-f-]\{36\}\)).*/\1/p" | head -1)"
    if [[ -z "$udid" ]]; then
        echo "error: no available simulator named '$device'" >&2
        exit 1
    fi
else
    udid="$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-Fa-f-]\{36\}\)) (Booted).*/\1/p' | head -1)"
    if [[ -z "$udid" ]]; then
        echo "error: no booted simulator — boot one, or pass --device 'iPhone 17'" >&2
        exit 1
    fi
fi

xcrun simctl bootstatus "$udid" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$udid" || true

derived="$root/.build/demo-app"
app="$derived/Build/Products/Debug-iphonesimulator/example.app"

if ((build)); then
    echo "Building the example app…"
    xcodebuild -project "$root/example/example.xcodeproj" -scheme example \
        -configuration Debug -destination "id=$udid" -derivedDataPath "$derived" \
        build >/dev/null
    xcrun simctl install "$udid" "$app"
elif [[ -d "$app" ]]; then
    xcrun simctl install "$udid" "$app"
fi

# Stays attached and streams the app's stdout, so the SDK's debug logging and any `[DemoOverrides]`
# warning land in the terminal. `--console-pty` and not `--console` because the app block-buffers
# its stdout when that isn't a terminal, which holds the interesting lines back until it exits.
echo "Launching $bundle_id…"
env ${launch_env[@]+"${launch_env[@]}"} xcrun simctl launch --terminate-running-process --console-pty "$udid" "$bundle_id"
