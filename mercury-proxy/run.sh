#!/command/with-contenv bashio
# Home Assistant add-on entrypoint for the mercury-proxy service
# https://github.com/webtoucher/mercury-proxy
#
# The add-on only translates its options into the service configuration file
# and starts the package entry point: no proxy or API code lives here.

set -e

# Container ports are fixed; the host side is chosen in the Network panel.
PROXY_PORT=5053
API_PORT=5054
CONFIG_FILE=/data/mercury-proxy.yaml
LOG_DIRECTORY=/data/log
MAX_METERS=32

METER_COUNT=0

# A meter port is either a serial device (/dev/ttyACM0, COM3) or host:port
# of another proxy; mercury-base tells them apart by spelling.
is_serial_port() {
    case "${1}" in
        /* | [Cc][Oo][Mm][0-9]*) return 0 ;;
    esac
    return 1
}

# Returns the option value or nothing, so optional keys stay out of the file
# and the service keeps its own defaults.
optional_option() {
    local key=${1}

    if bashio::config.has_value "${key}"; then
        bashio::config "${key}"
    fi
}

# Writes the meters section; the list of options is walked by jq paths
# (meters[0].address, meters[1].address, ...) until the next entry is absent.
write_meters() {
    local index=0
    local address
    local port
    local timeout
    local connect_timeout

    while true; do
        if [[ "${index}" -ge "${MAX_METERS}" ]]; then
            bashio::exit.nok "Too many meters, the limit is ${MAX_METERS}"
        fi
        if ! bashio::config.has_value "meters[${index}].address"; then
            break
        fi
        address=$(bashio::config "meters[${index}].address")
        if [[ "${address}" == "null" ]]; then
            break
        fi
        if ! bashio::config.has_value "meters[${index}].port"; then
            bashio::exit.nok "Meter ${address} has no port"
        fi
        port=$(bashio::config "meters[${index}].port")

        echo "  - address: ${address}"
        echo "    port: \"${port}\""
        if is_serial_port "${port}"; then
            echo "    baudrate: ${BAUDRATE}"
        else
            connect_timeout=$(optional_option 'connect_timeout')
            if [[ -n "${connect_timeout}" ]]; then
                echo "    connect_timeout: ${connect_timeout}"
            fi
        fi
        timeout=$(optional_option 'timeout')
        if [[ -n "${timeout}" ]]; then
            echo "    timeout: ${timeout}"
        fi

        index=$((index + 1))
    done

    if [[ "${index}" -eq 0 ]]; then
        bashio::exit.nok "The meters option is empty, add at least one meter"
    fi
    METER_COUNT=${index}
}

BAUDRATE=$(bashio::config 'baudrate')
LOG_LEVEL=$(bashio::config 'log_level' | tr '[:lower:]' '[:upper:]')
API_TOKEN=$(optional_option 'api_token')
RECONNECT_INTERVAL=$(optional_option 'reconnect_interval')

bashio::log.info "Writing the service configuration to ${CONFIG_FILE}"

{
    echo "meters:"
    write_meters

    echo "proxy:"
    echo "  port: ${PROXY_PORT}"

    echo "api:"
    echo "  enabled: $(bashio::config 'api')"
    echo "  port: ${API_PORT}"
    if [[ -n "${API_TOKEN}" ]]; then
        echo "  token: \"${API_TOKEN}\""
    fi

    echo "logging:"
    echo "  level: ${LOG_LEVEL}"
    echo "  directory: ${LOG_DIRECTORY}"
    echo "  console: $(bashio::config 'log_console')"

    if [[ -n "${RECONNECT_INTERVAL}" ]]; then
        echo "service:"
        echo "  reconnect_interval: ${RECONNECT_INTERVAL}"
    fi
} > "${CONFIG_FILE}"

if bashio::config.true 'api' && [[ -z "${API_TOKEN}" ]]; then
    bashio::log.warning "REST API is open: set the api_token option to require a Bearer token"
fi

bashio::log.info "Starting mercury-proxy: ${METER_COUNT} meter(s), proxy port ${PROXY_PORT}, API port ${API_PORT}"
exec mercury-proxy -c "${CONFIG_FILE}"
