#!/usr/bin/env bash
#
# Copyright © 2026 Intabia Fusion.
#
# Licensed under the Eclipse Public License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may
# obtain a copy of the License at https://www.eclipse.org/legal/epl-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Install or upgrade the platform from the published charts.
#   PROFILE=bundled PLATFORM_VERSION=v0.8.37 ./scripts/install.sh
#   PROFILE=external PLATFORM_VERSION=v0.8.37 ./scripts/install.sh
# Both helm releases are idempotent: the same command upgrades an existing installation.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

PROFILE="${PROFILE:-bundled}"
case "$PROFILE" in bundled|external) ;; *) echo "PROFILE must be bundled or external" >&2; exit 2 ;; esac
VERSION="${PLATFORM_VERSION:-${1:-}}"
[ -n "$VERSION" ] || { echo "usage: PLATFORM_VERSION=vX.Y.Z PROFILE=bundled|external $0" >&2; exit 2; }
CHART_VERSION="${VERSION#v}"
CHARTS_URL="${CHARTS_URL:-https://intabia-fusion.github.io/platform-charts}"
NS_BASE="${NS_BASE:-platform-base}"
NS="${NS:-platform}"
TIMEOUT="${HELM_TIMEOUT:-15m}"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 2; }

BASE_ARGS=()
PLATFORM_ARGS=()
[ -f "values/secrets-base.yaml" ] && BASE_ARGS+=(-f "values/secrets-base.yaml")
[ -f "values/secrets-platform.yaml" ] && PLATFORM_ARGS+=(-f "values/secrets-platform.yaml")

chart_ref() {
  local name="$1"
  if [ -n "${CHARTS_DIR:-}" ]; then
    printf '%s/%s-%s.tgz' "$CHARTS_DIR" "$name" "$CHART_VERSION"
  else
    printf 'platform-charts/%s' "$name"
  fi
}

# --version only applies to repository charts; a local .tgz carries its version already.
VERSION_ARGS=()
[ -z "${CHARTS_DIR:-}" ] && VERSION_ARGS=(--version "$CHART_VERSION")

if [ -z "${CHARTS_DIR:-}" ]; then
  helm repo add platform-charts "$CHARTS_URL" --force-update >/dev/null
  helm repo update platform-charts >/dev/null
fi

echo ">> platform-base $CHART_VERSION ($PROFILE) in $NS_BASE"
helm upgrade --install platform-base "$(chart_ref platform-base)" \
  "${VERSION_ARGS[@]}" \
  -n "$NS_BASE" --create-namespace \
  -f "values/base-$PROFILE.yaml" "${BASE_ARGS[@]}" \
  --timeout "$TIMEOUT" --wait

echo ">> platform $CHART_VERSION ($PROFILE) in $NS"
helm upgrade --install platform "$(chart_ref platform)" \
  "${VERSION_ARGS[@]}" \
  -n "$NS" --create-namespace \
  -f "values/platform-$PROFILE.yaml" "${PLATFORM_ARGS[@]}" \
  --set "global.namespace=$NS" \
  --set "global.baseNamespace=$NS_BASE" \
  --set "global.version=$VERSION" \
  --timeout "$TIMEOUT" --wait

HOST="$(helm -n "$NS" get values platform -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["global"]["hostUrl"])')"
echo
echo ">> installed $VERSION: https://$HOST"
echo "   next: create the first workspace (see README, 'First workspace')"
