// CloudFront Function (cloudfront-js-2.0) - viewer-request rewriter.
//
// Resolves the active version prefix per request and rewrites the URI so
// CloudFront fetches /<version>/<...> from S3. Because CloudFront uses the
// rewritten URI as part of the cache key, flipping the active version in KVS
// produces a fresh cache key and serves the new build immediately — no
// invalidation required.
//
// Version resolution order:
//   1. KVS[host]    — pin a specific host to a specific version (previews,
//                     staging overrides, gradual cutovers).
//   2. KVS[active]  — the canonical production pointer.
//   3. DEFAULT_VERSION — apply-time fallback so a fresh stack works before
//                        any KVS edits.
//
// URI rewriting (after the version prefix is decided):
//   spa routing:
//     /             -> /<v>/<index>
//     /foo.js       -> /<v>/foo.js                (asset, has extension)
//     /.well-known/openid-configuration
//                   -> /<v>/.well-known/openid-configuration  (dotted seg)
//     /foo[/]       -> /<v>/<index>               (router handles client-side)
//   filesystem routing:
//     /             -> /<v>/<index>
//     /foo.js       -> /<v>/foo.js
//     /.well-known/foo
//                   -> /<v>/.well-known/foo       (dotted seg)
//     /foo[/]       -> /<v>/foo/<index>           (clean URLs)
//
// Tokens substituted at apply time via templatefile():
//   ${kvs_id}, ${default_version}, ${index_document}, ${routing}

import cf from 'cloudfront';

var KVS_ID = '${kvs_id}';
var DEFAULT_VERSION = '${default_version}';
var INDEX_DOCUMENT = '${index_document}';
var ROUTING = '${routing}';

var kvs = cf.kvs(KVS_ID);

async function lookup(key) {
    try {
        var value = await kvs.get(key);
        return value || null;
    } catch (e) {
        return null;
    }
}

async function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var host = (headers.host && headers.host.value) || '';
    var uri = request.uri || '/';

    var version = (host && await lookup(host))
        || (await lookup('active'))
        || DEFAULT_VERSION;

    var lastSlash = uri.lastIndexOf('/');
    var lastDot = uri.lastIndexOf('.');
    var hasExtension = lastDot > lastSlash;
    // Any path segment beginning with a dot (e.g. `/.well-known/...`,
    // `/.config/...`) is treated as a literal asset path. By convention
    // these directories hold configuration files that must be served
    // verbatim — clean-URL rewriting to `<dir>/index.html` would 404
    // even when the file exists. RFC 8615 (`.well-known`) is the
    // canonical case.
    var hasDottedSegment = uri.indexOf('/.') >= 0;

    if (uri === '/') {
        request.uri = '/' + version + '/' + INDEX_DOCUMENT;
    } else if (hasExtension || hasDottedSegment) {
        request.uri = '/' + version + uri;
    } else if (ROUTING === 'spa') {
        request.uri = '/' + version + '/' + INDEX_DOCUMENT;
    } else {
        var trimmed = uri.charAt(uri.length - 1) === '/' ? uri.slice(0, -1) : uri;
        request.uri = '/' + version + trimmed + '/' + INDEX_DOCUMENT;
    }

    return request;
}
