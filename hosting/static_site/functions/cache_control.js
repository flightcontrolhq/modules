// CloudFront Function (cloudfront-js-2.0) - viewer-response Cache-Control writer.
//
// Sets Cache-Control on every response based on the *rewritten* request URI
// (the viewer-request rewriter has already prepended /<version>/... by the
// time we run, so we strip the leading version segment first):
//
//   - Path matches an entry in HTML_OVERRIDES (e.g. /service-worker.js,
//     /favicon.ico, /robots.txt, PWA manifests) -> HTML cache. Stable,
//     non-hashed root files MUST never be cached as immutable; a wedged
//     service worker bricks the page until the user clears site data.
//   - Path contains a dotted-segment (e.g. /.well-known/openid-configuration)
//     -> HTML cache. RFC 8615 well-known URIs and dot-prefixed config
//     directories are served verbatim and are not content-hashed.
//   - Path has no extension or ends in .html / .htm -> HTML cache. Catches
//     SPA routes after the rewriter has pointed them at /<v>/index.html and
//     filesystem routes after rewriting to /<v>/foo/index.html.
//   - Anything else (path with a non-html file extension) -> immutable
//     assets cache. Safe because every asset path is pinned to /<version>/...
//     by the rewriter, so bytes never collide between versions even though
//     the original viewer-facing URL is stable across deploys.
//
// Why this runs in viewer-response, not viewer-request:
//   CloudFront selects the cache behavior — and therefore the static
//   response-headers policy — from the *original* viewer URI before any
//   viewer-request function runs. That makes a static `*.html` ordered
//   behavior unable to match SPA routes like `/dashboard` (no extension),
//   which is how ENG-4785 happened: the immutable assets policy attached to
//   the default behavior leaked onto every HTML response. Setting
//   Cache-Control in viewer-response sidesteps cache-behavior matching
//   entirely and keys off the rewritten URI shape, where the asset/HTML
//   distinction is unambiguous.
//
// Tokens substituted at apply time via templatefile():
//   ${html_cache_control}, ${asset_cache_control}, ${html_overrides_json}

var HTML_CACHE_CONTROL = '${html_cache_control}';
var ASSET_CACHE_CONTROL = '${asset_cache_control}';
var HTML_OVERRIDES = ${html_overrides_json};

function classify(uri) {
    // Strip the version prefix so HTML_OVERRIDES matches the original
    // viewer-facing path shape (e.g. '/service-worker.js'), not the
    // rewritten one (e.g. '/v_abc/service-worker.js').
    var withoutVersion = uri.replace(/^\/[^\/]+/, '') || '/';

    if (HTML_OVERRIDES.indexOf(withoutVersion) >= 0) {
        return HTML_CACHE_CONTROL;
    }

    if (withoutVersion.indexOf('/.') >= 0) {
        return HTML_CACHE_CONTROL;
    }

    var lastSlash = withoutVersion.lastIndexOf('/');
    var lastDot = withoutVersion.lastIndexOf('.');
    var hasExtension = lastDot > lastSlash;
    if (!hasExtension) {
        return HTML_CACHE_CONTROL;
    }

    var ext = withoutVersion.substring(lastDot).toLowerCase();
    if (ext === '.html' || ext === '.htm') {
        return HTML_CACHE_CONTROL;
    }

    return ASSET_CACHE_CONTROL;
}

function handler(event) {
    var response = event.response;
    var uri = (event.request && event.request.uri) || '/';

    response.headers['cache-control'] = { value: classify(uri) };
    return response;
}
