// @ts-check
"use strict";

const { MAIN_FOLDER, VERSIONS_FOLDER } = require("./constants.cjs");

/**
 * Strip leading/trailing slashes and decode URI components.
 * @param {string} uri
 */
function normalizeUri(uri) {
  let out = uri;
  while (out.startsWith("/")) out = out.slice(1);
  while (out.endsWith("/")) out = out.slice(0, -1);
  return decodeURI(out);
}

/**
 * Read a custom origin header set on the CloudFront origin config.
 * Returns the provided default when missing.
 * @param {{ request: any, headerKey: string, defaultValue: string }} params
 */
function getOriginHeader({ request, headerKey, defaultValue }) {
  const headers = request.origin && request.origin.s3 && request.origin.s3.customHeaders;
  if (headers && headers[headerKey] && headers[headerKey][0]) {
    return headers[headerKey][0].value;
  }
  return defaultValue;
}

/**
 * Resolve the S3 folder prefix for this request.
 * x-fc-deployment-id == "" or MAIN_FOLDER  -> serve from MAIN_FOLDER
 * otherwise                                -> serve from VERSIONS_FOLDER/<id>
 *
 * The deployment id is set either by static origin header config
 * (filesystem mode) or by the CloudFront Function via KVS lookup
 * (filesystem_previews mode).
 *
 * @param {any} request
 */
function getFolderPrefix(request) {
  const deploymentId = getOriginHeader({
    request,
    headerKey: "x-fc-deployment-id",
    defaultValue: "",
  });

  if (deploymentId === "" || deploymentId === MAIN_FOLDER) {
    return MAIN_FOLDER;
  }
  return `${VERSIONS_FOLDER}/${deploymentId}`;
}

/**
 * @param {string} uri
 */
function isSourceFile(uri) {
  const lastSlash = uri.lastIndexOf("/");
  const lastDot = uri.lastIndexOf(".");
  return lastDot > lastSlash;
}

/**
 * @template T
 * @param {PromiseSettledResult<T>} settled
 */
function fulfilledValue(settled) {
  return settled.status === "fulfilled" ? settled.value : null;
}

const fallback404 = `<!DOCTYPE html>
<html>
<head><title>404 - Not Found</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#222}div{text-align:center}h1{font-size:3em;margin:0 0 .25em}p{font-size:1.25em;margin:0;color:#666}</style></head>
<body><div><h1>404</h1><p>This page could not be found.</p></div></body>
</html>`;

module.exports = {
  normalizeUri,
  getOriginHeader,
  getFolderPrefix,
  isSourceFile,
  fulfilledValue,
  fallback404,
};
