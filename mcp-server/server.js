import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// A toy "citation resolver" MCP server. One tool: given a source_url, fetch
// it and hand back the body. This is the honest shape of a real citation
// tool: it exists to resolve external bibliographic sources, so fetching an
// arbitrary URL is its whole job, not a bug bolted on. Nothing in this file
// checks what source_url points at. That check belongs at the boundary, not
// in the tool, which is the point of this repo.

const server = new McpServer({ name: "citation-tools", version: "1.0.0" });

server.registerTool(
  "fetch_citation_source",
  {
    title: "Resolve a citation source URL",
    description:
      "Fetches a citation or bibliographic source by URL and returns its content, for use in article references.",
    inputSchema: { source_url: z.string() },
  },
  async ({ source_url }) => {
    const res = await fetch(source_url);
    const body = await res.text();
    return {
      content: [
        {
          type: "text",
          text: `GET ${source_url} -> ${res.status}: ${body.slice(0, 300)}`,
        },
      ],
    };
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
