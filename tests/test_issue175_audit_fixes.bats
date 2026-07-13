#!/usr/bin/env bats
# Issue #175 - command-surface audit fixes.
#
# 1. Stale setup_state=7/99 + config-affecting CLI flags: initialize_setup
#    must roll back to step 4 so firewall + configs are regenerated;
#    previously the loop jumped straight to step 7 and the new values lived
#    only in awgsetup_cfg.init while awg0.conf kept the old ones.

# ---------------------------------------------------------------------------
# Fix 1: resume rollback guard
# ---------------------------------------------------------------------------

@test "issue #175/1: RU/EN installer rolls back stale state>4 to step 4 on config CLI flags" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        # The guard must exist between state load and end of initialize_setup:
        # a current_step>4 check that considers CLI overrides and resets to 4.
        run grep -A20 'current_step > 4' "$BATS_TEST_DIRNAME/../$f"
        [ "$status" -eq 0 ]
        [[ "$output" == *'current_step=4'* ]]
        [[ "$output" == *'update_state 4'* ]]
    done
}

@test "issue #175/1: rollback guard covers every config-affecting CLI override" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        block=$(awk '/current_step > 4/,/update_state 4/' "$BATS_TEST_DIRNAME/../$f")
        for var in CLI_PORT CLI_SUBNET CLI_SSH_PORT CLI_ROUTING_MODE CLI_ENDPOINT \
                   CLI_DISABLE_IPV6 CLI_ALLOW_IPV6_TUNNEL CLI_PRESET CLI_JC CLI_JMIN \
                   CLI_JMAX CLI_NO_CPS; do
            [[ "$block" == *"$var"* ]] || {
                echo "missing $var in $f rollback guard" >&2
                return 1
            }
        done
    done
}

@test "issue #175/1: guard sits inside initialize_setup after the state load" {
    # The reset must happen after STATE_FILE is read (otherwise current_step
    # is not yet known) and before the main step loop consumes it.
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        state_line=$(grep -n 'current_step=$(cat "$STATE_FILE")' "$BATS_TEST_DIRNAME/../$f" | head -1 | cut -d: -f1)
        guard_line=$(grep -n 'current_step > 4' "$BATS_TEST_DIRNAME/../$f" | head -1 | cut -d: -f1)
        [ -n "$state_line" ] && [ -n "$guard_line" ]
        [ "$guard_line" -gt "$state_line" ]
    done
}
