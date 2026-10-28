#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/ehr-native-checks.XXXXXX")"
trap 'rm -f "$check_dir/core-tests" "$check_dir/original-invocation-tests" "$check_dir/pinned-association-tests" "$check_dir/action-registry-tests" "$check_dir/class-layout-tests"; rmdir "$check_dir"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$project_root/native/include" "$project_root/native/EHRHostCore.cpp" \
    "$project_root/tests/core_tests.cpp" -o "$check_dir/core-tests"
"$check_dir/core-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$project_root/native/include" "$project_root/tests/original_invocation_gate_tests.cpp" \
    -o "$check_dir/original-invocation-tests"
"$check_dir/original-invocation-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -iquote "$project_root" "$project_root/tests/pinned_association_fixture.cpp" \
    -o "$check_dir/pinned-association-tests"
"$check_dir/pinned-association-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$project_root/native/include" "$project_root/tests/action_registry_fixture.cpp" \
    -o "$check_dir/action-registry-tests"
"$check_dir/action-registry-tests"
clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$project_root/native" "$project_root/tests/class_layout_core_fixture.cpp" \
    -o "$check_dir/class-layout-tests"
"$check_dir/class-layout-tests"
python3 -m unittest discover -s "$project_root/tests" -p 'test_*.py' -v
python3 -m unittest discover -s "$project_root/tests/source_inventory" -p 'test_*.py' -v
python3 -m unittest discover -s "$project_root/tools/facades" -p 'test_*.py' -v
