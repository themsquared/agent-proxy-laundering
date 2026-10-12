// The exact fetch logic fetch_citation_source runs in server.js, called
// directly with no MCP framing and no gateway anywhere in the path. This is
// here to prove a negative: the tool's own code has no destination check at
// all, so "the tool decides" was never actually true. The boundary has to
// live somewhere that sees the call before the fetch happens.
const sourceUrl = process.argv[2];
if (!sourceUrl) {
  console.error("usage: node direct-fetch.js <source_url>");
  process.exit(1);
}

const res = await fetch(sourceUrl);
const body = await res.text();
console.log(`GET ${sourceUrl} -> ${res.status}: ${body.slice(0, 300)}`);
