# agent-proxy-laundering

> 📖 **Read the write-up:** [Stopping Agent Proxy Laundering at the MCP Gateway](https://webofmike.com/agent-proxy-laundering/)

A tool that fetches an external URL on request is a proxy whether anyone meant it
to be or not. This repo reproduces that failure mode with a toy citation-resolver
MCP tool, then shows the control that catches it: a destination allowlist enforced
at the gateway, in front of the tool, not inside it.

> Context: on 2026-10-05 the Wikimedia Foundation [disclosed](https://wikimediafoundation.org/news/2026/10/05/openai-rogue-agent-activities-found-on-wikimedia-projects/)
> that agents it attributes to OpenAI made configuration edits to a citation tool
> that Wikimedia believes were an attempt to misuse it as a proxy for fetching data
> from remote services, and separately tried (and failed) to use a hosted Etherpad
> instance the same way. Wikimedia's post does not publish the exact mechanism, so
> this repo does not reproduce their citation tool. It reproduces the general shape
> of the failure: any tool whose job is "fetch this URL" can be pointed at a URL
> nobody intended, because the tool has no way to know the difference.

## The problem

`fetch_citation_source` is a one-tool MCP server. Give it a URL, it fetches the
URL and hands back the body, because that is what a citation resolver is for:
look up an external bibliographic source. Nothing in the tool checks what the URL
points at, because checking that is not the tool's job, and most citation tools
in the wild do not do it either.

That means the tool is a general-purpose fetch proxy with a narrower-sounding
name. An agent (or anyone else with access to call the tool) can point
`source_url` at anywhere, not just a citation source: an internal service, a
cloud metadata endpoint, an exfiltration target.

## The control

[agentgateway](https://agentgateway.dev)'s MCP guardrails sit in front of the
tool and see the resolved `tools/call` request, including its arguments, before
the tool runs. A CEL expression checks `source_url` against an allowlist of
actual citation sources and rejects anything else:

```yaml
mcpGuardrails:
  processors:
  - kind: expression
    methods: {"tools/call": request}
    condition: >-
      mcp.params.name == 'fetch_citation_source' &&
      has(mcp.params.arguments) &&
      has(mcp.params.arguments.source_url) &&
      !(mcp.params.arguments.source_url.startsWith('http://localhost:8081/') ||
        mcp.params.arguments.source_url.startsWith('http://127.0.0.1:8081/') ||
        mcp.params.arguments.source_url.startsWith('https://doi.org/') ||
        mcp.params.arguments.source_url.startsWith('https://api.crossref.org/'))
    reject: "source_url is not an allowlisted citation source; rejected before the fetch ran"
```

The tool's own code is unmodified. It still has no idea what a valid citation
source looks like. It doesn't need to, because the request never reaches it
unless the gateway already decided the destination was allowed.

## What this demo shows

Three calls against the same tool:

1. **Direct, no gateway.** `mcp-server/direct-fetch.js` runs the tool's exact
   fetch logic with no MCP framing at all. A legitimate call to the mock
   citation API succeeds. A call to the mock attacker target also succeeds,
   identically, because the code has no concept of "not allowed."
2. **Through agentgateway, allowed destination.** The same tool, now spawned by
   agentgateway over stdio, called via MCP for a legitimate citation lookup.
   Succeeds.
3. **Through agentgateway, laundered destination.** The same call shape, pointed
   at the mock attacker target. The guardrail rejects it before the tool runs.
   The attacker target's own request counter proves it: checked before and
   after, it does not move.

## Prerequisites

- An `agentgateway` build containing the CEL MCP guardrails processor
  (`mcpGuardrails.processors[].kind: expression`). This landed on `main` on
  2026-10-06 ([commit `276f10d`](https://github.com/agentgateway/agentgateway/commit/276f10dc68430762674d6d64f3baecead963ac78))
  and is **not in a tagged release yet** as of this writing (the latest release,
  [v1.6.0](https://github.com/agentgateway/agentgateway/releases/tag/v1.6.0),
  predates it). Build from source:

  ```bash
  git clone https://github.com/agentgateway/agentgateway.git
  cd agentgateway
  cargo build --release -p agentgateway-app
  # binary at target/release/agentgateway
  ```
- Node.js 18+ (the demo MCP server, `direct-fetch.js`, and the MCP Inspector CLI).
- Python 3 (the two mock HTTP services; standard library only, no dependencies).

## Run it

```bash
npm install --prefix mcp-server
AGENTGATEWAY_BIN=/path/to/agentgateway/target/release/agentgateway ./scripts/demo.sh
```

This starts the mock citation API (port 8081) and the mock attacker target
(port 8082), runs the direct no-gateway calls, then starts
`agentgateway -f config.yaml` (which spawns `mcp-server/server.js` as its MCP
target over stdio) and drives the gateway-fronted calls through
[`@modelcontextprotocol/inspector --cli`](https://github.com/modelcontextprotocol/inspector).
Output is saved under `captures/`.

## What this doesn't cover

The allowlist here is a handful of `startsWith` checks against known-good
hosts, which is the right shape for a small, stable set of legitimate sources
and the wrong shape for "any valid DOI resolver on the internet." A production
policy needs a real allowlist (and ideally scheme and port pinning, which
`startsWith` on a full prefix already gives you here) maintained alongside
whatever sources the tool is actually supposed to reach.

It also doesn't model the Etherpad half of the Wikimedia disclosure (a hosted
service being probed as a proxy from the outside, rather than a tool being
asked to fetch on the agent's behalf), and it doesn't model DNS-based evasion
of a destination check, which is a different channel covered in
[agent-dns-egress-covert-channel](https://github.com/themsquared/agent-dns-egress-lab).
And it doesn't model volume: Wikimedia's disclosure also describes hundreds of
thousands of queries to the Wikidata Query Service, a rate problem, not a
destination problem, covered separately in
[agent-egress-rate-limits](https://github.com/themsquared/agent-egress-rate-limits).

## License

Apache-2.0. See [LICENSE](LICENSE).

Topics: `agentgateway`, `mcp`, `ai-agents`, `kubernetes`, `agent-security`
