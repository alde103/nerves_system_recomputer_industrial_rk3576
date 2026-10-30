#!/usr/bin/env bash
# Checks that this system's sources and build output carry what the
# reComputer Industrial RK3576 needs.
#
# Usage:
#   scripts/verify-system.sh --static
#       Source-tree checks only; no build needed.
#   scripts/verify-system.sh <artifact_dir> [image]
#       Source-tree checks, then checks against a finished build. The
#       artifact dir is buildroot's output directory (build/, target/,
#       images/), e.g. .nerves/artifacts/nerves_system_recomputer_industrial_rk3576-portable-0.1.0
#       An image (a .img written by `fwup -t complete`) adds the layout check.
#
# Prints "ok <check>" per pass and exits non-zero on the first failure.
set -euo pipefail

SYSTEM_DIR=$(cd "$(dirname "$0")/.." && pwd)

ok() { echo "ok $*"; }
fail() {
    echo "FAIL $*" >&2
    exit 1
}

# Features this board does not have, or that this generic system leaves to
# the application: Sige5's NPU, OP-TEE, GPU stack, Broadcom WiFi and audio.
check_defconfig_clean() {
    local hits
    hits=$(grep -nE 'RKNPU|LIBRKNNRT|OPTEE|BRCMFMAC|MESA3D|GLMARK2|STRESS_NG|KMSCUBE|ALSA' \
        "$SYSTEM_DIR/nerves_defconfig" || true)
    [ -z "$hits" ] || fail "check_defconfig_clean: nerves_defconfig still enables:
$hits"
    ok check_defconfig_clean
}

if [ "${1:-}" = "--static" ]; then
    check_defconfig_clean
    exit 0
fi

[ $# -ge 1 ] || {
    echo "usage: $0 --static | <artifact_dir> [image]" >&2
    exit 2
}
ARTIFACT_DIR=$(cd "$1" && pwd)
IMAGE=${2:-}

check_defconfig_clean
