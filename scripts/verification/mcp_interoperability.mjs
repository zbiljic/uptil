import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";

const PROTOCOL_VERSION = "2026-07-28";
const EXPECTED_TOOLS = [
  "uptil.status",
  "uptil.start",
  "uptil.indefinite",
  "uptil.extend",
  "uptil.shorten",
  "uptil.stop",
];
const LIVE_STATES = new Set(["idle", "timed", "indefinite"]);
const TIMESTAMP_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function hasExactKeys(value, expectedKeys) {
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  return JSON.stringify(actual) === JSON.stringify(expected);
}

function isValidTimestamp(value) {
  return (
    typeof value === "string" &&
    TIMESTAMP_PATTERN.test(value) &&
    !Number.isNaN(Date.parse(value))
  );
}

function verifyStatus(status, expectedPID) {
  assert(
    status && status.schemaVersion === 1 && LIVE_STATES.has(status.state),
    "uptil.status did not return a valid structured status",
  );

  const expectedKeys = ["schemaVersion", "state", "assertionActive", "pid"];
  if (status.state === "timed") {
    expectedKeys.push("until");
  }

  assert(
    hasExactKeys(status, expectedKeys),
    "uptil.status did not return the exact flat structured status",
  );
  assert(
    typeof status.assertionActive === "boolean" &&
      status.assertionActive === (status.state !== "idle"),
    "uptil.status returned an inconsistent assertion state",
  );
  assert(
    Number.isSafeInteger(status.pid) && status.pid > 0,
    "uptil.status returned an invalid PID",
  );
  assert(
    status.state !== "timed" || isValidTimestamp(status.until),
    "uptil.status returned an invalid deadline",
  );

  if (expectedPID) {
    assert(
      String(status.pid) === expectedPID,
      `status PID ${status.pid} did not match ${expectedPID}`,
    );
  }
}

async function main() {
  const [helper, expectedPID] = process.argv.slice(2);
  const transport = new StdioClientTransport({
    command: helper,
    args: ["mcp"],
    stderr: "pipe",
  });
  const client = new Client(
    { name: "uptil-interoperability-gate", version: "0.1.0" },
    { versionNegotiation: { mode: { pin: PROTOCOL_VERSION } } },
  );

  try {
    await client.connect(transport);

    const discovery = client.getDiscoverResult();
    assert(
      discovery?.supportedVersions?.includes(PROTOCOL_VERSION),
      `server/discover did not confirm MCP ${PROTOCOL_VERSION}`,
    );

    const listed = await client.listTools();
    assert(
      JSON.stringify(listed.tools.map((tool) => tool.name)) ===
        JSON.stringify(EXPECTED_TOOLS),
      "tools/list did not return the exact ordered UpTil catalog",
    );

    const result = await client.callTool({
      name: "uptil.status",
      arguments: {},
    });
    verifyStatus(result.structuredContent, expectedPID);

    console.error(
      `PASS: official MCP client negotiated ${PROTOCOL_VERSION} and verified UpTil status.`,
    );
  } finally {
    await client.close();
    await transport.close();
  }
}

await main();
