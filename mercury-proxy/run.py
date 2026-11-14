# coding=utf8
"""
Home Assistant add-on launcher for the mercury-proxy package
https://github.com/webtoucher/mercury-proxy
"""
import json
import logging
import re
import sys
import time

from mercury_base import EventBus, Meter, Meters, check_crc, hex_str
from mercury_proxy.api import Api
from pathlib import Path
from socket import AF_INET, SOCK_STREAM, socket
from simple_socket_server import SimpleSocketServer
from threading import Thread
from typing import Optional

OPTIONS_PATH = Path('/data/options.json')
DEFAULT_PROXY_PORT = 5053
DEFAULT_API_PORT = 5054
CONNECT_TIMEOUT = 3
RECONNECT_INTERVAL = 60
LOG_LEVELS = {
    'debug': logging.DEBUG,
    'info': logging.INFO,
    'warning': logging.WARNING,
}


def load_options() -> dict:
    """ Read add-on options """
    if not OPTIONS_PATH.exists():
        return {}
    return json.loads(OPTIONS_PATH.read_text(encoding='utf-8'))


def is_meter_port_reachable(port: str) -> bool:
    """ Check TCP port before connecting, socket client hangs on refused connection """
    matched = re.search(r'^(?P<host>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(?P<port>\d+)$', port)
    if not matched:
        return True
    try:
        with socket(AF_INET, SOCK_STREAM) as sock:
            sock.settimeout(CONNECT_TIMEOUT)
            sock.connect((matched.group('host'), int(matched.group('port'))))
        return True
    except OSError:
        return False


def meter_serial_number(meter: Meter) -> Optional[int]:
    """ mercury-base 1.6 keeps serial number on the meter, newer versions in meter.info """
    info = getattr(meter, 'info', None)
    if info is not None:
        return info.serial_number
    return getattr(meter, 'serial_number', None)


def meter_model(meter: Meter) -> str:
    """ Meter model name in the same way for both mercury-base layouts """
    info = getattr(meter, 'info', None)
    model = info.model if info is not None else getattr(meter, 'model', None)
    return 'M%s' % model if model else '<unknown>'


def connect_meter(meters: Meters, address: int, port: str, logger: logging.Logger) -> bool:
    """ Connect meter by address and port string """
    if not is_meter_port_reachable(port):
        logger.error('Port "%s" is not reachable', port)
        return False
    try:
        return meters.connect_meter_by_port(address, port)
    except Exception:
        logger.exception('Unexpected error while connecting meter %s', address)
        return False


def watch_meter_connection(meters: Meters, address: int, port: str, logger: logging.Logger) -> None:
    """ Retry connection until at least one meter is available """
    while not meters.meters:
        time.sleep(RECONNECT_INTERVAL)
        logger.info('Reconnecting meter %s via port "%s"', address, port)
        connect_meter(meters, address, port, logger)


def main():
    options = load_options()
    meter_address = options.get('meter_address')
    meter_port = options.get('meter_port')
    proxy_port = int(options.get('proxy_port') or DEFAULT_PROXY_PORT)
    api_port = int(options.get('api_port') or DEFAULT_API_PORT)
    log_level = LOG_LEVELS.get(options.get('log_level', 'info'), logging.INFO)

    logging.basicConfig(
        stream=sys.stderr,
        level=log_level,
        format="[%(asctime)s] %(levelname)s\t%(message)s"
    )
    logger = logging.getLogger('mercury_proxy')

    meters_events = EventBus()
    meters = Meters(meters_events)

    socket_server = SimpleSocketServer()

    if options.get('api'):
        api = Api(meters)
        api.logger.setLevel(log_level)
    else:
        api = None

    @meters_events.on('connect')
    def on_connect(meter: Meter):
        logger.info(
            'Meter %s with serial number %s is connected',
            meter_model(meter),
            meter_serial_number(meter)
        )

    @meters_events.on('failed_connect')
    def on_failed_connect(address: int, port: str, err_message: str):
        logger.error('Connection error with meter %s on port "%s": %s', address, port, err_message)

    @meters_events.on('request')
    def on_request(meter: Meter, package: bytes):
        logger.debug('[proxy] --> [%s]\t%s', meter_serial_number(meter) or 'new meter', hex_str(package, ' '))

    @meters_events.on('answer')
    def on_answer(meter: Meter, package: bytes):
        logger.debug('[proxy] <-- [%s]\t%s', meter_serial_number(meter) or 'new meter', hex_str(package, ' '))

    @socket_server.on('start')
    def on_start(ip: str, port: int):
        logger.info('Proxy server is listening on %s:%s', ip, port)

    @socket_server.on('connect')
    def on_socket_connect(_sock, peer):
        logger.debug('New connection from %s:%s', *peer)

    @socket_server.on('disconnect')
    def on_socket_disconnect(_sock, peer):
        logger.debug('Connection from %s:%s is closed', *peer)

    @socket_server.on('message')
    def on_message(sock: socket, peer, message: bytes):
        if bytearray(message)[:1].isalpha():
            logger.warning('It looks like the socket request is HTTP')
            raise ConnectionResetError()
        logger.debug('[%s:%s] --> [proxy]\t%s', *peer, hex_str(message, ' '))
        if not check_crc(message):
            logger.warning('Package from %s:%s has wrong checksum', *peer)
            return
        meter = meters.find_by_package(message)
        if meter:
            answer = meter.send_package(message)
            if answer:
                logger.debug('[%s:%s] <-- [proxy]\t%s', *peer, hex_str(answer, ' '))
                socket_server.send(sock, answer)

    if meter_address and meter_port:
        meter_address = int(meter_address)
        logger.info('Connecting meter %s via port "%s"', meter_address, meter_port)
        if not connect_meter(meters, meter_address, meter_port, logger):
            logger.error(
                'Meter %s is not available, will retry every %s seconds',
                meter_address,
                RECONNECT_INTERVAL
            )
            Thread(
                target=watch_meter_connection,
                args=(meters, meter_address, meter_port, logger),
                daemon=True
            ).start()
    else:
        logger.error('Options "meter_address" and "meter_port" are required')

    if api:
        api.run(port=api_port)
    socket_server.run(port=proxy_port)


if __name__ == '__main__':
    main()
