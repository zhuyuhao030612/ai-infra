#!/usr/bin/env python3
"""mem0 MCP server — standard MCP protocol, ChromaDB + Ollama."""
import os, sys, json
from mem0 import Memory
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool

CONFIG = {
    "vector_store": {"provider": "chroma", "config": {"collection_name": "claude_mem", "path": os.path.join(os.path.dirname(__file__), "chroma_data")}},
    "llm": {"provider": "ollama", "config": {"model": "qwen2.5-coder:latest", "ollama_base_url": "http://localhost:11434"}},
    "embedder": {"provider": "ollama", "config": {"model": "nomic-embed-text:latest", "ollama_base_url": "http://localhost:11434"}},
}
memory = Memory.from_config(CONFIG)
USER_ID = os.environ.get("MEM0_USER_ID", "boss")
server = Server("local-memory")

@server.list_tools()
async def list_tools():
    return [
        Tool(name="add_memory", description="Add a memory. Args: content (str), tags (list[str], optional)", inputSchema={"type": "object", "properties": {"content": {"type": "string"}, "tags": {"type": "array", "items": {"type": "string"}}}, "required": ["content"]}),
        Tool(name="search_memory", description="Search memories semantically. Args: query (str), limit (int, default 5)", inputSchema={"type": "object", "properties": {"query": {"type": "string"}, "limit": {"type": "integer", "default": 5}}, "required": ["query"]}),
        Tool(name="get_all", description="Get all stored memories. Args: limit (int, default 50)", inputSchema={"type": "object", "properties": {"limit": {"type": "integer", "default": 50}}}),
        Tool(name="stats", description="Show memory statistics", inputSchema={"type": "object", "properties": {}}),
    ]

@server.call_tool()
async def call_tool(name, arguments):
    try:
        if name == "add_memory":
            r = memory.add(arguments["content"], user_id=USER_ID, metadata={"tags": arguments.get("tags", [])})
            mems = [m.get("memory", "") for m in r.get("results", [])]
            return [{"type": "text", "text": json.dumps({"ok": True, "memories": mems}, ensure_ascii=False)}]
        elif name == "search_memory":
            r = memory.search(arguments["query"], filters={"user_id": USER_ID}, limit=int(arguments.get("limit", 5)))
            results = [{"memory": m.get("memory", ""), "score": round(m.get("score", 0), 2)} for m in r.get("results", [])]
            return [{"type": "text", "text": json.dumps({"results": results}, ensure_ascii=False)}]
        elif name == "get_all":
            r = memory.get_all(filters={"user_id": USER_ID}, limit=int(arguments.get("limit", 50)))
            mems = [{"memory": m.get("memory", ""), "id": m.get("id", "")} for m in r.get("results", [])]
            return [{"type": "text", "text": json.dumps({"total": len(mems), "memories": mems}, ensure_ascii=False)}]
        elif name == "stats":
            r = memory.get_all(filters={"user_id": USER_ID}, limit=10000)
            return [{"type": "text", "text": json.dumps({"total": len(r.get("results", []))})}]
    except Exception as e:
        return [{"type": "text", "text": json.dumps({"error": str(e)})}]

async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
