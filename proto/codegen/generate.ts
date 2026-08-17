/**
 * RPC catalog codegen — reads ../rpc-catalog.json and emits checked-in artifacts:
 *
 *   core/src/daemon/rpc_passthrough.g.rs          passthrough spec table (Rust)
 *   hub/routes/rpc_passthrough.g.ts               Hono passthrough router
 *   app/lib/services/daemon_rpc_catalog.g.dart    method/param metadata (Dart)
 *   proto/generated/rpc-routes.g.json             passthrough route table (hub golden tests)
 *
 * The wire is frozen. Run: deno task generate (from proto/).
 */

interface CatalogParam {
  name: string;
  type: string;
  required: boolean;
  aliases?: string[];
}

interface CatalogHub {
  verb: string;
  path: string;
  body?: string[];
  query_flags?: Record<string, string>;
  unwrap?: string;
  /** Route auth: "bearer" (default) or "public" (no auth middleware). */
  auth?: "bearer" | "public";
  /** HubStore method, e.g. "listCollabs" or "enterprise.getListingPublic". */
  store?: string;
  /** HTTP status (default 200). */
  status?: number;
  /** Wrap the store return as `{ [reply_wrap]: result }`. */
  reply_wrap?: string;
}

interface CatalogMethod {
  name: string;
  aliases?: string[];
  kind: "passthrough" | "core" | "stub";
  params: CatalogParam[];
  params_schema?: string;
  hub?: CatalogHub;
  result?: { wrap?: string; ok?: boolean };
  notes?: string;
}

interface Catalog {
  version: number;
  description: string;
  methods: CatalogMethod[];
}

const HEADER =
  "GENERATED FILE — do not edit. Source: proto/rpc-catalog.json (deno task generate in proto/).";

function pathParamsOf(path: string): string[] {
  return [...path.matchAll(/\{([a-z_]+)\}/g)].map((x) => x[1]);
}

export function validateCatalog(catalog: Catalog): void {
  const seen = new Set<string>();
  for (const m of catalog.methods) {
    for (const key of [m.name, ...(m.aliases ?? [])]) {
      if (seen.has(key)) throw new Error(`duplicate method name/alias: ${key}`);
      seen.add(key);
    }
    const paramNames = new Set(m.params.map((p) => p.name));
    if (m.kind === "passthrough") {
      if (!m.hub) throw new Error(`passthrough ${m.name} missing hub mapping`);
      if (!m.hub.store) {
        throw new Error(`passthrough ${m.name} missing hub.store binding`);
      }
      for (const p of pathParamsOf(m.hub.path)) {
        if (!paramNames.has(p)) {
          throw new Error(`${m.name}: hub path param {${p}} not declared in params`);
        }
      }
      for (const b of m.hub.body ?? []) {
        if (!paramNames.has(b)) {
          throw new Error(`${m.name}: hub body param ${b} not declared in params`);
        }
      }
      for (const flagParam of Object.values(m.hub.query_flags ?? {})) {
        if (!paramNames.has(flagParam)) {
          throw new Error(
            `${m.name}: query flag param ${flagParam} not declared in params`,
          );
        }
      }
    } else if (m.hub) {
      throw new Error(`${m.kind} method ${m.name} must not carry a hub mapping`);
    }
  }
}

function rustStrArray(items: string[]): string {
  return items.length === 0 ? "&[]" : `&[${items.map((s) => JSON.stringify(s)).join(", ")}]`;
}

function paramSpec(m: CatalogMethod, name: string): CatalogParam {
  const p = m.params.find((x) => x.name === name);
  if (!p) throw new Error(`${m.name}: unknown param ${name}`);
  return p;
}

function rustParamSpec(p: CatalogParam): string {
  return `ParamSpec { name: ${JSON.stringify(p.name)}, aliases: ${
    rustStrArray(p.aliases ?? [])
  }, required: ${p.required}, ty: ${JSON.stringify(p.type)} }`;
}

export function emitRust(catalog: Catalog): string {
  const passthroughs = catalog.methods.filter((m) => m.kind === "passthrough");
  const lines: string[] = [];
  lines.push(`// ${HEADER}`);
  lines.push(`// Declarative hub-passthrough specs for the daemon JSON-RPC dispatch.`);
  lines.push(``);
  lines.push(`/// One RPC param: canonical name, accepted aliases, requiredness, wire type.`);
  lines.push(`pub struct ParamSpec {`);
  lines.push(`    pub name: &'static str,`);
  lines.push(`    pub aliases: &'static [&'static str],`);
  lines.push(`    pub required: bool,`);
  lines.push(`    /// Catalog type: string, bool, json, json[], string[].`);
  lines.push(`    pub ty: &'static str,`);
  lines.push(`}`);
  lines.push(``);
  lines.push(`/// One hub-passthrough RPC: verb + templated path + param routing + result shaping.`);
  lines.push(`pub struct PassthroughSpec {`);
  lines.push(`    pub name: &'static str,`);
  lines.push(`    pub verb: &'static str,`);
  lines.push(`    pub path: &'static str,`);
  lines.push(`    pub path_params: &'static [ParamSpec],`);
  lines.push(`    pub body_params: &'static [ParamSpec],`);
  lines.push(`    /// (query_key, bool param) — appended as ?key=1 when the param is truthy.`);
  lines.push(`    pub query_flags: &'static [(&'static str, ParamSpec)],`);
  lines.push(`    /// Field plucked from the hub response before shaping the RPC result.`);
  lines.push(`    pub hub_unwrap: Option<&'static str>,`);
  lines.push(`    /// RPC result is wrapped as {wrap: value} when set.`);
  lines.push(`    pub result_wrap: Option<&'static str>,`);
  lines.push(`    /// RPC result is a bare {"ok": true} regardless of hub body.`);
  lines.push(`    pub result_ok: bool,`);
  lines.push(`}`);
  lines.push(``);
  lines.push(`pub const PASSTHROUGH_SPECS: &[PassthroughSpec] = &[`);
  for (const m of passthroughs) {
    const hub = m.hub!;
    const pathParams = pathParamsOf(hub.path);
    const flags = Object.entries(hub.query_flags ?? {});
    lines.push(`    PassthroughSpec {`);
    lines.push(`        name: ${JSON.stringify(m.name)},`);
    lines.push(`        verb: ${JSON.stringify(hub.verb)},`);
    lines.push(`        path: ${JSON.stringify(hub.path)},`);
    lines.push(
      `        path_params: ${
        pathParams.length === 0
          ? "&[]"
          : `&[${pathParams.map((p) => rustParamSpec(paramSpec(m, p))).join(", ")}]`
      },`,
    );
    lines.push(
      `        body_params: ${
        (hub.body ?? []).length === 0
          ? "&[]"
          : `&[${(hub.body ?? []).map((p) => rustParamSpec(paramSpec(m, p))).join(", ")}]`
      },`,
    );
    lines.push(
      `        query_flags: ${
        flags.length === 0
          ? "&[]"
          : `&[${
            flags.map(([k, v]) => `(${JSON.stringify(k)}, ${rustParamSpec(paramSpec(m, v))})`)
              .join(", ")
          }]`
      },`,
    );
    lines.push(
      `        hub_unwrap: ${hub.unwrap ? `Some(${JSON.stringify(hub.unwrap)})` : "None"},`,
    );
    lines.push(
      `        result_wrap: ${m.result?.wrap ? `Some(${JSON.stringify(m.result.wrap)})` : "None"},`,
    );
    lines.push(`        result_ok: ${m.result?.ok === true},`);
    lines.push(`    },`);
  }
  lines.push(`];`);
  lines.push(``);
  return lines.join("\n");
}

export function emitDart(catalog: Catalog): string {
  const lines: string[] = [];
  lines.push(`// ${HEADER}`);
  lines.push(`// Daemon JSON-RPC method/param metadata used by FakeDaemonClient.`);
  lines.push(``);
  lines.push(`/// kind: passthrough = mechanical hub forward; core = daemon logic; stub = removed.`);
  lines.push(`class DaemonRpcMethod {`);
  lines.push(`  const DaemonRpcMethod({`);
  lines.push(`    required this.kind,`);
  lines.push(`    this.aliases = const [],`);
  lines.push(`    this.requiredParams = const [],`);
  lines.push(`    this.optionalParams = const [],`);
  lines.push(`  });`);
  lines.push(``);
  lines.push(`  final String kind;`);
  lines.push(`  final List<String> aliases;`);
  lines.push(`  final List<String> requiredParams;`);
  lines.push(`  final List<String> optionalParams;`);
  lines.push(`}`);
  lines.push(``);
  lines.push(`const Map<String, DaemonRpcMethod> daemonRpcCatalog = {`);
  for (const m of catalog.methods) {
    const req = m.params.filter((p) => p.required).map((p) => p.name);
    const opt = m.params.filter((p) => !p.required).map((p) => p.name);
    const parts: string[] = [`kind: '${m.kind}'`];
    if ((m.aliases ?? []).length > 0) {
      parts.push(`aliases: [${m.aliases!.map((a) => `'${a}'`).join(", ")}]`);
    }
    if (req.length > 0) {
      parts.push(`requiredParams: [${req.map((p) => `'${p}'`).join(", ")}]`);
    }
    if (opt.length > 0) {
      parts.push(`optionalParams: [${opt.map((p) => `'${p}'`).join(", ")}]`);
    }
    lines.push(`  '${m.name}': DaemonRpcMethod(${parts.join(", ")}),`);
  }
  lines.push(`};`);
  lines.push(``);
  return lines.join("\n");
}

export function emitRoutes(catalog: Catalog): string {
  const routes = catalog.methods
    .filter((m) => m.kind === "passthrough")
    .map((m) => ({
      rpc: m.name,
      verb: m.hub!.verb,
      path: m.hub!.path,
      auth: m.hub!.auth ?? "bearer",
    }));
  return JSON.stringify({ comment: HEADER, routes }, null, 2) + "\n";
}

function honoVerb(verb: string): string {
  const v = verb.toLowerCase();
  if (!["get", "post", "put", "patch", "delete"].includes(v)) {
    throw new Error(`unsupported hub verb ${verb}`);
  }
  return v;
}

export function emitHub(catalog: Catalog): string {
  const passthroughs = catalog.methods.filter((m) => m.kind === "passthrough");
  const lines: string[] = [];
  lines.push(`// ${HEADER}`);
  lines.push(`import { Hono } from "hono";`);
  lines.push(`import { authMiddleware, type HubEnv } from "../middleware/auth.ts";`);
  lines.push(`import type { HubStore } from "../store/store.ts";`);
  lines.push(``);
  lines.push(`/** Mechanical hub forwards declared in proto/rpc-catalog.json. */`);
  lines.push(`export function createPassthroughRoutes(store: HubStore) {`);
  lines.push(`  const routes = new Hono<HubEnv>();`);
  lines.push(`  const auth = authMiddleware(store);`);
  lines.push(``);
  for (const m of passthroughs) {
    const hub = m.hub!;
    const honoPath = hub.path.replaceAll(/\{([a-z_]+)\}/g, ":$1");
    const verb = honoVerb(hub.verb);
    const pathParams = pathParamsOf(hub.path);
    const needsAuth = hub.auth !== "public";
    const hasBody = (hub.body ?? []).length > 0;
    const flags = Object.entries(hub.query_flags ?? {});
    const status = hub.status ?? 200;
    const mw = needsAuth ? "auth, " : "";

    const args: string[] = [];
    if (needsAuth) args.push(`c.get("auth")`);
    for (const p of pathParams) {
      args.push(`decodeURIComponent(c.req.param(${JSON.stringify(p)})!)`);
    }
    if (hasBody) args.push("body");
    if (flags.length > 0) {
      const fields = flags.map(([queryKey]) =>
        `${queryKey}: c.req.query(${JSON.stringify(queryKey)}) === "1" || c.req.query(${
          JSON.stringify(queryKey)
        }) === "true"`
      );
      args.push(`{ ${fields.join(", ")} }`);
    }

    const call = `await store.${hub.store}(${args.join(", ")})`;
    const payload = hub.reply_wrap
      ? `{ ${hub.reply_wrap}: result }`
      : "result";
    const statusArg = status !== 200 ? `, ${status}` : "";

    lines.push(`  // ${m.name}`);
    lines.push(`  routes.${verb}(${JSON.stringify(honoPath)}, ${mw}async (c) => {`);
    if (hasBody) {
      lines.push(`    const body = await c.req.json();`);
    }
    lines.push(`    const result = ${call};`);
    lines.push(`    return c.json(${payload}${statusArg});`);
    lines.push(`  });`);
    lines.push(``);
  }
  lines.push(`  return routes;`);
  lines.push(`}`);
  lines.push(``);
  return lines.join("\n");
}

export interface GeneratedOutputs {
  [relPath: string]: string;
}

export function generateAll(catalog: Catalog): GeneratedOutputs {
  validateCatalog(catalog);
  return {
    "core/src/daemon/rpc_passthrough.g.rs": emitRust(catalog),
    "hub/routes/rpc_passthrough.g.ts": emitHub(catalog),
    "app/lib/services/daemon_rpc_catalog.g.dart": emitDart(catalog),
    "proto/generated/rpc-routes.g.json": emitRoutes(catalog),
  };
}

export function repoRootFromScript(): string {
  const here = new URL(".", import.meta.url).pathname;
  return new URL("../..", `file://${here}`).pathname.replace(/\/$/, "");
}

export function loadCatalog(root: string): Catalog {
  return JSON.parse(Deno.readTextFileSync(`${root}/proto/rpc-catalog.json`));
}

if (import.meta.main) {
  const outFlag = Deno.args.indexOf("--out");
  const root = repoRootFromScript();
  const outRoot = outFlag >= 0 ? Deno.args[outFlag + 1] : root;
  const outputs = generateAll(loadCatalog(root));
  for (const [rel, content] of Object.entries(outputs)) {
    const target = `${outRoot}/${rel}`;
    Deno.mkdirSync(target.slice(0, target.lastIndexOf("/")), { recursive: true });
    Deno.writeTextFileSync(target, content);
    console.log(`wrote ${target}`);
  }
}
