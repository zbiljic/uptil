#!/usr/bin/env python3

import argparse
import os
import socket


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Accept one Unix-socket request without sending a response."
    )
    parser.add_argument("socket_path")
    parser.add_argument("receipt_path")
    return parser.parse_args()


def receive_request(socket_path: str) -> bytes:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(socket_path)
        os.chmod(socket_path, 0o600)
        server.listen(1)

        connection, _ = server.accept()
        with connection:
            request = bytearray()
            while not request.endswith(b"\n"):
                chunk = connection.recv(4096)
                if not chunk:
                    raise SystemExit("request ended before newline")
                request.extend(chunk)

    return bytes(request)


def main() -> None:
    arguments = parse_arguments()
    request = receive_request(arguments.socket_path)
    with open(arguments.receipt_path, "wb") as receipt:
        receipt.write(request)


if __name__ == "__main__":
    main()
