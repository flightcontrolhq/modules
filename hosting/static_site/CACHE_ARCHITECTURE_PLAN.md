# A. Static hosting cache architecture plan

## 1. Status

This document records the target cache architecture for `hosting/static_site`, the two deployment cache modes it must support, the implementation currently present in the `modules2` and `flightcontrol4` working trees, and the remaining work required before release.

The `modules2` side now implements both Terraform cache modes, shared-asset viewer routing, conservative classification, conditional origin-request Lambda@Edge, browser-safe Cache-Control defaults, and the expanded `aws:static` deploy contract. The corresponding `flightcontrol4` deployment schema, publication, metadata enforcement, manifests, and cleanup must land in parallel before the feature works end to end.

Decision: cache-header policy is not part of static build destinations or the generic build runner. Module-managed S3 metadata enforcement happens during `aws:static` deployment so Ravion builds and externally uploaded `s3_directory` prefixes use the same contract.

## 2. Goals

The module must support two materially different cache consistency requirements independently from its routing behavior:

1. **Versioned delivery** is for any site that must not intentionally serve stale HTML after an edge observes a promotion. This includes SPAs and high-traffic public sites with strict freshness requirements.
2. **Stale-while-revalidate delivery** is for high-traffic public sites that prefer a continuously warm HTML cache and accept bounded, coherent stale responses during deployment convergence.

Both deployment cache modes should:

- Keep content-hashed assets cached across deployments when their URL and bytes are unchanged.
- Preserve ETags for unchanged content where the upload mechanism supports stable ETags.
- Separate CDN caching policy from browser caching policy.
- Keep old deployment directories available for rollback and for any allowed stale response window.
- Avoid dependence on CloudFront invalidation for normal deployment freshness.
- Keep explicitly configured invalidations as an escape hatch, but do not issue a default `/*` invalidation when shared assets are enabled.
- Work for platform builds and for pre-existing `s3_directory` deployments.
- Avoid Lambda@Edge unless the selected delivery semantics structurally require it.
- Return `404 Not Found` for missing objects while preserving genuine authorization failures as `403 AccessDenied`.

## 3. Non-goals

- Making mutable, unhashed assets safe to cache as `immutable`.
- Treating an ETag as a substitute for a stable cache key.
- Guaranteeing atomic cutover and a completely warm HTML cache at the same time without origin-request indirection.
- Deleting old assets before every browser and CDN stale window has expired.

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

New bytes cannot already be cached. The objective is not to eliminate misses for changed or newly introduced content. The objective is to prevent unchanged HTML and assets from receiving new cache identities on every deployment.

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

- `versioned`: version-specific HTML does not benefit from cross-deployment SWR, so the mode can use a safe module-managed CDN policy.
- `stale_while_revalidate`: stable HTML cache keys receive the module-managed short `s-maxage` and bounded SWR policy required by that mode.
- Immutable assets use the same long-lived immutable policy at the CDN and browser layers.

The module README and definition README must clearly distinguish what browsers receive from how CloudFront caches. Advanced users can replace `cache_policy_id` in versioned mode. SWR mode must use the module-managed Host-partitioned cache policy and internal-header origin request policy; callers cannot replace either policy because doing so could mix host pins or omit version forwarding.

### 6.2. Shared content-addressed asset namespace

Immutable assets must not receive a deployment-version prefix in the CloudFront cache key. Their public URL and shared origin key should be stable across deployments. The deployment keeps the complete version directory and additionally publishes classified immutable assets under a reserved internal namespace:

```text
Public URL:       /assets/app.abc123.js
Version key:      v_abc123/assets/app.abc123.js
Shared S3 key:    __ravion/assets/assets/app.abc123.js
CloudFront key:   /__ravion/assets/assets/app.abc123.js
```

Required properties:

- The key is content-addressed or otherwise guaranteed immutable.
- An unchanged asset keeps the same public URL, CloudFront key, browser key, and S3 key.
- Deployment skips the shared copy when the object already exists with the expected identity.
- New assets are uploaded before any HTML that references them becomes active.
- Old assets remain available for at least the maximum browser/CDN stale window plus rollback retention.
- The viewer-request function maps classified public asset paths to the reserved shared prefix without a KVS version prefix.
- Stable but mutable files such as service workers, manifests, robots files, sitemaps, and unhashed images are excluded from the immutable namespace.
- `__ravion/` is reserved, rejected as a deployment version, and excluded from normal version-directory pruning.

### 6.3. Shared asset configuration and framework defaults

The public configuration should use three grouped fields:

```yaml
shared_assets_enabled: true
shared_assets_path_patterns:
  - "/_next/static/**"
  - "/_astro/**"
  - "/_nuxt/**"
  - "/_app/immutable/**"
  - "/static/js/**"
  - "/static/css/**"
  - "/static/media/**"
shared_assets_hash_detection_enabled: true
```

Semantics:

- `shared_assets_enabled = false` disables shared publication, manifest creation, shared routing, and shared-asset cleanup.
- `shared_assets_path_patterns` has an internally maintained default list. A caller-supplied list replaces that list completely; there are no separate additional or exclusion inputs.
- `shared_assets_path_patterns = []` disables path-based classification while leaving optional hash detection active.
- `shared_assets_hash_detection_enabled` independently controls conservative filename-hash detection.
- Both path patterns and hash detection classify individual public paths. Neither changes the existing cache-control input surface.

The internal path list must contain only framework-owned namespaces documented or fixture-tested as immutable. Initial research matrix:

| Framework/tool                 | Immutable output convention                                                                                                                      | Default handling                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| Next.js static assets          | `/_next/static/**`; Next.js documents this separately from mutable `public/` files                                                               | Default path pattern                                             |
| Astro                          | `/_astro/**` by default; `build.assets` can customize the directory while `public/` files are copied separately                                  | Default path pattern; document override when customized          |
| Nuxt                           | `/_nuxt/**` generated client assets                                                                                                              | Default path pattern after current-version fixture verification  |
| SvelteKit                      | `/_app/immutable/**` generated immutable application assets                                                                                      | Default path pattern after current-version fixture verification  |
| Create React App               | `/static/js/**`, `/static/css/**`, and `/static/media/**` generated build assets                                                                 | Default path patterns after fixture verification                 |
| Vite                           | Generated assets default to `/assets/**`, but `publicDir` is copied as-is and can also contain mutable `/assets/` files                          | Hash detection; do not default all `/assets/**`                  |
| TanStack Start with Vite       | Official examples show client assets such as `/assets/index-a1b2c3d4.js`; output is Vite-based and does not have a uniquely safe TanStack prefix | Hash detection; users may override paths for a controlled output |
| TanStack Start with Rsbuild    | Client output is under `dist/client`, but public URL layout depends on Rsbuild configuration                                                     | Hash detection plus fixture research; no broad default yet       |
| Angular                        | Production bundles commonly use hashed names at the output root; hashing can be configured                                                       | Hash detection                                                   |
| Gatsby                         | Generated bundles span several paths and do not provide one universally safe public prefix                                                       | Hash detection plus fixture research                             |
| React Router/Remix with Vite   | Uses Vite-style generated assets and configurable output                                                                                         | Hash detection                                                   |
| Docusaurus                     | Webpack-generated JS/CSS is hashed, while static content may share nearby directories                                                            | Hash detection until fixture research proves safe prefixes       |
| Hugo, Jekyll, MkDocs, Eleventy | No universal content-hashing guarantee                                                                                                           | No internal path default; user override only                     |

Before freezing or expanding defaults, CI should build minimal current-version fixtures twice for each supported framework and assert:

- Unchanged generated assets keep the same public names.
- Files under each default pattern are content-addressed or otherwise immutable.
- Mutable public/static files cannot enter the default namespace.
- Configuration that changes the framework asset directory is documented.
- A framework upgrade that changes these properties fails the fixture test rather than silently weakening the invariant.

### 6.4. Conservative hash detection

Hash detection is useful for Vite, TanStack Start, Angular, Gatsby, and other tools that emit hashed assets without a uniquely safe directory. It can be enabled, but it must be conservative because falsely declaring a mutable URL immutable can leave browsers on old bytes for a year.

The Go deployment activity and viewer-request JavaScript must implement the same deterministic predicate. Candidate rules:

- Match only the basename, not hash-looking parent directories.
- Require the candidate token immediately before the extension and separated from the logical name by `.` or `-`.
- Accept bounded hexadecimal tokens of 8-64 characters only when they contain both a digit and a hexadecimal letter.
- Accept bounded base64url-style tokens of 8-64 characters only when they contain lowercase, uppercase, and numeric characters.
- Restrict detection to an allowlist of static asset extensions.
- Never detect HTML, service workers, web manifests, robots files, sitemaps, or other known mutable metadata as immutable.
- Normalize URI escaping and case identically in Go and CloudFront JavaScript.
- Maintain shared table-driven fixtures so every accepted/rejected path produces the same result in both implementations.

Examples expected to match:

```text
/assets/index-BUKi6k3H.js
/assets/app.8f12ab34.js
/static/css/main.91cd23ef.css
```

Examples expected not to match:

```text
/assets/app.js
/images/product-20260710.jpg
/manifest.webmanifest
/service-worker.js
```

If a detected shared key already exists with different content identity, deployment fails before KVS promotion. The error tells the user to disable hash detection, override `shared_assets_path_patterns`, or emit a genuinely content-hashed name. Since there is intentionally no per-path exclusion input, disabling hash detection is the escape hatch for a false-positive filename; path-based defaults remain independently overridable.

### 6.5. Deploy-time shared asset publication

Shared publication runs entirely during `aws:static` deployment so it works for Ravion builds and arbitrary pre-existing `s3_directory` prefixes:

```text
EnsureStaticDirectoryExists
-> EnsureStaticObjectMetadata, when required
-> PublishStaticSharedAssets
-> WriteStaticAssetManifest
-> PromoteStaticDirectory
-> background cleanup
```

`PublishStaticSharedAssets` should:

1. List the candidate version directory.
2. Classify each relative public path using the effective path patterns and hash-detection setting.
3. Map each candidate to `__ravion/assets/<original-relative-path>`.
4. `HeadObject` the shared destination.
5. Skip it when checksum identity, or ETag plus size as a fallback, matches.
6. Fail the deployment on an identity mismatch because an immutable public URL has collided.
7. Use server-side `CopyObject` for missing assets with bounded concurrency.
8. Preserve required content metadata and apply the existing `assets_cache_control` value where object metadata is needed.
9. Write `__ravion/manifests/<version>.json` only after every shared asset is available.
10. Complete before KVS promotion so HTML can never become active before its shared assets.

The manifest records the version, creation time, source key, shared key, size, ETag, and available checksum for each classified asset. A failed deployment may leave harmless unreferenced shared objects; later garbage collection removes them after the grace period.

### 6.6. Shared asset cleanup and invalidations

Shared cleanup must be manifest-driven. S3 object age alone is unsafe because an unchanged asset may remain actively referenced for years without being recopied or receiving a new `Last-Modified` value.

The protected asset set is the union of manifests for:

- The active KVS version.
- Every host-specific KVS pin or active preview version.
- The latest retained successful deployments, currently defaulting to ten.
- Deployments newer than `shared_assets_retention_days`.
- Any deployment explicitly retained for rollback.

After successful promotion, a dedicated background activity should:

1. Read protected manifests and build the shared-key union.
2. List `__ravion/assets/`.
3. Ignore every protected key.
4. Select only unreferenced objects older than the retention window.
5. Recheck candidates against the protected set immediately before deletion to avoid deployment races.
6. Delete in S3 batches of up to 1,000.
7. Remove manifests after their version is no longer retained and its grace period has elapsed.

`PruneStaticDirectories` must exclude the entire `__ravion/` prefix. Its existing lifecycle rules continue to prune version directories only.

The retention default must be at least the maximum HTML browser SWR window, HTML CDN SWR window, and rollback window. It must also account for long-lived open SPAs that may lazy-load an old chunk after promotion. No finite window protects indefinitely open tabs, so the configured retention period defines the support boundary explicitly.

The current default `/*` invalidation is incompatible with persistent shared assets because it purges the shared CloudFront entries on every deployment. When shared assets are enabled:

- `versioned` mode defaults to no invalidation because KVS creates the new HTML cache identity.
- `stale_while_revalidate` mode defaults to no invalidation because invalidation would replace controlled convergence with cache misses.
- Explicit invalidation paths remain an advanced escape hatch.
- Documentation warns that `/*` defeats shared-cache persistence; CloudFront invalidations have no negative pattern for excluding the shared namespace.

### 6.7. Metadata enforcement independent of upload path

The module must not classify every file extension as immutable. Classification comes only from the effective shared path patterns and optional conservative hash detection.

Cache metadata must not depend on Ravion performing the build or upload. A deployment may promote a prefix produced by any external tool, so metadata enforcement belongs exclusively in the deployment workflow when a deployment cache mode requires object metadata.

The universal path should run before promotion:

```text
EnsureStaticDirectoryExists
-> EnsureStaticObjectMetadata
-> PublishStaticSharedAssets
-> WriteStaticAssetManifest
-> PromoteStaticDirectory
-> background cleanup
```

`EnsureStaticObjectMetadata` should:

- List all objects in the candidate directory.
- Apply deployment-mode policy against paths relative to that directory.
- Inspect existing metadata.
- Skip objects already carrying the desired `Cache-Control` and `Content-Type`.
- For missing or incorrect metadata, self-copy the object with `MetadataDirective: REPLACE`, preserving all metadata that must survive replacement.
- Complete before promotion so the first cache fill sees the intended CDN policy.
- Be idempotent and safe under Temporal retries.
- Define explicit behavior for objects too large for single-call `CopyObject`.
- Surface failures clearly. Whether failure blocks promotion remains a product decision; the safer default is to block when the requested cache contract cannot be established.
- Remain the only module-managed path that adds or repairs cache metadata. Build uploaders stay generic and do not accept cache-header rules.

## 7. Versioned delivery mode

### 7.1. Goal

- Support both `spa` and `filesystem` routing.
- One coherent build is active at a time for each KVS routing key.
- KVS promotion and rollback remain the commit mechanism.
- A browser never displays stale HTML that resolves assets from the wrong build.
- Unchanged content-hashed assets stay warm at the CDN and browser across deployments.
- One HTML miss per requested page and relevant CloudFront cache after promotion is acceptable.
- After an edge observes the KVS promotion, it must not intentionally serve HTML from the previous version.

### 7.2. Target request routing

```text
HTML or route request:
  /dashboard
  -> viewer-request reads KVS active=v2
  -> SPA routing: /v2/index.html
  -> filesystem routing: /v2/dashboard/index.html
  -> version-specific CloudFront cache key

Immutable asset request:
  /assets/app.abc123.js
  -> viewer-request bypasses version prefix
  -> /__ravion/assets/assets/app.abc123.js
  -> stable CloudFront cache key across deployments
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
- The first viewer for each requested HTML page and relevant cache fetches the new object from S3.
- Assets unchanged from prior deployments remain warm because their keys are stable.
- Browser `no-cache` validates HTML before reuse and receives the current build on one refresh.
- Rollback flips KVS to the previous version; previous HTML and shared assets remain available.
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
-> miss/revalidation: origin-request Lambda@Edge rewrites origin URI to
   /v2/products/widget/index.html
-> S3 returns 304 for identical content or 200 for changed content
```

Properties:

- HTML SWR works across deployments because the cache key stays stable.
- Cache hits do not invoke Lambda@Edge.
- Lambda@Edge runs on cache miss or revalidation only.
- A KVS flip does not trigger a cache-miss wave.
- Changed pages converge after `s-maxage` plus background revalidation.
- Unchanged pages can revalidate cheaply when their ETag is stable.
- Versioned origin directories and KVS rollback remain available.
- Shared content-addressed assets make stale HTML coherent and avoid routing old chunk names into the active build.

Operational costs:

- Lambda@Edge must be published in `us-east-1` and associated by versioned ARN.
- The module gains IAM, replication, update, and deletion complexity.
- Function changes deploy more slowly than CloudFront Function changes.
- Header propagation and cache-key exclusion must be tested explicitly.
- SWR cache keys include viewer `Host`, so host-specific KVS pins and aliases cannot share stable HTML entries. `X-Ravion-Version` remains excluded from the cache key and is forwarded only by the origin request policy.

Lambda@Edge is structurally required for this exact combination: stable viewer cache key, versioned S3 directories, and KVS pointer-based origin selection.

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

Lambda@Edge is required for this mode because KVS version selection must occur behind a stable CloudFront cache key. This is an architectural toggle, not merely a different `Cache-Control` value.

## 9. Suggested module-level product model

Avoid representing this only as independent low-level cache strings. Users need to choose a consistency model.

Conceptual configuration:

```yaml
routing: spa | filesystem
deployment_cache_mode: versioned | stale_while_revalidate
html_cache_control: null
assets_cache_control: null
shared_assets_enabled: true
shared_assets_path_patterns: <internal framework defaults, caller-replaceable>
shared_assets_hash_detection_enabled: true
```

Suggested defaults:

| Setting                     | `versioned`                                                                | `stale_while_revalidate`                                  |
| --------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------- |
| HTML cache key              | Version-specific                                                           | Stable                                                    |
| Promotion                   | KVS pointer flip                                                           | KVS + origin-request resolution                           |
| HTML browser policy         | `no-cache`                                                                 | Bounded SWR for public pages; per-path overrides required |
| HTML CDN policy             | Does not bridge deploys                                                    | Short `s-maxage` + bounded SWR                            |
| Immutable assets            | Shared stable namespace                                                    | Shared stable namespace                                   |
| Shared asset classification | Internal framework path defaults plus optional conservative hash detection | Same                                                      |
| Atomic cutover              | Yes                                                                        | No; per-page convergence                                  |
| Lambda@Edge                 | No                                                                         | Yes, on cache miss/revalidation only                      |

The existing header overrides remain useful, but documentation must warn against unsafe combinations. Browser SWR should only be documented for modes with shared/durable asset resolution.

## 11. Current implementation in `flightcontrol4`

The rejected build-uploader `cache_control_rules` implementation has been removed. Static build destinations and the runner remain generic and do not own cache policy.

The current platform implementation includes:

- `aws:static` TypeSpec, generated schemas, resolver, stored deployment snapshots, rollback, and workflow propagation for deployment cache mode, shared assets, deploy-time metadata, retention, and KMS context.
- Legacy compatibility: definitions omitting the new contract retain the old deploy behavior without metadata mutation, shared publication, or shared cleanup.
- Runtime and schema rejection of SWR when shared assets are disabled.
- A Go classifier matching the CloudFront JavaScript contract for path normalization, exact and trailing `/**` patterns, static extensions, hash tokens, and service-worker exclusions.
- Pre-commit HTML metadata repair for arbitrary platform or external S3 prefixes.
- Pre-commit shared publication under `__ravion/assets/` using server-side conditional copies, checksum/ETag identity checks, collision failure, post-copy verification, and per-version manifests.
- Source and destination compare-and-swap guards so metadata or immutable content races fail before manifest creation and KVS promotion.
- Manifest-driven shared cleanup with a minimum one-day retention, persistent tombstones, repeated protected-state observation, KVS ETag checks, host-pin protection, and batched deletes.
- Safe version pruning based only on known old successful deployments; unknown or pending uploaded prefixes are no longer candidates.
- Unconditional exclusion of `__ravion/` from normal version-directory pruning.
- KVS `ListKeys` support and generated customer-role policy `1.0.38` for pin-aware cleanup.
- Correct CopyObject IAM extraction as `s3:GetObject` plus `s3:PutObject`; generated policies contain no nonexistent `s3:CopyObject` action.
- Fail-closed rejection of SSE-KMS managed publication until a dedicated exact-key deployment role exists.
- Focused schema, resolver, AWS adapter, Temporal workflow/activity, database, API handler, credentials-broker, and IAM tests.

Untracked research files already present in `flightcontrol4`, including `docs/research/` and `schema-format-research.md`, remain unrelated and untouched.

## 12. Remaining implementation plan

### 12.1. Phase 1: fix the browser correctness bug (modules2 complete)

1. Restore the known tracked `flightcontrol4` build-uploader WIP files to `HEAD`, delete only the two cache-control fixtures listed in section 11, and preserve unrelated untracked research files.
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

### 12.2. Phase 2: make immutable assets deployment-independent (implementation complete; framework and AWS integration fixtures pending)

1. Add `shared_assets_enabled`, defaulting to true.
2. Add `shared_assets_path_patterns` with the internally maintained framework defaults from section 6.3; a caller list replaces the defaults.
3. Add `shared_assets_hash_detection_enabled`, defaulting to true after the conservative matcher and fixture suite pass review.
4. Build two-deployment fixtures for every framework in the research matrix, including TanStack Start with Vite and Rsbuild.
5. Implement identical path-pattern and hash-detection behavior in Go and CloudFront JavaScript with shared fixtures.
6. Reserve `__ravion/`, add the shared S3 asset prefix and per-version manifests, and reject collisions with deployment version names.
7. Publish new immutable assets before HTML promotion and skip copies for already-present content-addressed objects.
8. Change `rewrite.js` to map classified immutable paths to `__ravion/assets/` without KVS versioning.
9. Keep mutable assets versioned or give them explicit short-cache behavior.
10. Exclude `__ravion/` from `PruneStaticDirectories` and add manifest-driven shared-asset garbage collection.
11. Remove the default `/*` invalidation when shared assets are enabled while retaining explicit invalidation paths as an advanced escape hatch.

Exit criteria:

- An unchanged hashed asset keeps the same S3 key and CloudFront cache key across deployments.
- A stale HTML page can retrieve all referenced immutable assets.
- A new hashed asset incurs one unavoidable cache fill, while unchanged assets remain warm.
- Service workers and other stable mutable files are never marked immutable accidentally.
- Framework path defaults and hash detection produce identical classifications in Go and CloudFront JavaScript.
- TanStack Start Vite assets are shared through hash detection without declaring all `/assets/**` paths immutable.
- Shared assets survive deployment because default invalidations no longer purge them.
- Cleanup never deletes an asset referenced by an active, pinned, retained, or grace-period manifest.

### 12.3. Phase 3: universal deploy-time metadata enforcement (SSE-S3 implementation complete; SSE-KMS role architecture pending)

1. Extend the `aws:static` deployment definition with ordered metadata rules.
2. Add `EnsureStaticObjectMetadata` before the promotion commit point.
3. Keep static build destinations and the runner free of cache-header configuration.
4. Add required S3 IAM permissions for HEAD/GET and self-copy PUT operations.
5. Preserve `Content-Type`, content encoding, content disposition, custom metadata, and any other required headers during metadata replacement.
6. Skip self-copy when an object already has the desired metadata, regardless of which uploader created it.
7. Add pagination, bounded concurrency, retry, cancellation, and large-object handling.
8. Record metrics: objects inspected, skipped, copied, failed, bytes represented, and duration.

Exit criteria:

- Platform builds and arbitrary pre-existing prefixes receive the same CDN metadata contract before promotion.
- Metadata processing is idempotent.
- First viewer requests cannot fill CloudFront with unintended origin headers.

### 12.4. Phase 4: introduce stale-while-revalidate delivery (cross-repository implementation complete; real CloudFront integration pending)

1. Add `deployment_cache_mode = "stale_while_revalidate"` independently from `routing`.
2. Change viewer-request behavior to preserve stable HTML URIs.
3. Pass active version and host-routing context to origin-request without adding it to the cache key.
4. Add origin-request Lambda@Edge and least-privilege IAM.
5. Define cache partitioning for aliases, previews, and host-specific KVS pins.
6. Verify SWR background revalidation uses the current KVS version.
7. Add per-path browser policy guidance so transactional routes remain `no-cache` while eligible public content may use bounded SWR through the existing `html_cache_control` field.
8. Keep shared immutable assets mandatory for browser stale-first mode.

Exit criteria:

- Deploying an unchanged large site does not replace its HTML CloudFront cache identities.
- A viewer receives a cached response immediately during deployment convergence.
- Changed HTML appears after the configured freshness/SWR process without waiting for invalidation.
- Unchanged HTML revalidates with `304` when ETag behavior permits.
- Rollback semantics are documented and tested.

### 12.5. Phase 5: cleanup and release

1. Reconcile all WIP code with the selected architecture.
2. Remove or rewrite claims that no longer match runtime behavior.
3. Reassess the `0.3.0` release version and description based on the final user-visible change set.
4. Run module formatting, validation, and tests.
5. Run schema generation and tests in `flightcontrol4`.
6. Run runner, shared-go, tower-go, and targeted Temporal workflow tests.
7. Publish a local development module definition only after platform schema/runtime support is available.
8. Validate with a real distribution using both deployment cache modes and both routing modes before publishing a release.

## 13. Validation plan

### 13.1. Functional scenarios

- SPA deployment with a browser holding old HTML.
- SPA deployment where an old hashed chunk no longer exists in the new build.
- Filesystem site with thousands of HTML pages and a small changed subset.
- Identical asset bytes and filenames across multiple deployments.
- Changed asset bytes with a new content hash.
- Shared assets disabled entirely.
- Framework defaults replaced by an empty or custom `shared_assets_path_patterns` list.
- Hash detection enabled and disabled independently from path patterns.
- TanStack Start Vite and Rsbuild output across two identical builds.
- A hash-like mutable filename rejected by the conservative detector.
- A shared immutable key collision with different content fails before KVS promotion.
- A shared asset referenced only by a host-specific KVS pin remains protected.
- An orphaned shared asset is removed only after the grace period.
- External `s3_directory` upload without Cache-Control metadata.
- External upload with correct metadata already present.
- Service worker update.
- Host-specific KVS pin and preview hostname.
- Rollback during and after cache convergence.
- CloudFront invalidation delayed or failed.
- S3 metadata pass partially fails and retries.
- Missing versioned HTML and missing shared assets return `404` through CloudFront.
- A genuine OAC, bucket-policy, or KMS denial remains `403` rather than being remapped.

### 13.2. Header and cache assertions

For each deployment cache mode, capture:

- Viewer request URI.
- Rewritten URI or origin URI.
- CloudFront cache status (`Miss`, `Hit`, `RefreshHit`).
- `Age`.
- Browser-facing `Cache-Control`.
- Origin object `Cache-Control`.
- ETag before and after identical-content deployment.
- S3 request count and bytes transferred.
- First-byte latency for the first and subsequent requests after promotion.

### 13.3. Success metrics

- Zero stale-shell asset failures.
- Versioned-mode post-promotion misses limited to versioned HTML and genuinely new assets.
- SWR-mode deployments show no deployment-correlated HTML miss wave.
- Unchanged shared assets retain high cache-hit ratios across deployments.
- Metadata fallback copies only objects lacking the desired metadata.
- Invalidations are no longer on the critical path for freshness.
