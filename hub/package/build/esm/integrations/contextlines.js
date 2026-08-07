import { LRUMap, defineIntegration, addContextToFrame } from '@sentry/core';

const INTEGRATION_NAME = "ContextLines";
const FILE_CONTENT_CACHE = new LRUMap(100);
const DEFAULT_LINES_OF_CONTEXT = 7;
async function readSourceFile(filename) {
  const cachedFile = FILE_CONTENT_CACHE.get(filename);
  if (cachedFile !== void 0) {
    return cachedFile;
  }
  let content = null;
  try {
    content = await Deno.readTextFile(filename);
  } catch {
  }
  FILE_CONTENT_CACHE.set(filename, content);
  return content;
}
const _contextLinesIntegration = ((options = {}) => {
  return {
    name: INTEGRATION_NAME,
    processEvent(event, _hint, client) {
      const contextLines = options.frameContextLines ?? client?.getDataCollectionOptions().frameContextLines ?? DEFAULT_LINES_OF_CONTEXT;
      return addSourceContext(event, contextLines);
    }
  };
});
const contextLinesIntegration = defineIntegration(_contextLinesIntegration);
async function addSourceContext(event, contextLines) {
  if (contextLines > 0 && event.exception?.values) {
    for (const exception of event.exception.values) {
      if (exception.stacktrace?.frames) {
        await addSourceContextToFrames(exception.stacktrace.frames, contextLines);
      }
    }
  }
  return event;
}
async function addSourceContextToFrames(frames, contextLines) {
  for (const frame of frames) {
    if (frame.filename && frame.in_app && frame.context_line === void 0) {
      const permission = await Deno.permissions.query({
        name: "read",
        path: frame.filename
      });
      if (permission.state == "granted") {
        const sourceFile = await readSourceFile(frame.filename);
        if (sourceFile) {
          try {
            const lines = sourceFile.split("\n");
            addContextToFrame(lines, frame, contextLines);
          } catch {
          }
        }
      }
    }
  }
}

export { contextLinesIntegration };
//# sourceMappingURL=contextlines.js.map
