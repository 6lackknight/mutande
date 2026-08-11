/** Minimal MCP JSON-RPC shapes (Streamable HTTP). */

export interface McpRequest {
  jsonrpc?: string;
  id?: string | number | null;
  method: string;
  params?: Record<string, unknown>;
}

export interface McpResponse {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}

export function mcpSuccess(
  id: string | number | null | undefined,
  result: unknown,
): McpResponse {
  return { jsonrpc: "2.0", id: id ?? null, result };
}

export function mcpError(
  id: string | number | null | undefined,
  code: number,
  message: string,
  data?: unknown,
): McpResponse {
  return {
    jsonrpc: "2.0",
    id: id ?? null,
    error: { code, message, ...(data !== undefined ? { data } : {}) },
  };
}

export function toolTextResult(text: string, isError = false) {
  return {
    content: [{ type: "text", text }],
    isError,
  };
}
