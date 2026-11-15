#!/usr/bin/with-contenv bashio
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

METER_ADDRESS=$(bashio::config 'meter_address')
METER_PORT=$(bashio::config 'meter_port')
LOG_LEVEL=$(bashio::config 'log_level' | tr '[:lower:]' '[:upper:]')

API_TOKEN=""
if bashio::config.has_value 'api_token'; then
    API_TOKEN=$(bashio::config 'api_token')
fi

RECONNECT_INTERVAL=""
if bashio::config.has_value 'reconnect_interval'; then
    RECONNECT_INTERVAL=$(bashio::config 'reconnect_interval')
fi

bashio::log.info "Writing the service configuration to ${CONFIG_FILE}"

{
    echo "meters:"
    echo "  - address: ${METER_ADDRESS}"
    echo "    port: \"${METER_PORT}\""
    # The transport accepts baudrate only for a serial device, host:port is TCP.
    case "${METER_PORT}" in
        /* | [Cc][Oo][Mm][0-9]*)
            echo "    baudrate: $(bashio::config 'baudrate')"
            ;;
    esac

    echo "proxy:"
    echo "  port: ${PROXY_PORT}"

    echo "api:"
    echo "  enabled: $(bashio::config 'api')"
    echo "  port: ${API_PORT}"
    if bashio::var.has_value "${API_TOKEN}"; then
        echo "  token: \"${API_TOKEN}\""
    fi

    echo "logging:"
    echo "  level: ${LOG_LEVEL}"
    echo "  directory: ${LOG_DIRECTORY}"

    if bashio::var.has_value "${RECONNECT_INTERVAL}"; then
        echo "service:"
        echo "  reconnect_interval: ${RECONNECT_INTERVAL}"
    fi
} > "${CONFIG_FILE}"

if bashio::config.true 'api' && ! bashio::var.has_value "${API_TOKEN}"; then
    bashio::log.warning "REST API is open: set the api_token option to require a Bearer token"
fi

bashio::log.info "Starting mercury-proxy service"
exec mercury-proxy -c "${CONFIG_FILE}"
