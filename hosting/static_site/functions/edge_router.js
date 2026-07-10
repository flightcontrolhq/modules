'use strict';

var INDEX_DOCUMENT = '${index_document}';
var ROUTING = '${routing}';
var HTML_OVERRIDES = ${html_overrides_json};
var NO_CACHE_PATHS = ${no_cache_paths_json};
var HTML_CACHE_CONTROL = '${html_cdn_cache_control}';
var ASSET_CACHE_CONTROL = '${assets_cdn_cache_control}';
var CONTENT_TYPES = ${content_types_json};

function hasExtension(uri) {
    return uri.lastIndexOf('.') > uri.lastIndexOf('/');
}

function isHtml(uri) {
    if (HTML_OVERRIDES.indexOf(uri) >= 0 || uri.indexOf('/.') >= 0 || !hasExtension(uri)) {
        return true;
    }
    var extension = uri.substring(uri.lastIndexOf('.')).toLowerCase();
    return extension === '.html' || extension === '.htm';
}

function matchesPattern(uri, pattern) {
    var escaped = pattern.replace(/[.+?^$()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
    return new RegExp('^' + escaped + '$').test(uri);
}

function isNoCache(uri) {
    return NO_CACHE_PATHS.some(function (pattern) { return matchesPattern(uri, pattern); });
}

function originUri(uri, version) {
    if (uri === '/') {
        return '/' + version + '/' + INDEX_DOCUMENT;
    }
    if (hasExtension(uri) || uri.indexOf('/.') >= 0) {
        return '/' + version + uri;
    }
    if (ROUTING === 'spa') {
        return '/' + version + '/' + INDEX_DOCUMENT;
    }
    var trimmed = uri.charAt(uri.length - 1) === '/' ? uri.slice(0, -1) : uri;
    return '/' + version + trimmed + '/' + INDEX_DOCUMENT;
}

function setHeader(headers, name, value) {
    headers[name] = [{ key: name.split('-').map(function (part) {
        return part.charAt(0).toUpperCase() + part.slice(1);
    }).join('-'), value: value }];
}

exports.handler = function (event, context, callback) {
    var record = event.Records[0].cf;
    var request = record.request;

    if (record.config.eventType === 'origin-request') {
        var versionHeader = request.headers['x-ravion-version'];
        if (!versionHeader || !versionHeader[0] || !versionHeader[0].value) {
            return callback(new Error('Missing X-Ravion-Version header'));
        }
        request.headers['x-ravion-viewer-uri'] = [{ key: 'X-Ravion-Viewer-Uri', value: request.uri || '/' }];
        request.uri = originUri(request.uri || '/', versionHeader[0].value);
        return callback(null, request);
    }

    var response = record.response;
    if (response.status !== '200' && response.status !== '304') {
        return callback(null, response);
    }

    var viewerUriHeader = request.headers['x-ravion-viewer-uri'];
    var viewerUri = viewerUriHeader && viewerUriHeader[0] ? viewerUriHeader[0].value : (request.uri || '/');
    var cacheControl = isNoCache(viewerUri)
        ? 'no-store, no-cache, must-revalidate'
        : (isHtml(viewerUri) ? HTML_CACHE_CONTROL : ASSET_CACHE_CONTROL);
    setHeader(response.headers, 'cache-control', cacheControl);

    var extension = hasExtension(viewerUri) ? viewerUri.substring(viewerUri.lastIndexOf('.')).toLowerCase() : '.html';
    if (CONTENT_TYPES[extension]) {
        setHeader(response.headers, 'content-type', CONTENT_TYPES[extension]);
    }

    return callback(null, response);
};
