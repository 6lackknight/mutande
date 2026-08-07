export type ServeParams = [Deno.ServeHandler<Deno.NetAddr>] | [Deno.ServeUnixOptions, Deno.ServeHandler<Deno.UnixAddr>] | [Deno.ServeVsockOptions, Deno.ServeHandler<Deno.VsockAddr>] | [Deno.ServeTcpOptions | (Deno.ServeTcpOptions & Deno.TlsCertifiedKeyPem), Deno.ServeHandler<Deno.NetAddr>] | [Deno.ServeUnixOptions & Deno.ServeInit<Deno.UnixAddr>] | [Deno.ServeVsockOptions & Deno.ServeInit<Deno.VsockAddr>] | [(Deno.ServeTcpOptions | (Deno.ServeTcpOptions & Deno.TlsCertifiedKeyPem)) & Deno.ServeInit<Deno.NetAddr>];
export declare const denoServeIntegration: () => import("@sentry/core").Integration & {
    name: "DenoServe";
};
