const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const template = fs.readFileSync(path.join(__dirname, 'viewer_request.js'), 'utf8');
const normalization = fs.readFileSync(
    path.join(__dirname, 'accept_header_normalization.js'),
    'utf8',
);

function makeHandler(rules, normalizeAccept = false) {
    const context = {};
    const code = template
        .replace('${redirect_rules_json}', JSON.stringify(rules))
        .replace(
            '${accept_header_normalization_code}',
            normalizeAccept ? normalization : '',
        );
    vm.runInNewContext(code, context);
    return context.handler;
}

function rule(overrides = {}) {
    return {
        source: 'https://docs.example.com/:path*',
        destination: 'https://www.example.com/docs/:path*',
        preserve_query_string: false,
        redirect_non_read_methods: false,
        status_code: 308,
        ...overrides,
    };
}

function request(host, uri, querystring = {}) {
    return {
        request: {
            headers: {host: {value: host}},
            method: 'GET',
            uri,
            querystring,
        },
    };
}

function requestWithAccept(accept, xMd) {
    const event = request('www.example.com', '/');
    event.request.headers.accept = {value: accept};
    if (xMd !== undefined) {
        event.request.headers['x-md'] = {value: xMd};
    }
    return event;
}

test('normalizes Accept into a Markdown cache-key header', () => {
    const cases = [
        ['text/markdown', '1'],
        ['text/markdown,text/html;q=0.9', '1'],
        ['text/markdown;q=0.1,text/markdown;q=0.9,text/html;q=0.5', '1'],
        ['text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', '0'],
        ['*/*', '0'],
        ['text/*;q=0.5, text/html;q=0.1', '1'],
        ['text/markdown;q=0, text/html;q=0.1', '0'],
        ['text/markdown;q=0.5, text/html;q=0.5', '0'],
        ['', '0'],
        ['not a media type', '0'],
    ];

    for (const [accept, expected] of cases) {
        const event = requestWithAccept(accept);
        makeHandler([], true)(event);
        assert.equal(event.request.headers['x-md'].value, expected, accept);
    }
});

test('overwrites a client-supplied x-md header', () => {
    const event = requestWithAccept(
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        '1',
    );
    makeHandler([], true)(event);
    assert.equal(event.request.headers['x-md'].value, '0');
});

test('redirects the source root to the destination prefix', () => {
    const result = makeHandler([rule()])(request('docs.example.com', '/'));

    assert.equal(result.statusCode, 308);
    assert.equal(result.statusDescription, 'Permanent Redirect');
    assert.equal(result.headers.location.value, 'https://www.example.com/docs');
});

test('captures multiple named path segments', () => {
    const result = makeHandler([
        rule({
            source: 'https://docs.example.com/:product/:version/:page',
            destination: 'https://www.example.com/docs/:version/:product/:page',
        }),
    ])(request('DOCS.EXAMPLE.COM', '/platform/v2/install'));

    assert.equal(
        result.headers.location.value,
        'https://www.example.com/docs/v2/platform/install',
    );
});

test('captures and relocates a nested catch-all path', () => {
    const result = makeHandler([
        rule({
            source: 'https://docs.example.com/:product/:version/:path*',
            destination: 'https://www.example.com/docs/:version/:product/:path*',
        }),
    ])(request('docs.example.com', '/platform/v2/guides/install'));

    assert.equal(
        result.headers.location.value,
        'https://www.example.com/docs/v2/platform/guides/install',
    );
});

test('normalizes captured segments without decoding path separators', () => {
    const result = makeHandler([rule()])(
        request('docs.example.com', '/caf%C3%A9/hello%20world'),
    );

    assert.equal(
        result.headers.location.value,
        'https://www.example.com/docs/caf%C3%A9/hello%20world',
    );
});

test('does not redirect unsafe encoded path segments', () => {
    const handler = makeHandler([rule()]);

    for (const uri of [
        '/%2e%2e/admin',
        '/safe/%2Fadmin',
        '/safe/%5Cadmin',
        '/safe/%00admin',
        '/safe/%invalid',
    ]) {
        const event = request('docs.example.com', uri);
        assert.equal(handler(event), event.request);
    }
});

test('matches equivalent encodings of literal source segments', () => {
    const result = makeHandler([
        rule({source: '/login', destination: '/new-login'}),
    ])(request('app.example.com', '/%6cogin'));

    assert.equal(result.headers.location.value, 'https://app.example.com/new-login');
});

test('does not emit unsafe literal destination segments', () => {
    const event = request('app.example.com', '/old');
    const result = makeHandler([
        rule({source: '/old', destination: '/safe/%2e%2e/admin'}),
    ])(event);

    assert.equal(result, event.request);
});

test('supports host-agnostic source and destination paths', () => {
    const result = makeHandler([
        rule({source: '/old/:path*', destination: '/new/:path*'}),
    ])(request('app.example.com', '/old/guide'));

    assert.equal(result.headers.location.value, 'https://app.example.com/new/guide');
});

test('requires exact segment counts without a catch-all', () => {
    const handler = makeHandler([
        rule({source: '/old/:page', destination: '/new/:page'}),
    ]);

    assert.equal(
        handler(request('app.example.com', '/old/guide')).headers.location.value,
        'https://app.example.com/new/guide',
    );
    assert.equal(handler(request('app.example.com', '/old/guide/child')).uri, '/old/guide/child');
});

test('preserves query parameters only when enabled', () => {
    const querystring = {
        source: {value: 'nav'},
        tag: {multiValue: [{value: 'one'}, {value: 'two'}]},
    };

    const discarded = makeHandler([rule()])(
        request('docs.example.com', '/quickstart', querystring),
    );
    assert.equal(discarded.headers.location.value, 'https://www.example.com/docs/quickstart');

    const preserved = makeHandler([rule({preserve_query_string: true})])(
        request('docs.example.com', '/quickstart', querystring),
    );
    assert.equal(
        preserved.headers.location.value,
        'https://www.example.com/docs/quickstart?source=nav&tag=one&tag=two',
    );
});

test('uses the first matching rule', () => {
    const result = makeHandler([
        rule({destination: 'https://first.example.com/:path*', status_code: 302}),
        rule({destination: 'https://second.example.com/:path*', status_code: 307}),
    ])(request('docs.example.com', '/guide'));

    assert.equal(result.statusCode, 302);
    assert.equal(result.headers.location.value, 'https://first.example.com/guide');
});

test('returns the request when no rule matches', () => {
    const event = request('app.example.com', '/guide');
    const result = makeHandler([rule()])(event);

    assert.equal(result, event.request);
});

test('does not redirect non-read methods without explicit opt-in', () => {
    const event = request('docs.example.com', '/submit');
    event.request.method = 'POST';

    assert.equal(makeHandler([rule()])(event), event.request);

    const result = makeHandler([rule({redirect_non_read_methods: true})])(event);
    assert.equal(result.statusCode, 308);
});

test('does not redirect into the same source pattern', () => {
    const event = request('www.example.com', '/docs/guide');
    const result = makeHandler([
        rule({
            source: 'https://www.example.com/docs/:path*',
            destination: 'https://www.example.com/docs/:path*',
        }),
    ])(event);

    assert.equal(result, event.request);
});

test('continues after a matching same-route rule would loop', () => {
    const event = request('www.example.com', '/guide');
    const result = makeHandler([
        rule({source: '/:path*', destination: '/:path*'}),
        rule({source: '/:path*', destination: 'https://other.example.com/:path*'}),
    ])(event);

    assert.equal(result.headers.location.value, 'https://other.example.com/guide');
});

test('continues after a destination cannot be expanded safely', () => {
    const event = request('www.example.com', '/guide');
    const result = makeHandler([
        rule({source: '/:path*', destination: '/safe/%2e%2e/:path*'}),
        rule({source: '/:path*', destination: 'https://other.example.com/:path*'}),
    ])(event);

    assert.equal(result.headers.location.value, 'https://other.example.com/guide');
});

test('supports all redirect status descriptions', () => {
    const descriptions = {
        301: 'Moved Permanently',
        302: 'Found',
        307: 'Temporary Redirect',
        308: 'Permanent Redirect',
    };

    for (const [statusCode, description] of Object.entries(descriptions)) {
        const result = makeHandler([rule({status_code: Number(statusCode)})])(
            request('docs.example.com', '/'),
        );
        assert.equal(result.statusDescription, description);
    }
});
