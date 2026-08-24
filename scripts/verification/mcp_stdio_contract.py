#!/usr/bin/env python3

import argparse
import json
import subprocess


CURRENT_VERSION = "2026-07-28"
OLD_VERSION = "2025-11-25"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def metadata(version: str = CURRENT_VERSION) -> dict:
    result = {
        "io.modelcontextprotocol/protocolVersion": version,
        "io.modelcontextprotocol/clientCapabilities": {},
    }
    if version == CURRENT_VERSION:
        result["io.modelcontextprotocol/clientInfo"] = {"name": "bridge-verifier"}
    return result


def tool_call(
    name: str,
    *,
    request_id=None,
    arguments=None,
    version: str = CURRENT_VERSION,
) -> dict:
    request = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": name,
            "arguments": {} if arguments is None else arguments,
            "_meta": metadata(version),
        },
    }
    if request_id is not None:
        request["id"] = request_id
    return request


class Bridge:
    def __init__(self, helper: str) -> None:
        self.command = [helper, "mcp"]

    def exchange(self, payload: bytes) -> bytes:
        result = subprocess.run(
            self.command,
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        require(result.returncode == 0, f"MCP bridge exited with {result.returncode}")
        return result.stdout

    def request(self, request: dict) -> dict:
        payload = json.dumps(request, separators=(",", ":")).encode() + b"\n"
        return json.loads(self.exchange(payload))

    def raw_request(self, payload: bytes) -> dict:
        return json.loads(self.exchange(payload))


def verify_error(response: dict, expected_code: int) -> None:
    require(response["error"]["code"] == expected_code, "unexpected MCP error code")


def verify_error_responses(bridge: Bridge) -> None:
    verify_error(bridge.raw_request(b"{\n"), -32700)
    verify_error(bridge.raw_request(b"[]\n"), -32600)
    verify_error(
        bridge.request(tool_call("uptil.unknown", request_id="unknown-1")),
        -32602,
    )
    verify_error(
        bridge.request(
            tool_call("uptil.status", request_id="bad-arguments", arguments=False)
        ),
        -32602,
    )

    old_version = bridge.request(
        tool_call(
            "uptil.status",
            request_id="old-version",
            version=OLD_VERSION,
        )
    )
    verify_error(old_version, -32022)
    require(
        old_version["error"]["data"]
        == {"supported": [CURRENT_VERSION], "requested": OLD_VERSION},
        "unexpected protocol-version error data",
    )


def verify_notifications(bridge: Bridge) -> None:
    notification = tool_call("uptil.indefinite")
    payload = json.dumps(notification, separators=(",", ":")).encode() + b"\n"
    require(bridge.exchange(payload) == b"", "notification returned a response")


def verify_repeated_requests(bridge: Bridge) -> None:
    requests = [
        tool_call("uptil.status", request_id="status-1"),
        tool_call("uptil.status", request_id=2),
    ]
    payload = b"".join(
        json.dumps(request, separators=(",", ":")).encode() + b"\n"
        for request in requests
    )
    responses = [json.loads(line) for line in bridge.exchange(payload).splitlines()]
    require(len(responses) == 2, "expected exactly two MCP responses")
    require(
        [response["id"] for response in responses] == ["status-1", 2],
        "MCP response IDs were not preserved",
    )


def verify_stream_boundaries(bridge: Bridge) -> None:
    require(bridge.exchange(b"") == b"", "EOF returned an MCP response")
    require(
        bridge.exchange(b"x" * 65_537 + b"\n") == b"",
        "oversized input returned an MCP response",
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify MCP stdio edge cases.")
    parser.add_argument("helper")
    return parser.parse_args()


def main() -> None:
    bridge = Bridge(parse_arguments().helper)
    verify_error_responses(bridge)
    verify_notifications(bridge)
    verify_repeated_requests(bridge)
    verify_stream_boundaries(bridge)


if __name__ == "__main__":
    main()
