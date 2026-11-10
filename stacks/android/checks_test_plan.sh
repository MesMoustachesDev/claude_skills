# shellcheck shell=bash
# test_plan / test_plan_match pour un module Android : les mêmes que Flutter (stacks/flutter/checks_test_plan.sh),
# test_plan.py reconnaissant les tests Kotlin (src/test/**/*Test.kt, src/androidTest, .feature Cucumber) et les
# noms de méthode JUnit.
# shellcheck source=/dev/null
source "$CLAUDE_STACKS_DIR/flutter/checks_test_plan.sh"
