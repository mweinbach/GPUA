# API Parity Audit: `http_client.rs`

- **Generated At**: 2026-10-29T07:15:20Z
- **Upstream Rust File**: `/Users/mweinbach/Projects/GPUA/.upstream/gpui/crates/http_client/src/http_client.rs`
- **Swift Target Files**:
  - `/Users/mweinbach/Projects/GPUA/Sources/HTTPClient/http_client.swift`
- **Ledger File**: None (no exemptions applied)

## Executive Summary

| Metric | Count | Percentage |
| :--- | :--- | :--- |
| **Total Upstream `pub`/`pub(crate)` Items** | **26** | 100.0% |
| Genuine Swift Implementations | 26 | 100.0% |
| Legitimate Ledger Exemptions | 0 | 0.0% |
| — *Deferred to Later Batch* | 0 | 0.0% |
| — *Renamed in Swift* | 0 | 0.0% |
| — *Omitted (Obsolete/OS-specific)* | 0 | 0.0% |
| — *Allowed Stubs (Exempted)* | 0 | 0.0% |
| **Stubs Detected (FAIL)** | **0** | **0.0%** |
| **Missing Items (FAIL)** | **0** | **0.0%** |

**Audit Status**: ✅ PASS (100.0% accounted for, all implementations verified genuine)

## Genuine Swift Implementations

Found 26 matching genuine declarations in Swift target files:

<details>
<summary>Click to view genuine declarations (26 total)</summary>

| Line | Upstream Item | Kind | Swift Declaration / Symbol | Location |
| :--- | :--- | :--- | :--- | :--- |
| 22 | `RedirectPolicy` | `enum` | `RedirectPolicy` | `http_client.swift:8` |
| 28 | `FollowRedirects` | `struct` | `FollowRedirects` | `http_client.swift:16` |
| 30 | `HttpRequestExt` | `trait` | `HttpRequestExt` | `http_client.swift:67` |
| 60 | `HttpClient` | `trait` | `HttpClient` | `http_client.swift:98` |
| 116 | `HttpClientWithProxy` | `struct` | `HttpClientWithProxy` | `http_client.swift:144` |
| 124 | `HttpClientWithProxy::new` | `fn` | `new` | `http_client.swift:153` |
| 131 | `HttpClientWithProxy::new_url` | `fn` | `newUrl` | `http_client.swift:158` |
| 163 | `HttpClientWithUrl` | `struct` | `HttpClientWithUrl` | `http_client.swift:182` |
| 171 | `HttpClientWithUrl::new` | `fn` | `new` | `http_client.swift:192` |
| 184 | `HttpClientWithUrl::new_url` | `fn` | `newUrl` | `http_client.swift:201` |
| 198 | `HttpClientWithUrl::base_url` | `fn` | `baseUrl` | `http_client.swift:209` |
| 203 | `HttpClientWithUrl::set_base_url` | `fn` | `setBaseUrl` | `http_client.swift:215` |
| 209 | `HttpClientWithUrl::build_url` | `fn` | `buildUrl` | `http_client.swift:221` |
| 214 | `HttpClientWithUrl::build_zed_api_url` | `fn` | `buildZedApiUrl` | `http_client.swift:225` |
| 230 | `HttpClientWithUrl::build_zed_cloud_url` | `fn` | `buildZedCloudUrl` | `http_client.swift:246` |
| 243 | `HttpClientWithUrl::build_zed_cloud_url_with_query` | `fn` | `buildZedCloudUrlWithQuery` | `http_client.swift:260` |
| 256 | `HttpClientWithUrl::build_zed_llm_url` | `fn` | `buildZedLlmUrl` | `http_client.swift:282` |
| 294 | `read_proxy_from_env` | `fn` | `readProxyFromEnv` | `http_client.swift:320` |
| 310 | `read_no_proxy_from_env` | `fn` | `readNoProxyFromEnv` | `http_client.swift:337` |
| 316 | `BlockedHttpClient` | `struct` | `BlockedHttpClient` | `http_client.swift:348` |
| 319 | `BlockedHttpClient::new` | `fn` | `new` | `http_client.swift:351` |
| 361 | `FakeHttpClient` | `struct` | `FakeHttpClient` | `http_client.swift:377` |
| 368 | `FakeHttpClient::create` | `fn` | `create` | `http_client.swift:387` |
| 385 | `FakeHttpClient::with_404_response` | `fn` | `with404Response` | `http_client.swift:394` |
| 395 | `FakeHttpClient::with_200_response` | `fn` | `with200Response` | `http_client.swift:400` |
| 405 | `FakeHttpClient::replace_handler` | `fn` | `replaceHandler` | `http_client.swift:406` |

</details>
