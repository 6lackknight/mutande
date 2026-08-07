function classifyResponseStreaming(res) {
  if (!res.body) {
    return { isStreaming: false };
  }
  const contentType = res.headers.get("content-type") ?? "";
  const contentLength = res.headers.get("content-length");
  if (/^text\/event-stream\b/i.test(contentType) || /^application\/(x-)?ndjson\b/i.test(contentType) || /^application\/stream\+json\b/i.test(contentType) || /^text\/plain\b/i.test(contentType) && !contentLength) {
    return { isStreaming: true };
  }
  return { isStreaming: false };
}
async function streamResponse(span, res) {
  const classification = classifyResponseStreaming(res);
  if (!classification.isStreaming || !res.body) {
    span.end();
    return res;
  }
  try {
    return new Response(
      monitorStream(res.body, () => span.end()),
      {
        status: res.status,
        statusText: res.statusText,
        headers: res.headers
      }
    );
  } catch (_e) {
    span.end();
    return res;
  }
}
function monitorStream(stream, onDone) {
  const reader = stream.getReader();
  reader.closed.then(
    () => onDone(),
    () => onDone()
  );
  return new ReadableStream({
    async start(controller) {
      let result;
      do {
        result = await reader.read();
        if (result.value) {
          try {
            controller.enqueue(result.value);
          } catch (er) {
            controller.error(er);
            reader.releaseLock();
            return;
          }
        }
      } while (!result.done);
      controller.close();
      reader.releaseLock();
    }
  });
}

export { classifyResponseStreaming, streamResponse };
//# sourceMappingURL=streaming.js.map
