#!/bin/sh
# Behavior tests for bin/focus-block against a scratch hosts file.
set -eu

repo_root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

export FOCUS_BLOCK_HOSTS="$scratch/hosts"
export FOCUS_BLOCK_DOMAINS="$scratch/domains"
block="$repo_root/bin/focus-block"
failures=0

fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

expect_line() {
    grep -qxF "$2" "$FOCUS_BLOCK_HOSTS" || fail "$1: missing line '$2'"
}

reject_line() {
    if grep -qF "$2" "$FOCUS_BLOCK_HOSTS"; then
        fail "$1: unexpected content '$2'"
    fi
}

printf '127.0.0.1 localhost\n::1 localhost\n' > "$FOCUS_BLOCK_HOSTS"
cat > "$FOCUS_BLOCK_DOMAINS" <<'EOF'
# Focus blocklist
youtube.com   # trailing comment
www.reddit.com
bad domain!
$(touch /tmp/focus-block-pwned)
this-label-is-far-too-long-to-be-a-real-domain-name-because-it-goes-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on-and-on.com
EOF

test "$("$block" status)" = off || fail "fresh hosts should report off"

"$block" on
test "$("$block" status)" = on || fail "status should report on after on"
expect_line "on" "127.0.0.1 localhost"
expect_line "on" "0.0.0.0 youtube.com"
expect_line "on" ":: youtube.com"
expect_line "on" "0.0.0.0 www.youtube.com"
expect_line "on" "0.0.0.0 www.reddit.com"
reject_line "on" "0.0.0.0 www.www.reddit.com"
reject_line "on" "bad domain"
reject_line "on" "touch /tmp"
reject_line "on" "far-too-long"

"$block" on
count=$(grep -cF ">>> focus-block >>>" "$FOCUS_BLOCK_HOSTS")
test "$count" = 1 || fail "repeated on must keep a single section (got $count)"

"$block" off
test "$("$block" status)" = off || fail "status should report off after off"
expect_line "off" "127.0.0.1 localhost"
expect_line "off" "::1 localhost"
reject_line "off" "focus-block"
reject_line "off" "youtube"

# A hosts file missing the loopback sentinel must be left untouched: with no
# pipefail in sh, the sentinel is what catches a producer dying mid-pipe.
printf '# intentionally no localhost line\n1.2.3.4 example.test\n' > "$FOCUS_BLOCK_HOSTS"
if "$block" on 2>/dev/null; then
    fail "on must refuse a hosts file without 127.0.0.1 localhost"
fi
expect_line "sentinel" "1.2.3.4 example.test"
reject_line "sentinel" "youtube"

# A symlinked hosts file (NixOS-style generated file) must be refused, not
# silently replaced by a regular file.
printf '127.0.0.1 localhost\n' > "$scratch/hosts.real"
ln -sf "$scratch/hosts.real" "$FOCUS_BLOCK_HOSTS"
if "$block" on 2>/dev/null; then
    fail "on must refuse a symlinked hosts file"
fi
test -L "$FOCUS_BLOCK_HOSTS" || fail "refused symlink must stay a symlink"
rm "$FOCUS_BLOCK_HOSTS"

printf '127.0.0.1 localhost\n' > "$FOCUS_BLOCK_HOSTS"
rm "$FOCUS_BLOCK_DOMAINS"
"$block" on
test "$("$block" status)" = on || fail "missing domains file still writes markers"
reject_line "missing domains" "0.0.0.0"
"$block" off

if [ "$failures" -gt 0 ]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "focus-block tests passed"
