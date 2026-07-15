#!/usr/bin/env bats
# Issue #178 - explicit client isolation setting.
# Isolation used to be an implicit side effect of the routing mode; now the
# installer asks/accepts --isolation=on|off, enforces isolation server-side
# (FORWARD awg0->awg0 DROP) and, when disabled, routes the tunnel subnet to
# the clients via ALLOWED_IPS.

# ---------------------------------------------------------------------------
# CLI flag + step-0 helpers
# ---------------------------------------------------------------------------

@test "issue #178: RU/EN installer parses --isolation= into CLI_ISOLATION" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        run grep -F -- '--isolation=*)' "$BATS_TEST_DIRNAME/../$f"
        [ "$status" -eq 0 ]
        [[ "$output" == *'CLI_ISOLATION='* ]]
    done
}

@test "issue #178: RU/EN help mentions --isolation" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        run grep -c -- '--isolation=' "$BATS_TEST_DIRNAME/../$f"
        [ "$status" -eq 0 ]
        [ "$output" -ge 2 ]   # парсер + help
    done
}

@test "issue #178 functional: tunnel_network_cidr derives network from server addr" {
    fn=$(awk '/^tunnel_network_cidr\(\)/,/^}/' "$BATS_TEST_DIRNAME/../install_amneziawg.sh")
    [ -n "$fn" ]
    run bash -c "$fn"'
        tunnel_network_cidr 10.9.9.1/24
        tunnel_network_cidr 10.9.0.1/16
        tunnel_network_cidr 172.16.5.1/30
        tunnel_network_cidr not-a-cidr || echo "rejected"
    '
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "10.9.9.0/24" ]]
    [[ "${lines[1]}" == "10.9.0.0/16" ]]
    [[ "${lines[2]}" == "172.16.5.0/30" ]]
    [[ "${lines[3]}" == "rejected" ]]
}
