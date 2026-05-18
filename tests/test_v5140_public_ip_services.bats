#!/usr/bin/env bats
# Tests for get_server_public_ip extended service list (v5.14.0 MyAI-avy9).
#
# v5.14.0 extends the public IP detection from 4 to 6 services, adding
# checkip.amazonaws.com (AWS-friendly, reachable from VPC private subnets)
# and ifconfig.io (alternative to ifconfig.me for downtime cases).
# Order is first-wins: checkip.amazonaws.com first, then by uptime SLA.

load test_helper

setup() {
    TEST_DIR=$(mktemp -d)
    export AWG_DIR="$TEST_DIR"
    log()       { :; }
    log_warn()  { :; }
    log_error() { :; }
    log_debug() { :; }
    export -f log log_warn log_error log_debug
    source "$BATS_TEST_DIRNAME/../awg_common.sh"
    _CACHED_PUBLIC_IP=""
}

teardown() {
    rm -rf "$TEST_DIR"
    unset -f curl 2>/dev/null || true
}

@test "get_server_public_ip: structural RU - service list contains 6 endpoints" {
    local FILE="${BATS_TEST_DIRNAME}/../awg_common.sh"
    local block
    block=$(awk '/^get_server_public_ip\(\) \{$/,/^}$/' "$FILE")
    [[ "$block" == *"checkip.amazonaws.com"* ]]
    [[ "$block" == *"ifconfig.me"* ]]
    [[ "$block" == *"api.ipify.org"* ]]
    [[ "$block" == *"icanhazip.com"* ]]
    [[ "$block" == *"ipinfo.io/ip"* ]]
    [[ "$block" == *"ifconfig.io"* ]]
}

@test "get_server_public_ip: structural EN - service list contains 6 endpoints" {
    local FILE="${BATS_TEST_DIRNAME}/../awg_common_en.sh"
    local block
    block=$(awk '/^get_server_public_ip\(\) \{$/,/^}$/' "$FILE")
    [[ "$block" == *"checkip.amazonaws.com"* ]]
    [[ "$block" == *"ifconfig.me"* ]]
    [[ "$block" == *"api.ipify.org"* ]]
    [[ "$block" == *"icanhazip.com"* ]]
    [[ "$block" == *"ipinfo.io/ip"* ]]
    [[ "$block" == *"ifconfig.io"* ]]
}

@test "get_server_public_ip: RU and EN service lists match (parity)" {
    local RU_FILE="${BATS_TEST_DIRNAME}/../awg_common.sh"
    local EN_FILE="${BATS_TEST_DIRNAME}/../awg_common_en.sh"
    local ru_count en_count
    ru_count=$(awk '/^get_server_public_ip\(\) \{$/,/^}$/' "$RU_FILE" | grep -cE 'https://')
    en_count=$(awk '/^get_server_public_ip\(\) \{$/,/^}$/' "$EN_FILE" | grep -cE 'https://')
    [ "$ru_count" -eq "$en_count" ]
    [ "$ru_count" -eq 6 ]
}

@test "get_server_public_ip: first service success returns valid IP" {
    # shellcheck disable=SC2317
    curl() {
        local url="${@: -1}"
        if [[ "$url" == "https://checkip.amazonaws.com" ]]; then
            echo "203.0.113.42"
            return 0
        fi
        return 1
    }
    export -f curl

    run get_server_public_ip
    [ "$status" -eq 0 ]
    [ "$output" = "203.0.113.42" ]
}

@test "get_server_public_ip: first service fails, falls through to second" {
    # shellcheck disable=SC2317
    curl() {
        local url="${@: -1}"
        if [[ "$url" == "https://checkip.amazonaws.com" ]]; then
            return 1
        fi
        if [[ "$url" == "https://ifconfig.me" ]]; then
            echo "198.51.100.7"
            return 0
        fi
        return 1
    }
    export -f curl

    run get_server_public_ip
    [ "$status" -eq 0 ]
    [ "$output" = "198.51.100.7" ]
}

@test "get_server_public_ip: all 6 services fail returns 1 with empty output" {
    # shellcheck disable=SC2317
    curl() { return 1; }
    export -f curl

    run get_server_public_ip
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "get_server_public_ip: invalid IP format from one service skips to next" {
    # shellcheck disable=SC2317
    curl() {
        local url="${@: -1}"
        case "$url" in
            "https://checkip.amazonaws.com")
                echo "not-an-ip"
                return 0
                ;;
            "https://ifconfig.me")
                echo "192.0.2.99"
                return 0
                ;;
            *) return 1 ;;
        esac
    }
    export -f curl

    run get_server_public_ip
    [ "$status" -eq 0 ]
    [ "$output" = "192.0.2.99" ]
}

@test "get_server_public_ip: last-in-list ifconfig.io success after 5 fails" {
    # shellcheck disable=SC2317
    curl() {
        local url="${@: -1}"
        if [[ "$url" == "https://ifconfig.io" ]]; then
            echo "172.16.0.1"
            return 0
        fi
        return 1
    }
    export -f curl

    run get_server_public_ip
    [ "$status" -eq 0 ]
    [ "$output" = "172.16.0.1" ]
}

@test "get_server_public_ip: cached value short-circuits subsequent calls" {
    _CACHED_PUBLIC_IP="10.20.30.40"
    # No curl mock - if cache miss happens, real curl would run (test fails).
    run get_server_public_ip
    [ "$status" -eq 0 ]
    [ "$output" = "10.20.30.40" ]
}
