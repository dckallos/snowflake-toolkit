#!/usr/bin/env bash
# ============================================================
# doctor_profile.sh -- inspect a local Snowflake CLI profile without network calls.
#
# Use this before bootstrap when you suspect ~/.snowflake/connections.toml points
# at the wrong account/user/key. It reads only local TOML and key files.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_lib.sh"

usage() {
  cat <<'USAGE'
usage: doctor_profile.sh --profile PROFILE [--expected-account ACCOUNT] [--expected-user USER]

Examples:
  ./snowflake_cli/doctor_profile.sh --profile kw94245 \
    --expected-account DSHXYWJ-KW94245 --expected-user PORCHORCH
USAGE
}

PROFILE=""
EXPECTED_ACCOUNT=""
EXPECTED_USER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --expected-account) EXPECTED_ACCOUNT="${2:-}"; shift 2 ;;
    --expected-user) EXPECTED_USER="${2:-}"; shift 2 ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 64 ;;
  esac
done

[[ -n "${PROFILE}" ]] || { echo "error: --profile is required" >&2; usage >&2; exit 64; }
validate_conn_name "${PROFILE}" || exit $?

CONNECTIONS_TOML="${SNOW_LIB_CONNECTIONS_TOML}"
CONFIG_TOML="${SNOW_LIB_CONFIG_TOML}"
ACCOUNT="$(parse_toml_value "${PROFILE}" account "${CONNECTIONS_TOML}")"
USER_NAME="$(parse_toml_value "${PROFILE}" user "${CONNECTIONS_TOML}")"
ROLE="$(parse_toml_value "${PROFILE}" role "${CONNECTIONS_TOML}")"
WAREHOUSE="$(parse_toml_value "${PROFILE}" warehouse "${CONNECTIONS_TOML}")"
KEY_PATH="$(parse_toml_value "${PROFILE}" private_key_path "${CONNECTIONS_TOML}")"
DEFAULT_CONN="$(parse_toml_toplevel_key default_connection_name "${CONFIG_TOML}")"

status=0
cat <<REPORT
Profile doctor: ${PROFILE}
  connections.toml: ${CONNECTIONS_TOML}
  config.toml:      ${CONFIG_TOML}
  default:          ${DEFAULT_CONN:-<unset>}
  account:          ${ACCOUNT:-<missing>}
  user:             ${USER_NAME:-<missing>}
  role:             ${ROLE:-<missing>}
  warehouse:        ${WAREHOUSE:-<missing>}
  private key:      ${KEY_PATH:-<missing>}
REPORT

if [[ -n "${EXPECTED_ACCOUNT}" && "${ACCOUNT}" != "${EXPECTED_ACCOUNT}" ]]; then
  echo "  ❌ account mismatch: expected ${EXPECTED_ACCOUNT}, found ${ACCOUNT:-<missing>}"
  status=1
fi
if [[ -n "${EXPECTED_USER}" && "${USER_NAME^^}" != "${EXPECTED_USER^^}" ]]; then
  echo "  ❌ user mismatch: expected ${EXPECTED_USER}, found ${USER_NAME:-<missing>}"
  status=1
fi
if [[ -z "${ACCOUNT}" || -z "${USER_NAME}" || -z "${ROLE}" || -z "${WAREHOUSE}" || -z "${KEY_PATH}" ]]; then
  echo "  ❌ profile is incomplete"
  status=1
fi
if [[ -n "${KEY_PATH}" && ! -f "${KEY_PATH}" ]]; then
  echo "  ❌ private key file does not exist: ${KEY_PATH}"
  status=1
fi

if [[ "${status}" -eq 0 ]]; then
  echo "  ✅ local profile shape looks consistent"
else
  cat <<NEXT

Recommended repair example:
  ${SCRIPT_DIR}/setup.sh --profile ${PROFILE} \
    --account ${EXPECTED_ACCOUNT:-<ACCOUNT>} --admin-user ${EXPECTED_USER:-<USER>} \
    --replace-existing --phase prereq
NEXT
fi

exit "${status}"
