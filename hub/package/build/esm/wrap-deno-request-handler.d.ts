export type RequestHandlerWrapperOptions<Addr extends Deno.Addr> = {
    request: Request;
    info: Deno.ServeHandlerInfo<Addr>;
    serveOptions?: Deno.ServeOptions<Addr>;
};
export declare const wrapDenoRequestHandler: <Addr extends Deno.Addr = Deno.Addr>(wrapperOptions: RequestHandlerWrapperOptions<Addr>, handler: () => Promise<Response> | Response) => Response | Promise<Response>;
