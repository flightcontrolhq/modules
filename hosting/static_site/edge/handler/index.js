// @ts-check
"use strict";

// Lambda@Edge origin-request handler for static-site hosting on S3.
//
// Trigger: origin-request, single S3 origin.
// Responsibilities:
//   1. Resolve the active deployment prefix (x-fc-deployment-id custom header).
//   2. For non-asset URIs, look up the matching object in S3:
//        a. <prefix>/<uri>.html
//        b. <prefix>/<uri>/index.html
//        c. (spa mode only) <prefix>/index.html as fallback
//   3. Optional trailing-slash redirect via x-fc-trailing-slash=Enabled.
//   4. On final miss, return a 404 with the deployment's custom 404.html
//      (cached in module scope) or a built-in fallback page.
//
// The Lambda is created only in 'filesystem_previews' mode of the
// hosting/static_site composite. It runs at regional edge caches (not every
// POP), so the parallel headObject calls below are critical for latency.

const path = require("path");

const {
  normalizeUri,
  getOriginHeader,
  getFolderPrefix,
  isSourceFile,
  fulfilledValue,
  fallback404,
} = require("./utils.js");
const S3Wrapper = require("./s3.js");

let s3Client;

/**
 * @param {{ Records: { cf: { request: any } }[] }} event
 * @param {*} _context
 * @param {(err: any, response: any) => void} callback
 */
exports.handler = async (event, _context, callback) => {
  const record = event.Records && event.Records[0];
  const request = record && record.cf && record.cf.request;
  if (!request) {
    return callback(null, { status: "500", body: "Invalid CloudFront event" });
  }

  const origin = request.origin && request.origin.s3;
  if (!origin || origin.domainName.indexOf(".s3.") < 0) {
    return callback(null, { status: "500", body: "Origin must be an S3 bucket" });
  }
  const bucket = origin.domainName.slice(0, origin.domainName.indexOf(".s3."));

  const region = getOriginHeader({
    request,
    headerKey: "x-fc-region",
    defaultValue: "us-east-1",
  });
  const mode = getOriginHeader({
    request,
    headerKey: "static_mode",
    defaultValue: "spa",
  });
  const trailingSlash = getOriginHeader({
    request,
    headerKey: "x-fc-trailing-slash",
    defaultValue: "Disabled",
  });

  const folderPrefix = getFolderPrefix(request);
  const originalUri = request.uri;
  const normalizedUri = normalizeUri(originalUri);
  const hasExtension = isSourceFile(normalizedUri);
  const endsWithSlash = originalUri.endsWith("/");

  if (trailingSlash === "Enabled" && !hasExtension && !endsWithSlash) {
    const target = request.querystring
      ? `${originalUri}/?${request.querystring}`
      : `${originalUri}/`;
    return callback(null, {
      status: "302",
      headers: { location: [{ key: "Location", value: target }] },
    });
  }

  // Asset request: pass through unchanged (just prefix the deployment folder).
  if (hasExtension) {
    request.uri = "/" + path.posix.join(folderPrefix, normalizedUri);
    return callback(null, request);
  }

  if (!s3Client) {
    s3Client = new S3Wrapper({ region });
  }

  const matchCtx = { s3: s3Client, bucket, folderPrefix, normalizedUri };

  // Fire all candidate lookups in parallel; await in priority order.
  const htmlMatchPromise = matchHtmlFile(matchCtx);
  const dirIndexPromise = matchDirectoryIndex(matchCtx);
  const spaIndexPromise = mode === "spa" ? matchSpaIndex(matchCtx) : Promise.resolve(null);
  const customNotFoundPromise = loadCustomNotFound(matchCtx);

  let resolved = await htmlMatchPromise;
  if (!resolved) resolved = await dirIndexPromise;
  if (!resolved && mode === "spa") resolved = await spaIndexPromise;

  if (resolved) {
    request.uri = "/" + resolved;
    return callback(null, request);
  }

  const notFoundBody = (await customNotFoundPromise) || fallback404;
  return callback(null, {
    status: "404",
    statusDescription: "Not Found",
    body: notFoundBody,
    headers: {
      "content-type": [{ key: "Content-Type", value: "text/html" }],
    },
  });
};

/**
 * @param {{s3: S3Wrapper, bucket: string, folderPrefix: string, normalizedUri: string}} ctx
 */
async function matchHtmlFile({ s3, bucket, folderPrefix, normalizedUri }) {
  const candidate = normalizedUri === ""
    ? "index.html"
    : (normalizedUri.endsWith(".html") ? normalizedUri : `${normalizedUri}.html`);
  const key = path.posix.join(folderPrefix, candidate);
  return (await keyExists(s3, bucket, key)) ? key : null;
}

/**
 * @param {{s3: S3Wrapper, bucket: string, folderPrefix: string, normalizedUri: string}} ctx
 */
async function matchDirectoryIndex({ s3, bucket, folderPrefix, normalizedUri }) {
  if (normalizedUri.endsWith(".html")) return null;
  const key = path.posix.join(folderPrefix, normalizedUri, "index.html");
  return (await keyExists(s3, bucket, key)) ? key : null;
}

/**
 * @param {{s3: S3Wrapper, bucket: string, folderPrefix: string}} ctx
 */
async function matchSpaIndex({ s3, bucket, folderPrefix }) {
  const key = path.posix.join(folderPrefix, "index.html");
  return (await keyExists(s3, bucket, key)) ? key : null;
}

/**
 * @param {S3Wrapper} s3
 * @param {string} bucket
 * @param {string} key
 */
async function keyExists(s3, bucket, key) {
  try {
    await s3.headObject({ Bucket: bucket, Key: key });
    return true;
  } catch {
    return false;
  }
}

// Cache the deployment's 404 page across invocations of the same container.
// Each Lambda@Edge container handles one deployment prefix at a time in
// practice; if the prefix changes (rare), the cache is keyed by it.
const notFoundCache = new Map();

/**
 * @param {{s3: S3Wrapper, bucket: string, folderPrefix: string}} ctx
 */
async function loadCustomNotFound({ s3, bucket, folderPrefix }) {
  if (notFoundCache.has(folderPrefix)) {
    return notFoundCache.get(folderPrefix);
  }

  const candidates = [
    path.posix.join(folderPrefix, "404.html"),
    path.posix.join(folderPrefix, "404", "index.html"),
  ];

  const results = await Promise.allSettled(
    candidates.map((key) => s3.getObject({ Bucket: bucket, Key: key })),
  );

  for (const result of results) {
    const value = fulfilledValue(result);
    if (value && value.Body) {
      const bytes = await value.Body.transformToByteArray();
      const body = new TextDecoder("utf-8").decode(bytes);
      notFoundCache.set(folderPrefix, body);
      return body;
    }
  }

  notFoundCache.set(folderPrefix, null);
  return null;
}
