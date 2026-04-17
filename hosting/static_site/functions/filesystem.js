// CloudFront Function (cloudfront-js-2.0) - filesystem mode.
//
// Rewrites clean URLs to the underlying object key on S3:
//   /              -> /${index_document}
//   /foo/          -> /foo/${index_document}
//   /foo           -> /foo/${index_document}    (only when there is no extension)
//
// Files with an extension (foo.css, robots.txt, sitemap.xml) pass through unchanged.
// CloudFront Functions are limited to viewer-request and run synchronously at every
// edge POP, so this is much cheaper than Lambda@Edge for the common static-site case.
//
// The ${index_document} token is substituted at apply time via templatefile().

function handler(event) {
    var request = event.request;
    var uri = request.uri;

    var lastSlash = uri.lastIndexOf('/');
    var lastDot = uri.lastIndexOf('.');
    var hasExtension = lastDot > lastSlash;

    if (uri.endsWith('/')) {
        request.uri = uri + '${index_document}';
    } else if (!hasExtension) {
        request.uri = uri + '/${index_document}';
    }

    return request;
}
