#!/usr/bin/env python3

import argparse
import datetime
import json
import math
import re


TIMESTAMP_PATTERN = re.compile(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def parse_timestamp(value: str) -> datetime.datetime:
    require(TIMESTAMP_PATTERN.fullmatch(value), f"invalid timestamp: {value}")
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def verify_status(raw_status: str, expected_state: str, expected_pid: int) -> None:
    status = json.loads(raw_status)
    expected_keys = {"schemaVersion", "state", "assertionActive", "pid"}
    if expected_state == "timed":
        expected_keys.add("until")
    if expected_state == "paused":
        expected_keys.add("remainingSeconds")

    require(isinstance(status, dict), "status must be an object")
    require(set(status) == expected_keys, "unexpected status keys")
    require(status["schemaVersion"] == 1, "unexpected schema version")
    require(status["state"] == expected_state, "unexpected state")
    require(
        isinstance(status["assertionActive"], bool),
        "assertionActive must be boolean",
    )
    require(
        status["assertionActive"] == (expected_state in ("timed", "indefinite")),
        "unexpected assertion state",
    )
    require(
        type(status["pid"]) is int
        and status["pid"] == expected_pid
        and status["pid"] > 0,
        "unexpected PID",
    )

    if expected_state == "timed":
        parse_timestamp(status["until"])
    if expected_state == "paused":
        remaining = status["remainingSeconds"]
        require(
            type(remaining) in (int, float) and math.isfinite(remaining) and remaining > 0,
            "remainingSeconds must be a positive finite number",
        )


def verify_deadline_delta(
    earlier: str,
    later: str,
    minimum_seconds: float,
    maximum_seconds: float,
) -> None:
    delta = (parse_timestamp(later) - parse_timestamp(earlier)).total_seconds()
    require(
        minimum_seconds < delta < maximum_seconds,
        f"unexpected deadline delta: {delta}",
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the UpTil status contract.")
    commands = parser.add_subparsers(dest="command", required=True)

    status = commands.add_parser("status", help="verify an exact status payload")
    status.add_argument("payload")
    status.add_argument("expected_state", choices=("idle", "timed", "indefinite", "paused"))
    status.add_argument("expected_pid", type=int)

    delta = commands.add_parser(
        "deadline-delta",
        help="verify the open interval between two RFC 3339 deadlines",
    )
    delta.add_argument("earlier")
    delta.add_argument("later")
    delta.add_argument("minimum_seconds", type=float)
    delta.add_argument("maximum_seconds", type=float)

    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    if arguments.command == "status":
        verify_status(
            arguments.payload,
            arguments.expected_state,
            arguments.expected_pid,
        )
    else:
        verify_deadline_delta(
            arguments.earlier,
            arguments.later,
            arguments.minimum_seconds,
            arguments.maximum_seconds,
        )


if __name__ == "__main__":
    main()
