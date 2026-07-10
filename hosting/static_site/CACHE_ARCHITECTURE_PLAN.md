# A. Static hosting cache architecture plan

## 1. Status

This document records the target cache architecture for `hosting/static_site`, the two deployment cache modes it must support, the implementation currently present in the `modules2` and `flightcontrol4` working trees, and the remaining work required before release.

The `modules2` side now implements both Terraform cache modes, conditional Lambda@Edge, browser-safe Cache-Control defaults, and the expanded `aws:static` deploy contract. The corresponding `flightcontrol4` deployment schema and cleanup must land in parallel before the feature works end to end.

Decision: cache-header policy is not part of static build destinations or the generic build runner. In SWR mode, CDN cache-fill headers and `Content-Type` are applied at the edge by an origin-response Lambda@Edge trigger, so Ravion builds and externally uploaded `s3_directory` prefixes use the same contract without any deploy-time mutation of S3 objects. The earlier deploy-time S3 metadata-enforcement design (`EnsureStaticObjectMetadata` with self-copy) is superseded and its platform implementation must be removed.

## 2. Goals

The module must support two materially different cache consistency requirements independently from its routing behavior:

1. **Versioned delivery** is for any site that must not intentionally serve stale HTML after an edge observes a promotion. This includes SPAs and high-traffic public sites with strict freshness requirements.
2. **Stale-while-revalidate delivery** is for high-traffic public sites that prefer a continuously warm HTML cache and accept bounded, coherent stale responses during deployment convergence.

Both deployment cache modes should:

- Keep content-hashed assets cached in browsers across deployments when their public URL and bytes are unchanged.
- Preserve ETags for unchanged content where the upload mechanism supports stable ETags.
- Separate CDN caching policy from browser caching policy.
- Keep old deployment directories available for rollback and for any allowed stale response window.
- Avoid dependence on CloudFront invalidation for normal deployment freshness.
- Keep explicitly configured invalidations as an escape hatch instead of a default `/*` invalidation on every deployment.
- Work for platform builds and for pre-existing `s3_directory` deployments.
- Avoid Lambda@Edge unless the selected delivery semantics structurally require it.
- Return `404 Not Found` for missing objects while preserving genuine authorization failures as `403 AccessDenied`.

## 3. Non-goals

- Making mutable, unhashed assets safe to cache as `immutable`.
- Treating an ETag as a substitute for a stable cache key.
- Guaranteeing atomic cutover and a completely warm HTML cache at the same time without origin-request indirection.
- Deleting old deployment directories before every browser and CDN stale window has expired.

## 4. Confirmed current behavior

### 4.1. Deployment and storage

- A build is uploaded under a unique S3 directory.
- The CloudFront KeyValueStore contains the active directory.
- Deployment promotion changes the KVS `active` value.
- The viewer-request CloudFront Function prepends the active version to every request URI.
- Every deployment creates a `/*` CloudFront invalidation approximately three minutes after build upload.
- Previous deployment directories and hashed assets remain in S3 until retention cleanup applies.
- The current OAC policy grants `s3:GetObject` but not `s3:ListBucket`, so S3 returns `403 AccessDenied` for a missing key. The target behavior is a real viewer-facing `404 Not Found` for missing objects.

### 4.2. Current cache-key shape

The viewer requests a stable public URL, but the viewer-request function changes the URI before CloudFront cache lookup:

```text
Viewer URL:            /assets/app.abc123.js
Active version v1:     /v1/assets/app.abc123.js
Active version v2:     /v2/assets/app.abc123.js
```

CloudFront caches the rewritten URI. Therefore `/v1/...` and `/v2/...` are unrelated cache entries even if the object bytes and ETag are identical.

Consequences:

- A KVS flip makes new content visible without waiting for invalidation.
- The first request for every rewritten key in the new version is a cache miss.
- CDN `stale-while-revalidate` cannot bridge deployments because the new version asks for a new cache key with no stale entry.
- An ETag can make revalidation of an existing cache entry cheap, but it cannot connect two different cache keys.

### 4.3. Existing stale-browser failure

The current released HTML header is effectively browser-facing:

```text
s-maxage=5, stale-while-revalidate=31536000
```

The viewer-response function writes this header after CloudFront cache lookup, so it does not establish CDN SWR. It allows a browser to reuse stale HTML while revalidating in the background.

After promotion, stale HTML from `v1` requests an old hashed asset at its public URL. The viewer-request function rewrites that asset request into `v2`, not `v1`:

```text
Stale v1 HTML requests: /assets/chunk-old.js
Active KVS version:     v2
Rewritten request:      /v2/assets/chunk-old.js
Actual old object:      /v1/assets/chunk-old.js
Result:                 missing key -> 403 -> blank SPA
```

The old asset may still be cached and present in S3, but it is stored under a cache key and origin key the stale HTML can no longer address.

### 4.4. Missing-object status

Missing files must return `404`, not `403`. Grant the CloudFront service principal `s3:ListBucket` on the hosting bucket, constrained by the same `AWS:SourceArn` distribution condition as OAC object reads. S3 can then distinguish a nonexistent key from an authorization failure when CloudFront performs a signed origin request.

Do not map every CloudFront origin `403` to `404` with `custom_error_response`; that would hide genuine bucket-policy, KMS, or OAC authorization failures. The scoped `ListBucket` statement preserves real access failures as `403` while missing keys become `404`.

## 5. Important cache facts

### 5.1. `no-cache` does not mean `no-store`

`Cache-Control: no-cache` permits the browser to store HTML but requires validation before reuse. A browser normally sends `If-None-Match`; a fresh CloudFront edge entry can answer without contacting S3. The steady-state cost is a request to the nearest CloudFront POP, not an S3 request or write for every page load.

### 5.2. SWR and `no-cache` have similar request volume

Browser SWR also performs revalidation. Its distinction is timing:

- `no-cache`: validate before displaying the stored response.
- SWR: display the stored response first and validate in the background.

Browser SWR is only safe when stale HTML can still retrieve every asset it references.

### 5.3. ETags help only behind stable URLs and cache keys

For single-part S3 `PutObject` uploads without ETag-altering encryption or multipart behavior, identical bytes generally produce identical ETags. Stable ETags allow conditional requests to return `304` and avoid retransferring a body.

ETag stability must not be assumed for all upload mechanisms. Multipart uploads, encryption choices, metadata-replacement copies, or external tooling may change ETag behavior. Content hashes embedded in filenames remain the stronger identity for immutable assets.

### 5.4. New content must miss somewhere

New bytes cannot already be cached. The objective is not to eliminate misses for changed or newly introduced content. The objective is to prevent unchanged content from receiving new browser cache identities and, in stale-while-revalidate mode, new CDN cache identities on every deployment.

## 6. Target model shared by both deployment modes

### 6.1. Keep the existing cache-control inputs

The public module configuration should keep the existing cache-control fields:

- `html_cache_control`
- `assets_cache_control`
- `cache_control_enabled`
- `html_path_overrides`
- `no_cache_paths`

Do not add separate browser/CDN variants for every header. Four low-level fields make the module harder to understand and allow users to combine policies that are internally inconsistent. Documentation and examples should explain how the existing fields behave under each deployment cache mode.

`html_cache_control` and `assets_cache_control` remain the values emitted by the viewer-response CloudFront Function to browsers. Their defaults are selected for the deployment cache mode:

- `versioned`: HTML defaults to `no-cache`; assets default to `public, max-age=31536000, immutable`.
- `stale_while_revalidate`: public HTML may default to a bounded stale-first policy; assets remain immutable. Transactional or user-specific paths must be documented and configured as `no-cache`.

CloudFront still needs a cache-fill policy, but it should be an implementation detail derived from the deployment cache mode rather than another set of raw module inputs:

- `versioned`: version-specific HTML does not benefit from cross-deployment SWR, so the mode can use a safe module-managed CDN policy. No origin-response processing is required.
- `stale_while_revalidate`: CloudFront honors `stale-while-revalidate` and `stale-if-error` only when those directives appear in the `Cache-Control` header of the origin response at cache-fill time. Cache policies have no stale-serving settings, and response-headers policies and viewer-response functions modify viewer responses only. The mode therefore injects the module-managed short `s-maxage` and bounded SWR directives with an origin-response Lambda@Edge trigger (section 6.3).
- Immutable assets use the same long-lived immutable policy at the CDN and browser layers.

The module README and definition README must clearly distinguish what browsers receive from how CloudFront caches. Advanced users can replace `cache_policy_id` in versioned mode. SWR mode must use the module-managed Host-partitioned cache policy and internal-header origin request policy; callers cannot replace either policy because doing so could mix host pins or omit version forwarding.

### 6.2. Deployment invalidations

Invalidation must not remain on the critical path for deployment freshness:

- `versioned` mode defaults to no invalidation because the KVS flip creates the new HTML cache identity.
- `stale_while_revalidate` mode defaults to no invalidation because invalidation would replace controlled convergence with cache misses.
- Explicit invalidation paths remain an advanced escape hatch.

### 6.3. Edge header injection independent of upload path

Cache headers must not depend on Ravion performing the build or upload. A deployment may promote a prefix produced by any external tool, so the header contract must be applied somewhere the upload path cannot influence.

The rejected approaches:

- **Build-time headers** (`cache_control_rules` in the uploader) were removed: they cannot cover external `s3_directory` prefixes and put cache policy into generic build tooling.
- **Deploy-time S3 metadata enforcement** (`EnsureStaticObjectMetadata` self-copying every object with `MetadataDirective: REPLACE`) worked but carried heavy costs: a list-and-copy pass over every object before each promotion, write access to customer prefixes, ETag churn from metadata-replacement copies, large-object `CopyObject` handling, idempotency and retry machinery, an ordered metadata-rules field in the `aws:static` contract, and a fail-closed SSE-KMS restriction because the self-copy is a write requiring exact-key KMS permissions.

The selected approach: in SWR mode, the origin-facing Lambda@Edge function is associated with both the `origin-request` and `origin-response` triggers. The `origin-response` trigger sets the response headers before CloudFront caches the object:

- Apply the module-derived `Cache-Control` cache-fill policy (`s-maxage`, `stale-while-revalidate`, `stale-if-error`) per path class.
- Repair missing or incorrect `Content-Type` from an extension map so cache fill and CloudFront compression decisions see the correct type.
- Apply identical logic to `200` and `304` origin responses; CloudFront refreshes cached headers from revalidation responses, so a `304` that skipped header injection would strip the SWR contract from the cached entry.
- Never modify the body; the function is header-only.

Properties:

- One function, one IAM role, one us-east-1 publication pipeline; the two triggers branch on the event type.
- Runs only on cache miss and revalidation, the same frequency as the origin-request trigger the mode already requires.
- The deployment workflow never writes to customer objects; deploys are read-only with respect to S3 content.
- Works identically for platform builds and external `s3_directory` prefixes, including SSE-KMS buckets, because reads flow through the existing OAC path.
- Header configuration is templated into the function source by Terraform (Lambda@Edge has no environment variables), so header changes are stack updates followed by natural revalidation, not deploy-time data.
- Existing cached entries keep their previous headers until they revalidate; with the mode's short `s-maxage`, convergence is fast.

Versioned mode intentionally does not get this function (section 7.5). Its CDN policy comes from the cache policy and its browser policy from the viewer-response function, neither of which needs origin headers. Consequence: external uploads with missing `Content-Type` are not repaired at cache fill in versioned mode, so CloudFront may skip compression for those objects. This is the pre-existing behavior and must be documented; the viewer-response function may patch `Content-Type` for browsers if needed.

Build uploaders stay generic and do not accept cache-header rules under any mode.

## 7. Versioned delivery mode

### 7.1. Goal

- Support both `spa` and `filesystem` routing.
- One coherent build is active at a time for each KVS routing key.
- KVS promotion and rollback remain the commit mechanism.
- A browser never displays stale HTML that resolves assets from the wrong build.
- Unchanged content-hashed assets remain cached in browsers across deployments because their public URLs are stable.
- One miss per requested object and relevant CloudFront cache after promotion is acceptable.
- After an edge observes the KVS promotion, it must not intentionally serve HTML from the previous version.

### 7.2. Target request routing

```text
HTML or route request:
  /dashboard
  -> viewer-request reads KVS active=v2
  -> SPA routing: /v2/index.html
  -> filesystem routing: /v2/dashboard/index.html
  -> version-specific CloudFront cache key

Asset request:
  /assets/app.abc123.js
  -> viewer-request reads KVS active=v2
  -> /v2/assets/app.abc123.js
  -> version-specific CloudFront cache key
```

### 7.3. Recommended policies

```text
HTML browser: no-cache
HTML CDN:     long cache policy is safe because the version is in the key;
              a shorter TTL may be retained for operational consistency
Assets:       public, max-age=31536000, immutable at CDN and browser
```

CDN SWR on HTML has little deployment benefit in this mode because every KVS flip creates a new HTML key. It may still help within one version after TTL expiry, but it does not prevent the post-promotion HTML miss.

### 7.4. Expected behavior

- KVS promotion makes the new HTML key active within KVS propagation time.
- The first viewer for each requested object and relevant cache fetches it from S3 under the new version key.
- Assets unchanged from prior deployments remain warm in browsers because their public URLs are stable and immutable; the CDN refills version-specific asset keys on first request.
- Browser `no-cache` validates HTML before reuse and receives the current build on one refresh.
- Rollback flips KVS to the previous version; previous HTML and assets remain available in their retained version directory.
- KVS propagation is distributed rather than globally instantaneous. An edge that has not observed the new KVS value can still resolve the prior version for a short period. Here, "never stale" means that once an edge observes the promotion it never intentionally serves the previous HTML version.

### 7.5. Lambda requirement

No Lambda@Edge is required for this mode.

## 8. Stale-while-revalidate delivery mode

### 8.1. Goal

- Deployments do not replace CloudFront cache identities for unchanged HTML or assets.
- A viewer never blocks on origin merely because a deployment occurred.
- CloudFront may serve a coherent stale page immediately and revalidate in the background.
- Identical content can revalidate with `304` where ETags are stable.
- Frequent deployments do not repeatedly cold-start the long tail of HTML pages.

This mode trades atomic all-page cutover for warm-cache, per-page convergence over the HTML freshness window. It is appropriate only when bounded stale content is acceptable.

### 8.2. Required property

The viewer-facing URI must remain the CloudFront cache key across deployments. The active version may not be inserted into that key.

### 8.3. Stable cache key with origin-request version resolution

This preserves immutable version directories, KVS promotion, and rollback while moving version selection behind CloudFront cache lookup.

Request flow:

```text
Viewer request /products/widget
-> viewer-request CloudFront Function reads KVS active=v2
-> URI remains /products/widget (stable cache key)
-> function passes active version in a request header
-> cache hit: CloudFront serves cached response immediately
-> miss/revalidation: origin-request Lambda@Edge trigger rewrites origin URI to
   /v2/products/widget/index.html
-> S3 returns 304 for identical content or 200 for changed content
-> origin-response Lambda@Edge trigger (same function) injects the CDN
   Cache-Control policy and repairs Content-Type before CloudFront caches
```

Properties:

- HTML SWR works across deployments because the cache key stays stable.
- Cache hits do not invoke Lambda@Edge.
- Lambda@Edge runs on cache miss or revalidation only, for both triggers.
- A KVS flip does not trigger a cache-miss wave.
- Changed pages converge after `s-maxage` plus background revalidation.
- Unchanged pages can revalidate cheaply when their ETag is stable.
- Versioned origin directories and KVS rollback remain available.
- The CDN SWR contract lives in the origin-response trigger (section 6.3), not in S3 object metadata, so deploys never mutate objects.

Stale-asset exposure: a stale HTML response may reference hashed assets from the build that produced it. An old asset that is still cached at the edge under its stable public URL continues to be served, but a cache miss or revalidation resolves against the active version, and an asset name that no longer exists there returns `404`. The bounded SWR window limits this exposure but does not eliminate it. Documentation must state this boundary, and correctness-critical routes must use `no-cache`.

Operational costs:

- Lambda@Edge must be published in `us-east-1` and associated by versioned ARN.
- The module gains IAM, replication, update, and deletion complexity.
- Function changes deploy more slowly than CloudFront Function changes, and header configuration is baked into the function source, so cache-header changes require a function publish and distribution update.
- Header propagation, cache-key exclusion, and `304` header reapplication must be tested explicitly.
- SWR cache keys include viewer `Host`, so host-specific KVS pins and aliases cannot share stable HTML entries. `X-Ravion-Version` remains excluded from the cache key and is forwarded only by the origin request policy.

Lambda@Edge is structurally required for this exact combination: stable viewer cache key, versioned S3 directories, KVS pointer-based origin selection, and origin-response Cache-Control injection at cache fill.

### 8.4. Recommended policies

For cacheable public HTML:

```text
HTML CDN:     public, s-maxage=5, stale-while-revalidate=<bounded window>,
              stale-if-error=<bounded window>
HTML browser: configurable:
              - no-cache for correctness-first pages such as checkout/account
              - max-age=0, stale-while-revalidate=<short bounded window>
                for stale-first public content
Assets:       public, max-age=31536000, immutable
```

The one-year browser SWR window should not remain the default. Browser SWR duration must be bounded by how long referenced assets are guaranteed to remain reachable and by how stale business content is allowed to become. Commerce pricing, inventory, authentication, checkout, and account routes should normally use `no-cache` even when public editorial pages use stale-first caching.

### 8.5. Lambda requirement

Lambda@Edge is required for this mode for two reasons: KVS version selection must occur behind a stable CloudFront cache key (origin-request), and the SWR cache-fill directives must appear on the origin response (origin-response). This is an architectural toggle, not merely a different `Cache-Control` value.

## 9. Suggested module-level product model

Avoid representing this only as independent low-level cache strings. Users need to choose a consistency model.

Conceptual configuration:

```yaml
routing: spa | filesystem
deployment_cache_mode: versioned | stale_while_revalidate
html_cache_control: null
assets_cache_control: null
```

Suggested defaults:

| Setting             | `versioned`                                        | `stale_while_revalidate`                                  |
| ------------------- | -------------------------------------------------- | --------------------------------------------------------- |
| HTML cache key      | Version-specific                                   | Stable                                                    |
| Promotion           | KVS pointer flip                                   | KVS + origin-request resolution                           |
| HTML browser policy | `no-cache`                                         | Bounded SWR for public pages; per-path overrides required |
| HTML CDN policy     | Does not bridge deploys                            | Short `s-maxage` + bounded SWR                            |
| Asset cache keys    | Version-specific at CDN; stable public browser URL | Stable                                                    |
| Atomic cutover      | Yes                                                | No; per-page convergence                                  |
| Lambda@Edge         | No                                                 | Yes; one function on origin-request and origin-response, cache miss/revalidation only |
| CDN header source   | Cache policy TTLs                                  | Origin-response header injection                          |

The existing header overrides remain useful, but documentation must warn against unsafe combinations. Browser SWR documentation must state the stale-asset exposure boundary and keep transactional routes on `no-cache`.

## 10. Current implementation in `flightcontrol4`

The rejected build-uploader `cache_control_rules` implementation has been removed. Static build destinations and the runner remain generic and do not own cache policy.

The current platform implementation includes:

- `aws:static` TypeSpec, generated schemas, resolver, stored deployment snapshots, rollback, and workflow propagation for deployment cache mode, deploy-time metadata, retention, and KMS context.
- Legacy compatibility: definitions omitting the new contract retain the old deploy behavior without metadata mutation.
- Pre-commit HTML metadata repair for arbitrary platform or external S3 prefixes.
- Source compare-and-swap guards so metadata races fail before KVS promotion.
- Safe version pruning based only on known old successful deployments; unknown or pending uploaded prefixes are no longer candidates.
- Correct CopyObject IAM extraction as `s3:GetObject` plus `s3:PutObject`; generated policies contain no nonexistent `s3:CopyObject` action.
- Fail-closed rejection of SSE-KMS metadata enforcement until a dedicated exact-key deployment role exists.
- Focused schema, resolver, AWS adapter, Temporal workflow/activity, database, API handler, credentials-broker, and IAM tests.

The deploy-time metadata-enforcement portion of this implementation is superseded by origin-response header injection (section 6.3) and must be removed in phase 2: the ordered metadata-rules contract fields, the `EnsureStaticObjectMetadata` activity and its workflow step, the metadata compare-and-swap guards, the self-copy IAM extraction, and the SSE-KMS fail-closed restriction (which existed only because the self-copy is a write). The `deployment_cache_mode` field, snapshot persistence, retention, invalidation-behavior changes, legacy compatibility, and safe version pruning remain.

Untracked research files already present in `flightcontrol4`, including `docs/research/` and `schema-format-research.md`, remain unrelated and untouched.

## 11. Remaining implementation plan

### 11.1. Phase 1: fix the browser correctness bug (modules2 complete)

1. Restore the known tracked `flightcontrol4` build-uploader WIP files to `HEAD`, delete only the two cache-control fixtures noted in section 10, and preserve unrelated untracked research files.
2. Remove `cache_control_rules` and `html_cdn_cache_control` from the module definition and remove all build-time metadata claims.
3. Retain the viewer-response function.
4. Make versioned-mode HTML browser policy `no-cache` by default for both SPA and filesystem routing.
5. Keep stable mutable root files in `html_path_overrides`.
6. Correct documentation so it does not claim CDN SWR bridges KVS versions.
7. Add or reserve `deployment_cache_mode = "versioned"` as the safe default independently from `routing`.
8. Grant the OAC principal scoped `s3:ListBucket` so missing origin keys return `404` without masking genuine `403` authorization failures.

Exit criteria:

- A browser with cached old HTML cannot produce a blank page after promotion.
- One refresh after KVS propagation returns the current HTML.
- Tests distinguish browser-facing headers from CDN cache-fill policy.
- Missing objects return `404`; intentionally denied objects continue returning `403`.

### 11.2. Phase 2: replace deploy-time metadata enforcement with origin-response header injection

1. Remove the deploy-time metadata machinery from `flightcontrol4`: the ordered metadata-rules fields in the `aws:static` contract, the `EnsureStaticObjectMetadata` activity and its workflow step, the metadata compare-and-swap guards, the self-copy IAM extraction, and the SSE-KMS fail-closed restriction. Keep `deployment_cache_mode`, snapshot persistence, retention, and legacy compatibility.
2. Keep static build destinations and the runner free of cache-header configuration.
3. In `modules2`, associate the SWR-mode Lambda@Edge function with the `origin-response` trigger in addition to `origin-request`, branching on the event type.
4. Template the module-derived cache-fill header rules and `Content-Type` extension map into the function source (Lambda@Edge has no environment variables).
5. Apply identical header logic to `200` and `304` origin responses so revalidation never strips the SWR contract from a cached entry.
6. Keep the function header-only; never generate or modify bodies.
7. Document the versioned-mode carve-out: no origin-response processing, so external uploads with missing `Content-Type` are not repaired at cache fill and may skip CloudFront compression.
8. Update the module README and definition README so the header layering table shows origin-response as the CDN header source in SWR mode.

Exit criteria:

- Platform builds and arbitrary pre-existing prefixes, including SSE-KMS buckets, receive the same CDN header contract at cache fill without any deploy-time object mutation.
- Deploys are read-only with respect to S3 objects; the deployment role needs no object-write permissions for header purposes.
- A `304` revalidation preserves the injected `Cache-Control` on the cached entry.
- Objects with missing or wrong `Content-Type` are cached and compressed correctly in SWR mode.

### 11.3. Phase 3: introduce stale-while-revalidate delivery (origin-request implementation complete; origin-response injection and real CloudFront integration pending)

1. Add `deployment_cache_mode = "stale_while_revalidate"` independently from `routing`.
2. Change viewer-request behavior to preserve stable HTML URIs.
3. Pass active version and host-routing context to origin-request without adding it to the cache key.
4. Add the Lambda@Edge function with origin-request and origin-response triggers and least-privilege IAM (origin-response work is detailed in phase 2).
5. Define cache partitioning for aliases, previews, and host-specific KVS pins.
6. Verify SWR background revalidation uses the current KVS version.
7. Add per-path browser policy guidance so transactional routes remain `no-cache` while eligible public content may use bounded SWR through the existing `html_cache_control` field.
8. Document the stale-asset exposure boundary from section 8.3, including the retention window that keeps old version directories available.

Exit criteria:

- Deploying an unchanged large site does not replace its HTML CloudFront cache identities.
- A viewer receives a cached response immediately during deployment convergence.
- Changed HTML appears after the configured freshness/SWR process without waiting for invalidation.
- Unchanged HTML revalidates with `304` when ETag behavior permits.
- Rollback semantics are documented and tested.

### 11.4. Phase 4: cleanup and release

1. Reconcile all WIP code with the selected architecture.
2. Remove or rewrite claims that no longer match runtime behavior.
3. Reassess the `0.3.0` release version and description based on the final user-visible change set.
4. Run module formatting, validation, and tests.
5. Run schema generation and tests in `flightcontrol4`.
6. Run runner, shared-go, tower-go, and targeted Temporal workflow tests.
7. Publish a local development module definition only after platform schema/runtime support is available.
8. Validate with a real distribution using both deployment cache modes and both routing modes before publishing a release.

## 12. Validation plan

### 12.1. Functional scenarios

- SPA deployment with a browser holding old HTML.
- SPA deployment where an old hashed chunk no longer exists in the new build.
- Filesystem site with thousands of HTML pages and a small changed subset.
- Identical asset bytes and filenames across multiple deployments.
- Changed asset bytes with a new content hash.
- External `s3_directory` upload without Cache-Control metadata.
- External upload with pre-existing Cache-Control metadata (origin-response injection must win in SWR mode).
- External upload with missing or wrong `Content-Type` in both modes.
- SWR-mode `304` revalidation preserves the injected `Cache-Control` and SWR directives on the cached entry.
- SWR-mode compression applies to objects whose `Content-Type` was repaired at origin-response.
- Cache-header configuration change propagates via function publish plus natural revalidation.
- Service worker update.
- Host-specific KVS pin and preview hostname.
- Rollback during and after cache convergence.
- CloudFront invalidation delayed or failed.
- Missing objects return `404` through CloudFront.
- A genuine OAC, bucket-policy, or KMS denial remains `403` rather than being remapped.

### 12.2. Header and cache assertions

For each deployment cache mode, capture:

- Viewer request URI.
- Rewritten URI or origin URI.
- CloudFront cache status (`Miss`, `Hit`, `RefreshHit`).
- `Age`.
- Browser-facing `Cache-Control`.
- Origin response `Cache-Control` as cached (after origin-response injection in SWR mode).
- ETag before and after identical-content deployment.
- S3 request count and bytes transferred.
- First-byte latency for the first and subsequent requests after promotion.

### 12.3. Success metrics

- Zero stale-shell asset failures.
- Versioned-mode post-promotion misses limited to the first request per object under the new version key.
- SWR-mode deployments show no deployment-correlated HTML miss wave.
- Deploys perform no S3 object writes; object ETags are unchanged by deployment.
- Invalidations are no longer on the critical path for freshness.
