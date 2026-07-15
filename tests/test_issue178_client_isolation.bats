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
        tunnel_network_cidr 300.1.1.1/24 || echo "rejected-octet"
    '
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "10.9.9.0/24" ]]
    [[ "${lines[1]}" == "10.9.0.0/16" ]]
    [[ "${lines[2]}" == "172.16.5.0/30" ]]
    [[ "${lines[3]}" == "rejected" ]]
    [[ "${lines[4]}" == "rejected-octet" ]]
}

# ---------------------------------------------------------------------------
# CLIENT_ISOLATION resolution + ALLOWED_IPS application
# ---------------------------------------------------------------------------

@test "issue #178 functional: configure_client_isolation priority CLI > config > --yes/question" {
    fn=$(awk '/^configure_client_isolation\(\)/,/^}/' "$BATS_TEST_DIRNAME/../install_amneziawg.sh")
    [ -n "$fn" ]
    run bash -c '
        log() { :; }; die() { echo "DIE:$*"; exit 1; }
        '"$fn"'
        CLI_ISOLATION=off AUTO_YES=0 CLIENT_ISOLATION=""
        configure_client_isolation; echo "cli-off:$CLIENT_ISOLATION"
        CLI_ISOLATION=on AUTO_YES=0 CLIENT_ISOLATION=0
        configure_client_isolation; echo "cli-on:$CLIENT_ISOLATION"
        CLI_ISOLATION=default AUTO_YES=0 CLIENT_ISOLATION=0
        configure_client_isolation; echo "cfg:$CLIENT_ISOLATION"
        CLI_ISOLATION=default AUTO_YES=1 CLIENT_ISOLATION=""
        configure_client_isolation; echo "yes:$CLIENT_ISOLATION"
        CLI_ISOLATION=default AUTO_YES=0 CLIENT_ISOLATION="" config_exists=1
        configure_client_isolation; echo "legacy:$CLIENT_ISOLATION"
        CLI_ISOLATION=bogus configure_client_isolation
    '
    [[ "$output" == *'cli-off:0'* ]]
    [[ "$output" == *'cli-on:1'* ]]
    [[ "$output" == *'cfg:0'* ]]
    [[ "$output" == *'yes:1'* ]]
    [[ "$output" == *'legacy:1'* ]]
    [[ "$output" == *'DIE:'* ]]
}

@test "issue #178 functional: _apply_isolation_to_allowed_ips add/remove semantics" {
    fns=$(awk '/^tunnel_network_cidr\(\)/,/^}/' "$BATS_TEST_DIRNAME/../install_amneziawg.sh"
          awk '/^_apply_isolation_to_allowed_ips\(\)/,/^}/' "$BATS_TEST_DIRNAME/../install_amneziawg.sh")
    [ -n "$fns" ]
    run bash -c '
        log() { :; }
        '"$fns"'
        AWG_TUNNEL_SUBNET=10.9.9.1/24
        # off + mode 2: append once, idempotent
        CLIENT_ISOLATION=0 ALLOWED_IPS_MODE=2 ALLOWED_IPS="1.0.0.0/8, 8.8.8.8/32"
        _apply_isolation_to_allowed_ips; echo "A:$ALLOWED_IPS"
        _apply_isolation_to_allowed_ips; echo "B:$ALLOWED_IPS"
        # off + mode 1: 0.0.0.0/0 already covers the subnet
        CLIENT_ISOLATION=0 ALLOWED_IPS_MODE=1 ALLOWED_IPS="0.0.0.0/0"
        _apply_isolation_to_allowed_ips; echo "C:$ALLOWED_IPS"
        # off + mode 3: append to custom list too
        CLIENT_ISOLATION=0 ALLOWED_IPS_MODE=3 ALLOWED_IPS="192.168.50.0/24"
        _apply_isolation_to_allowed_ips; echo "D:$ALLOWED_IPS"
        # on + mode 2: our token is stripped (round-trip off->on)
        CLIENT_ISOLATION=1 ALLOWED_IPS_MODE=2 ALLOWED_IPS="1.0.0.0/8, 10.9.9.0/24, 8.8.8.8/32"
        _apply_isolation_to_allowed_ips; echo "E:$ALLOWED_IPS"
        # on + mode 3: user-owned custom list is left intact
        CLIENT_ISOLATION=1 ALLOWED_IPS_MODE=3 ALLOWED_IPS="192.168.50.0/24, 10.9.9.0/24"
        _apply_isolation_to_allowed_ips; echo "F:$ALLOWED_IPS"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'A:1.0.0.0/8, 8.8.8.8/32, 10.9.9.0/24'* ]]
    [[ "$output" == *'B:1.0.0.0/8, 8.8.8.8/32, 10.9.9.0/24'* ]]
    [[ "$output" == *'C:0.0.0.0/0'* ]]
    [[ "$output" == *'D:192.168.50.0/24, 10.9.9.0/24'* ]]
    [[ "$output" == *'E:1.0.0.0/8, 8.8.8.8/32'* ]]
    [[ "$output" == *'F:192.168.50.0/24, 10.9.9.0/24'* ]]
}

@test "issue #178: RU/EN installer persists CLIENT_ISOLATION into awgsetup_cfg.init" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        run grep -F 'export CLIENT_ISOLATION=${CLIENT_ISOLATION:-1}' "$BATS_TEST_DIRNAME/../$f"
        [ "$status" -eq 0 ]
    done
}

@test "issue #178: CLIENT_ISOLATION whitelisted in safe_load_config (all four copies)" {
    for f in awg_common.sh awg_common_en.sh install_amneziawg.sh install_amneziawg_en.sh; do
        run grep -c 'PREV_AWG_PORT|CLIENT_ISOLATION)' "$BATS_TEST_DIRNAME/../$f"
        [ "$status" -eq 0 ]
        [ "$output" -ge 1 ]
    done
}

@test "issue #178: resume rollback guard covers CLI_ISOLATION (RU/EN)" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        block=$(awk '/current_step > 4/,/update_state 4/' "$BATS_TEST_DIRNAME/../$f")
        [[ "$block" == *'CLI_ISOLATION'* ]]
    done
}

@test "issue #178: RU/EN installer warns about regen --reset-routes on isolation change" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        run grep -c '_cfg_client_isolation' "$BATS_TEST_DIRNAME/../$f"
        [ "$status" -eq 0 ]
        [ "$output" -ge 2 ]   # захват + сравнение
    done
    # Legacy-конфиг (без ключа) должен захватываться как 1, а не как пусто.
    run grep -F '_cfg_client_isolation="${CLIENT_ISOLATION:-1}"' "$BATS_TEST_DIRNAME/../install_amneziawg.sh"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Server-side isolation rules
# ---------------------------------------------------------------------------

@test "issue #178: render_server_config adds isolation DROP to PostUp/PostDown (RU/EN)" {
    for f in awg_common.sh awg_common_en.sh; do
        block=$(awk '/^render_server_config\(\)/,/^}/' "$BATS_TEST_DIRNAME/../$f")
        [[ "$block" == *'iptables -I FORWARD -i %i -o %i -j DROP'* ]]
        # PostDown guarded: rule may be absent after an on->off reinstall.
        [[ "$block" == *'iptables -D FORWARD -i %i -o %i -j DROP 2>/dev/null || true'* ]]
        [[ "$block" == *'ip6tables -I FORWARD -i %i -o %i -j DROP'* ]]
        [[ "$block" == *'CLIENT_ISOLATION'* ]]
    done
}

@test "issue #178: isolation DROP is appended after the ACCEPT insert (ends up above it)" {
    # PostUp выполняется слева направо; -I вставляет в начало цепочки, поэтому
    # DROP, идущий В СТРОКЕ ПОЗЖЕ ACCEPT, оказывается В ЦЕПОЧКЕ выше ACCEPT.
    for f in awg_common.sh awg_common_en.sh; do
        block=$(awk '/^render_server_config\(\)/,/^}/' "$BATS_TEST_DIRNAME/../$f")
        accept_first=$(grep -n 'local postup="iptables -I FORWARD -i %i -j ACCEPT' <<<"$block" | head -1 | cut -d: -f1)
        drop_line=$(grep -n 'postup=.*iptables -I FORWARD -i %i -o %i -j DROP' <<<"$block" | head -1 | cut -d: -f1)
        [ -n "$accept_first" ] && [ -n "$drop_line" ]
        [ "$drop_line" -gt "$accept_first" ]
    done
}

# ---------------------------------------------------------------------------
# Stale DROP cleanup (on->off reinstall)
# ---------------------------------------------------------------------------

@test "issue #178: step7 removes stale DROP rules when isolation is off (RU/EN)" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        block=$(awk '/^step7_start_service\(\)/,/^}/' "$BATS_TEST_DIRNAME/../$f")
        [[ "$block" == *'while iptables -D FORWARD -i awg0 -o awg0 -j DROP 2>/dev/null; do :; done'* ]]
        [[ "$block" == *'while ip6tables -D FORWARD -i awg0 -o awg0 -j DROP 2>/dev/null; do :; done'* ]]
        [[ "$block" == *'CLIENT_ISOLATION'* ]]
    done
}

@test "issue #178 functional: cleanup loop drains duplicates and only runs when off" {
    block=$(awk '/Переключение изоляции on->off/,/^    fi$/' "$BATS_TEST_DIRNAME/../install_amneziawg.sh" | grep -v '^ *#')
    [ -n "$block" ]
    run bash -c '
        calls=0
        iptables() { calls=$((calls+1)); (( calls <= 3 )); }   # 3 stale rules, then exhausted
        ip6tables() { return 1; }
        CLIENT_ISOLATION=0
        '"$block"'
        echo "off:$calls"
        calls=0
        CLIENT_ISOLATION=1
        '"$block"'
        echo "on:$calls"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *'off:4'* ]]   # 3 успешных удаления + 1 финальная неудача
    [[ "$output" == *'on:0'* ]]    # при включённой изоляции цикл не запускается
}

@test "issue #178: uninstall drains stale isolation DROP rules (RU/EN)" {
    for f in install_amneziawg.sh install_amneziawg_en.sh; do
        block=$(awk '/^step_uninstall\(\)/,/^}/' "$BATS_TEST_DIRNAME/../$f")
        [[ "$block" == *'while iptables -D FORWARD -i awg0 -o awg0 -j DROP 2>/dev/null; do :; done'* ]]
        [[ "$block" == *'while ip6tables -D FORWARD -i awg0 -o awg0 -j DROP 2>/dev/null; do :; done'* ]]
    done
}

@test "issue #178: install summary logs the isolation state (RU/EN)" {
    run grep -c 'Изоляция клиентов: $(' "$BATS_TEST_DIRNAME/../install_amneziawg.sh"
    [ "$status" -eq 0 ]
    run grep -c 'Client isolation: $(' "$BATS_TEST_DIRNAME/../install_amneziawg_en.sh"
    [ "$status" -eq 0 ]
}
