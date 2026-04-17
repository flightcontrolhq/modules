// CloudFront Function (cloudfront-js-2.0) - filesystem_previews mode.
//
// Resolves the active deployment prefix at the edge so the Lambda@Edge handler
// (origin-request) can read the right folder from S3 without an extra round trip.
//
// Strategy:
//   1. If the request Host is in the KeyValueStore, treat its value as the active
//      deployment prefix (e.g. "fc-versions/pr-42") and rewrite the URI so the
//      Lambda@Edge handler can resolve it relative to that prefix.
//   2. Otherwise, fall back to the default deployment prefix injected at apply
//      time (var.deployment_id_header_value -> "fc-main", "main", etc.).
//
// The ${kvs_id} and ${default_prefix} tokens are substituted at apply time via
// templatefile(). When KVS is disabled, ${kvs_id} is rendered as an empty string
// and the lookup is skipped.

import cf from 'cloudfront';

var KVS_ID = '${kvs_id}';
var DEFAULT_PREFIX = '${default_prefix}';
var kvs = KVS_ID ? cf.kvs(KVS_ID) : null;

async function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var host = (headers.host && headers.host.value) || '';

    var prefix = DEFAULT_PREFIX;

    if (kvs && host) {
        try {
            var lookup = await kvs.get(host);
            if (lookup) {
                prefix = lookup;
            }
        } catch (e) {
            // KVS miss: fall through to DEFAULT_PREFIX. The handler tolerates
            // this and serves the main deployment.
        }
    }

    headers['x-fc-deployment-id'] = { value: prefix };
    return request;
}
