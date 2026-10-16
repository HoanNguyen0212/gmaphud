#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${GMAPHUD_CHECK_RUNNING:-0}" != 1 ] && [ "${GMAPHUD_CHECK_RAW:-0}" != 1 ]; then
  exec python3 "$source_dir/gmaphud-check.py" test "$@"
fi
sh "$source_dir/test-source-output.sh"
test_dir=$(mktemp -d /tmp/gmaphud-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" -I"$source_dir/provider" \
  "$source_dir/common/speed-state.m" "$source_dir/provider/nav-source.m" \
  "$source_dir/provider/nav-payload.m" "$source_dir/tests/speed-state-tests.m" \
  -o "$test_dir/speed-state"
"$test_dir/speed-state"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" "$source_dir/common/test-state.m" \
  "$source_dir/tests/test-state-tests.m" -o "$test_dir/test-state"
"$test_dir/test-state"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" "$source_dir/common/speed-presentation.m" "$source_dir/common/placement-state.m" \
  "$source_dir/common/guidance-state.m" "$source_dir/tests/speed-presentation-tests.m" -o "$test_dir/presentation"
"$test_dir/presentation"

xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -I"$source_dir/common" -I"$source_dir/provider" \
  "$source_dir/common/alert-state.m" "$source_dir/provider/vietmap-alert-assets.m" \
  "$source_dir/tests/alert-state-tests.m" -o "$test_dir/alert-state"
"$test_dir/alert-state" \
  "$source_dir/tweak/layout/usr/share/gmaphud/gmaphud/traffic_camera.png" \
  "$source_dir/tweak/layout/usr/share/gmaphud/gmaphud/speed_limit_60.png" \
  "$source_dir/tweak/layout/usr/share/gmaphud/gmaphud"

package_version=$(sed -n 's/^Version: *//p' "$source_dir/tweak/control")
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  -DGVM_PACKAGE_VERSION="\"$package_version\"" \
  -I"$source_dir/common" "$source_dir/common/diagnostics.m" \
  "$source_dir/tests/diagnostics-tests.m" -o "$test_dir/diagnostics"
"$test_dir/diagnostics" "$package_version"

xcrun clang -Wall -Wextra -Werror "$source_dir/tests/background-policy-tests.c" -o "$test_dir/background-policy"
"$test_dir/background-policy"
python3 "$source_dir/tests/check-runner-tests.py"
