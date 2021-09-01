# Swift Package Registry Compatibility Test Suite

This is a command-line tool for running compatibility tests against a Swift package registry server that implements
[SE-0292](https://github.com/apple/swift-evolution/blob/main/proposals/0292-package-registry-service.md),
[SE-0321](https://github.com/apple/swift-evolution/blob/main/proposals/0321-package-registry-publish.md)
and the corresponding [service specification](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md).

## `package-registry-compatibility` command

The compatibility test suite covers these API endpoints:

| Sub-Command                                       | API Endpoint                                                  | API Required |
| :------------------------------------------------ | :------------------------------------------------------------ | :----------: |
| [`list-package-releases`](#subcommand-1)          | `GET /{scope}/{name}`                                         | Yes          |
| [`fetch-package-release-info`](#subcommand-2)     | `GET /{scope}/{name}/{version}`                               | Yes          |
| [`fetch-package-release-manifest`](#subcommand-3) | `GET /{scope}/{name}/{version}/Package.swift{?swift-version}` | Yes          |
| `download-source-archive`                         | `GET /{scope}/{name}/{version}.zip`                           | Yes          |
| `lookup-package-identifiers`                      | `GET /identifiers{?url}`                                      | Yes          |
| [`create-package-release`](#subcommand-6)         | `PUT /{scope}/{name}/{version}`                               | No           |
| [`all`](#subcommand-all)                          | All of the above                                              | N/A          |

### Sub-command arguments and options

All of the sub-commands have the same arguments and options:

```bash
package-registry-compatibility <sub-command> <url> <config-path> [--auth-token <auth-token>] [--api-version <api-version>] [--allow-http] [--generate-data]
```

The URL of the package registry being tested is set via the `url` argument. `https` scheme is required, but user may choose to allow
`http` by setting the `--allow-http` flag.

Each sub-command requires a JSON configuration file, described in their corresponding section below.
The path of the configuration file is specified with the `config-path` argument.

Sub-commands operate in one of two modes:
- Data already exists in the registry. The tests simply verify that the values returned by the server match the expected values specified in the configuration file.
- Generate data for the test requests. The registry must implement the ["create package release" API](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#46-create-a-package-release) in this case, since the tool will use it to create the package releases needed for testing. The `--generate-data` flag enables this mode.

The two test modes require different configuration format. See the corresponding sub-command section for more details.

The optional `auth-token` argument specifies the authentication token to be used for registry requests (i.e., the `Authorization` HTTP header).
It is in the format of `<type>:<token>` where `<type>` is one of: `basic`, `bearer`, `token`. For example, for basic authentication, `<token>` would be
`username:password` (i.e., `basic:username:password`).

There is also an optional `api-version` argument for specifying the API version to use in the `Accept` HTTP request header. It
defaults to `1` if omitted.

#### Test HTTP client

All HTTP requests sent by the test HTTP client include the following headers:
- `Accept: application/vnd.swift.registry.v{apiVersion}+{mediaType}` ([3.5](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#35-api-versioning))

#### Test results

The tool can be used to test success and/or failure scenarios. Anything that the server **must** do according to the API
specification but does not would result in an error. Anything that the server **should** do but does not would result in
a warning. The tool tries to execute as many assertions as it can unless it encounters a fatal error (e.g., invalid JSON).
All warnings and errors are collected and printed at the end of each test case.

All HTTP server responses **must** include the following headers:
- `Content-Version` ([3.5](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#35-api-versioning))
- `Content-Type` ([3.5](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#35-api-versioning)) unless the response body is empty

<a name="subcommand-1"></a>
### `list-package-releases` sub-command

```bash
package-registry-compatibility list-package-releases <url> <config-path>
```

This sub-command tests the "list package release" (`GET /{scope}/{name}`) API endpoint ([4.1](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#41-list-package-releases)).

##### Sample server response

```json
HTTP/1.1 200 OK
Content-Type: application/json
Content-Version: 1
Content-Length: 508
Link: <https://github.com/mona/LinkedList>; rel="canonical",
      <ssh://git@github.com:mona/LinkedList.git>; rel="alternate",
      <https://packages.example.com/mona/LinkedList/1.1.1>; rel="latest-version",
      <https://github.com/sponsors/mona>; rel="payment"

{
    "releases": {
        "1.1.1": {
            "url": "https://packages.example.com/mona/LinkedList/1.1.1"
        },
        "1.1.0": {
            "url": "https://packages.example.com/mona/LinkedList/1.1.0",
            "problem": {
                "status": 410,
                "title": "Gone",
                "detail": "this release was removed from the registry"
            }
        },
        "1.0.0": {
            "url": "https://packages.example.com/mona/LinkedList/1.0.0"
        }
    }
}
```

#### Test configuration

##### Without `--generate-data` flag

The test configuration is a `listPackageReleases` JSON object with the following key-values:
- `packages`: An array of JSON objects describing packages found in the registry and their expected responses:
  - `package`: A JSON object that includes the package `scope` and `name`.
  - `numberOfReleases`: The total number of releases expected for the package. If pagination is supported by the server, the test will fetch all pages to obtain the total.
  - `versions`: A set of versions that must be present in the response. This can be a subset of all versions. If pagination is supported by the server, the test will fetch all pages to collect all version details.
  - `unavailableVersions`: Package versions that are unavailable (e.g., deleted). The server should communicate unavailability using a `problem` object, which the test enforces if `problemProvided` is `true`.
  - `linkRelations`: Relations that should be included in the `Link` response header (e.g., `latest-version`, `canonical`, `alternate`). Omit this if the server does not set the `Link` header. Do not include pagination relations (e.g., `next`, `last`, etc.) in this.
- `unknownPackages`: An array of package `scope` and `name` JSON objects for packages that do not exist in the registry. In other words, the server is expected to return HTTP status code `404` for these.
- `packageURLProvided`: If `true`, each package release detail JSON object must include the `url` key.
- `problemProvided`: If `true`, the detail JSON object of an unavailable version must include `problem` key.
- `paginationSupported`: If `true`, the `Link` HTTP response header should include `next`, `last`, `first`, `prev` relations, and a response may potentially contain only a subset of a package's releases.

###### Sample configuration

```json
{
    "listPackageReleases": {
        "packages": [
            {
                "package": { "scope": "apple", "name": "swift-nio" },
                "numberOfReleases": 3,
                "versions": [ "1.14.2", "2.29.0", "2.30.0" ],
                "unavailableVersions": [ "2.29.0" ],
                "linkRelations": [ "latest-version", "canonical" ]
            }
        ],
        "unknownPackages": [
            { "scope": "unknown", "name": "unknown" }
        ],
        "packageURLProvided": true,
        "problemProvided": true,
        "paginationSupported": false
    }
}
```

##### With `--generate-data` flag

See [the corresponding section for the `create-package-release` sub-command](#generate-data-required) for required
configuration when `--generate-data` flag is set.

The `listPackageReleases` object is also required:
- `linkHeaderIsSet`: `true` indicates the server includes `Link` header (e.g., `latest-version`, `canonical`, `alternate` relations) in the response, thus the generate should set `linkRelations` accordingly.
- `packageURLProvided`: If `true`, each package release object in the response must include the `url` key.
- `problemProvided`: If `true`, the detail JSON object of an unavailable release must include `problem` key.
- `paginationSupported`: If `true`, the `Link` HTTP response header should include `next`, `last`, `first`, `prev` relations.

The tool will use these configurations to construct the `listPackageReleases` configuration described in the previous section for testing.

###### Sample configuration

```json
{
    "listPackageReleases": {
        "linkHeaderIsSet": true,
        "packageURLProvided": true,
        "problemProvided": true,
        "paginationSupported": false
    }
}
```

#### Test details

A. For each package in `packages`:
1. Send `GET /{scope}/{name}` request and wait for server response.
2. Response status code must be `200`. Response must include `Content-Type` (`application/json`) and `Content-Version` headers.
3. If `linkRelations` is specified, then the `Link` response header must include these relations.
4. Response body must be a JSON object with `releases` key. If pagination is supported (i.e., `paginationSupported == true`), the test will fetch all pages using URL links in the `Link` header. Otherwise, the test will assume the response contains all of the releases.
5. The number of releases must match `numberOfReleases`.
6. The keys (i.e., versions) in the `releases` JSON object must contain `versions`.
7. For each package release detail JSON object:
    1. There must be `url` key if `packageURLProvided` is `true`.
    2. If a version belongs to `unavailableVersions` and `problemProvided` is `true`, then there must be `problem` key.
8. Repeat steps 1-7 with flipcased `scope` and `name` in the request URL to test for case-insensitivity.

B. For each package in `unknownPackages`:
1. Send `GET /{scope}/{name}` request and wait for server response.
2. Response status code must be `404`.
3. Response body should be a problem details JSON object.

C. The same as A except the request URI is `/{scope}/{name}.json`.

D. The same as B except the request URI is `/{scope}/{name}.json`.

<a name="subcommand-2"></a>
### `fetch-package-release-info` sub-command

```bash
package-registry-compatibility fetch-package-release-info <url> <config-path>
```

This sub-command tests the "fetch information about a package release" (`GET /{scope}/{name}/{version}`) API endpoint ([4.2](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#42-fetch-information-about-a-package-release)).

##### Sample server response

```json
HTTP/1.1 200 OK
Content-Version: 1
Content-Type: application/json
Content-Length: 720
Link: <https://packages.example.com/mona/LinkedList/1.1.1>; rel="latest-version",
      <https://packages.example.com/mona/LinkedList/1.0.0>; rel="predecessor-version"
{
  "id": "mona.LinkedList",
  "version": "1.1.1",
  "resources": [
    {
      "name": "source-archive",
      "type": "application/zip",
      "checksum": "a2ac54cf25fbc1ad0028f03f0aa4b96833b83bb05a14e510892bb27dea4dc812"
    }
  ],
  "metadata": { ... }
}
```

#### Test configuration

##### Without `--generate-data` flag

The test configuration is a `fetchPackageReleaseInfo` JSON object with the following key-values:
- `packageReleases`: An array of JSON objects describing package releases found in the registry and their expected responses:
  - `packageRelease`: A JSON object that includes the `package` (`scope` and `name`) and `version`.
  - `resources`: An array of JSON objects describing the package release's resources (e.g., source archive).
  - `keyValues`: Key-value pairs that must be found in the package release's `metadata`. Currently only string values are supported.
  - `linkRelations`: Relations that should be included in the `Link` response header (e.g., `latest-version`, `successor-version`, `predecessor-version`). Omit this if the server does not set the `Link` header.
- `unknownPackageReleases`: An array of "package release" JSON objects for package releases that do not exist in the registry. In other words, the server is expected to return HTTP status code `404` for these.

###### Sample configuration

```json
{
    "fetchPackageReleaseInfo": {
        "packageReleases": [
            {
                "packageRelease": {
                    "package": { "scope": "apple", "name": "swift-nio" },
                    "version": "2.30.0"
                },
                "resources": [
                    {
                        "name": "source-archive",
                        "type": "application/zip",
                        "checksum": "e9a5540d37bf4fa0b5d5a071b366eeca899b37ece4ce93b26cc14286d57fbcef"
                    }
                ],
                "keyValues": {
                    "repositoryURL": "https://github.com/apple/swift-nio",
                    "commitHash": "d79e333"
                },
                "linkRelations": [ "latest-version", "predecessor-version" ]
            }
        ],
        "unknownPackageReleases": [
            {
                "package": { "scope": "unknown", "name": "unknown" },
                "version": "1.0.0"
            }
        ]
    }
}
```

##### With `--generate-data` flag

See [the corresponding section for the `create-package-release` sub-command](#generate-data-required) for required
configuration when `--generate-data` flag is set.

The `fetchPackageReleaseInfo` object is also required:
- `linkHeaderIsSet`: `true` indicates the server includes `Link` header (e.g., `latest-version`, `successor-version`, `predecessor-version` relations) in the response, thus the generate should set `linkRelations` accordingly.

The tool will use these configurations to construct the `fetchPackageReleaseInfo` configuration described in the previous section for testing.

###### Sample configuration

```json
{
    "fetchPackageReleaseInfo": {
        "linkHeaderIsSet": true
    }
}
```

#### Test details

A. For each package release in `packageReleases`:
1. Send `GET /{scope}/{name}/{version}` request and wait for server response.
2. Response status code must be `200`. Response must include `Content-Type` (`application/json`) and `Content-Version` headers.
3. If `linkRelations` is specified, then the `Link` response header must include these relations.
4. Response body must be a JSON map with keys `id` and `version`.
5. The response JSON map must have matching `resources`.
6. If `metadata` is specified, the response JSON map's `metadata` must have matching key-value pairs.
7. Repeat steps 1-6 with flipcased `scope` and `name` in the request URL to test for case-insensitivity.

B. For each packageRelease in `unknownPackageReleases`:
1. Send `GET /{scope}/{name}/{version}` request and wait for server response.
2. Response status code must be `404`.
3. Response body should be a problem details JSON object.

C. The same as A except the request URI is `/{scope}/{name}/{version}.json`.

D. The same as B except the request URI is `/{scope}/{name}/{version}.json`.

<a name="subcommand-3"></a>
### `fetch-package-release-manifest` sub-command

```bash
package-registry-compatibility fetch-package-release-manifest <url> <config-path>
```

This sub-command tests the "fetch manifest for a package release" (`GET /{scope}/{name}/{version}/Package.swift`) API endpoint ([4.3](https://github.com/apple/swift-package-manager/blob/f3749218c8e803e52efaa0a2e8dd4c59edff9bf4/Documentation/Registry.md#43-fetch-manifest-for-a-package-release)).

##### Sample server response

```
HTTP/1.1 200 OK
Cache-Control: public, immutable
Content-Type: text/x-swift
Content-Disposition: attachment; filename="Package.swift"
Content-Length: 361
Content-Version: 1
Link: <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4>; rel="alternate"; filename="Package@swift-4.swift"; swift-tools-version="4.0",
      <http://packages.example.com/mona/LinkedList/1.1.1/Package.swift?swift-version=4.2>; rel="alternate"; filename="Package@swift-4.2.swift"; swift-tools-version="4.0"

// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "LinkedList",
    products: [
        .library(name: "LinkedList", targets: ["LinkedList"])
    ],
    targets: [
        .target(name: "LinkedList"),
        .testTarget(name: "LinkedListTests", dependencies: ["LinkedList"]),
    ],
    swiftLanguageVersions: [.v4, .v5]
)
```

#### Test configuration

##### Without `--generate-data` flag

The test configuration is a `fetchPackageReleaseManifest` JSON object with the following key-values:
- `packageReleases`: An array of JSON objects describing package releases found in the registry:
  - `packageRelease`: A JSON object that includes the `package` (`scope` and `name`) and `version`.
  - `swiftVersions`: An array of Swift versions that have version-specific manifest (i.e., `Package@swift-{swift-version}.swift`).
  - `noSwiftVersions`: An array of Swift versions that do not have version-specific manifest (i.e., `Package@swift-{swift-version}.swift`). The server is expected to return HTTP status code `303` which redirects client to the unqualified manifest (i.e., `Package.swift`).
- `unknownPackageReleases`: An array of "package release" JSON objects for package releases that do not exist in the registry. In other words, the server is expected to return HTTP status code `404` for these.
- `contentLengthHeaderIsSet`: If `true`, the `Content-Length` HTTP response header must be set.
- `contentDispositionHeaderIsSet`: If `true`, the `Content-Disposition` HTTP response header must be set.
- `linkHeaderHasAlternateRelations`: If `true`, the registry should include `alternate` relation(s) in the `Link` HTTP response header when fetching the unqualified manifest (i.e., `Package.swift`) and if the release has version-specific manifests.

###### Sample configuration

```json
{
    "fetchPackageReleaseManifest": {
        "packageReleases": [
            {
                "packageRelease": {
                    "package": { "scope": "sunshinejr", "name": "SwiftyUserDefaults" },
                    "version": "5.3.0"
                },
                "swiftVersions": [ "4.2" ],
                "noSwiftVersions": [ "5.0" ]
            }
        ],
        "unknownPackageReleases": [
            {
                "package": { "scope": "unknown", "name": "unknown" },
                "version": "1.0.0"
            }
        ],
        "contentLengthHeaderIsSet": true,
        "contentDispositionHeaderIsSet": true,
        "linkHeaderHasAlternateRelations": true
    }
}
```

##### With `--generate-data` flag

See [the corresponding section for the `create-package-release` sub-command](#generate-data-required) for required
configuration when `--generate-data` flag is set.

The `fetchPackageReleaseManifest` object is also required:
- `contentLengthHeaderIsSet`: If `true`, the `Content-Length` HTTP response header must be set.
- `contentDispositionHeaderIsSet`: If `true`, the `Content-Disposition` HTTP response header must be set.
- `linkHeaderHasAlternateRelations`: If `true`, the registry should include `alternate` relation(s) in the `Link` HTTP response header when fetching the unqualified manifest (i.e., `Package.swift`) and if the release has version-specific manifests.

The tool will use these configurations to construct the `fetchPackageReleaseManifest` configuration described in the previous section for testing.

###### Sample configuration

```json
{
    "fetchPackageReleaseManifest": {
        "contentLengthHeaderIsSet": true,
        "contentDispositionHeaderIsSet": true,
        "linkHeaderHasAlternateRelations": true
    }
}
```

#### Test details

For each package release in `packageReleases`:
1. Send `GET /{scope}/{name}/{version}/Package.swift` request and wait for server response.
2. Response status code must be `200`. Response must include `Content-Type` (`text/x-swift`) and `Content-Version` headers.
3. If `contentLengthHeaderIsSet == true`, the response must include `Content-Length` header and response body length must match.
4. If `contentDispositionHeaderIsSet == true`, the response must include `Content-Disposition` header and its value must contain `attachment; filename={filename}`.
5. If `swiftVersions` is specified and `linkHeaderHasAlternateRelations == true`, then the `Link` response header must include `alternate` relation(s).
6. Response body must be non-empty.
7. Repeat steps 1-6 with flipcased `scope` and `name` in the request URL to test for case-insensitivity.
8. For each Swift version in `swiftVersions`:
    1. Send `GET /{scope}/{name}/{version}/Package.swift?swift-version={swiftVersion}` request and wait for server response.
    2. Response status code must be `200`. Response must include `Content-Type` (`text/x-swift`) and `Content-Version` headers.
    3. If `contentLengthHeaderIsSet == true`, the response must include `Content-Length` header and response body length must match.
    4. If `contentDispositionHeaderIsSet == true`, the response must include `Content-Disposition` header and its value must contain `attachment; filename={filename}`.
    5. Response body must be non-empty.
9. For each Swift version in `noSwiftVersions`:
    1. Send `GET /{scope}/{name}/{version}/Package.swift?swift-version={swiftVersion}` request and wait for server response.
    2. Response status code must be `303`.
    3. Response must include `Location` header.
    4. The redirected response should have status code `200`. Response must include `Content-Type` (`text/x-swift`) and `Content-Version` headers.
    5. If `contentLengthHeaderIsSet == true`, the response must include `Content-Length` header and response body length must match.
    6. If `contentDispositionHeaderIsSet == true`, the response must include `Content-Disposition` header and its value must contain `attachment; filename={filename}`.
    7. Response body must be non-empty.

For each package in `unknownPackageReleases`:
1. Send `GET /{scope}/{name}/{version}/Package.swift` request and wait for server response.
2. Response status code must be `404`.
3. Response body should be a problem details JSON object.

<a name="subcommand-6"></a>
### `create-package-release` sub-command

```bash
package-registry-compatibility create-package-release <url> <config-path>
```

This sub-command tests the "create a package release" (`PUT /{scope}/{name}/{version}`) API endpoint ([4.6](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md#46-create-a-package-release)). Both synchronous and asynchronous publication are supported.

##### Sample server response

Synchronous publication:

```json
HTTP/1.1 201 Created
Content-Version: 1
Location: https://packages.example.com/github.com/mona/LinkedList/1.1.1
```

Asynchronous publication:

```json
HTTP/1.1 202 Accepted
Content-Version: 1
Location: https://packages.example.com/submissions/90D8CC77-A576-47AE-A531-D6402C4E33BC
Retry-After: 120
```

The test polls the `Location` URL until the server redirects (`301`) to the package release (which should return HTTP status `200`).

```json
HTTP/1.1 301 Moved Permanently
Content-Version: 1
Location: https://packages.example.com/mona/LinkedList/1.1.1
```

#### Test configuration

##### Without `--generate-data` flag

The test configuration is a `createPackageRelease` JSON object with the following key-values:
- `packageReleases`: An array of JSON objects describing package release to be published:
  - `package`: An optional JSON object with `scope` and `name` strings. They are used in the request URL if specified, otherwise the test will generate random values.
  - `version`: The package release version.
  - `sourceArchivePath`: The path of the source archive, which can be absolute or relative. If the latter, the tool will assume the parent directory of the configuration file (i.e., the `config-path` argument) as the base directory.
  - `metadataPath`: The path of an optional JSON file containing metadata for the package release, which can be absolute or relative. If the latter, the tool will assume the parent directory of the configuration file (i.e., the `config-path` argument) as the base directory.
- `maxProcessingTimeInSeconds`: The maximum processing time in seconds before the test considers the publication has failed. Optional.

###### Sample configuration

```json
{
    "createPackageRelease": {
        "packageReleases": [
            {
                "version": "1.14.2",
                "sourceArchivePath": "../SourceArchives/swift-nio@1.14.2.zip",
                "metadataPath": "Metadata/swift-nio@1.14.2.json"
            },
            {
                "version": "2.29.0",
                "sourceArchivePath": "../SourceArchives/swift-nio@2.29.0.zip",
                "metadataPath": "Metadata/swift-nio@2.29.0.json"
            }
        ],
        "maxProcessingTimeInSeconds": 10
    }
}
```

<a name="generate-data-required"></a>

##### With `--generate-data` flag

When the `--generate-data` flag is set, the tool will generate the necessary data and configuration for the individual compatibility
tests (as documented in the "without `--generate-data` flag" sections).

The following key-values are **required** in the configuration file:
- `resourceBaseDirectory`: The path of the directory containing test resource files (e.g., source archives, metadata JSON files, etc.), which can be absolute or relative. If the latter, the tool will assume the parent directory of the configuration file (i.e., the `config-path` argument) as the base directory.
- `packages`: An array of JSON objects containing information about package releases that will serve as the basis of compatibility test configuration. This must NOT be empty.
  - `id`: An optional JSON object with `scope` and `name` strings. The tool will generate a random package identity if this is unspecified.
  - `repositoryURL`: Repository URL of the package. Optional.
  - `releases`: An array of JSON package release objects. This must NOT be empty.
    - `version`: The package release version. Optional. The tool will generate a random version if unspecified.
    - `sourceArchivePath`: The path of the source archive, which can be absolute or relative. If the latter, the tool will use `resourceBaseDirectory` as the base directory.
    - `metadataPath`: The path of an optional JSON file containing metadata for the package release, which can be absolute or relative. If the latter, the tool will use `resourceBaseDirectory` as the base directory. The tool automatically replaces `{TEST_SCOPE}`, `{TEST_NAME}`, and `{TEST_VERSION}` with generated values.
    - `versionManifests`: An array of Swift version strings with version-specific manifest. This is optional, but it is recommended for there to be at least one package release with version-specific manifests such that the "fetch package manifest" API can be tested properly.

The `createPackageRelease` object is also required:
- `maxProcessingTimeInSeconds`: The maximum processing time in seconds before the test considers the publication has failed. Optional.

The tool will use these configurations to construct the `createPackageRelease` configuration described in the previous section to
call the "create package release" API to create package releases for testing.

###### Sample configuration

```json
{
    "resourceBaseDirectory": ".",
    "packages": [
        {
            "releases": [
                {
                    "sourceArchivePath": "../SourceArchives/swift-nio@1.14.2.zip",
                    "metadataPath": "Metadata/Templates/swift-nio@1.14.2.json"
                },
                {
                    "sourceArchivePath": "../SourceArchives/swift-nio@2.29.0.zip",
                    "metadataPath": "Metadata/Templates/swift-nio@2.29.0.json"
                },
                {
                    "sourceArchivePath": "../SourceArchives/swift-nio@2.30.0.zip",
                    "metadataPath": "Metadata/Templates/swift-nio@2.30.0.json"
                }
            ]
        },
        {
            "releases": [
                {
                    "sourceArchivePath": "../SourceArchives/SwiftyUserDefaults@5.3.0.zip",
                    "metadataPath": "Metadata/Templates/SwiftyUserDefaults@5.3.0.json",
                    "versionManifests": [ "4.2" ]
                }
            ]
        }
    ],
    "createPackageRelease": {
        "maxProcessingTimeInSeconds": 10
    }
}
```

#### Test details

A. For each package release in `packageReleases`:
1. Send `PUT /{scope}/{name}/{version}` request and wait for server response.
2. Response status code must be `201` (synchronous) or `202` (asynchronous). Response must include `Content-Version` header.
  - In case of status `201`, response should include `Location` header.
  - In case of status `202`, response must include `Location` header and should include `Retry-After` header. The `Location` URL will be polled until it yields a `301` (success) or `4xx` (failure) response status.
3. The test waits up to `maxProcessingTimeInSeconds` for publication to complete before failing.

B. For each package release in `packageReleases`:
1. Send `PUT /{scope}/{name}/{version}` request with flipcased `scope` and `name` and wait for server response.
2. Response status code must be `409` since the package release already exists and package identity should be case-insensitive.
3. Response body should be non-empty since the server should return a problem details JSON object.

<a name="subcommand-all"></a>
### `all` sub-command

```bash
package-registry-compatibility all <url> <config-path>
```

This sub-command tests all the API endpoints mentioned in the previous sections.

#### Test configuration

##### Without `--generate-data` flag

The test configuration is a JSON object with the following key-values:
- `createPackageRelease`: configuration for the `create-package-release` sub-command (without `--generate-data` flag)
- `listPackageReleases`: configuration for the `list-package-releases` sub-command (without `--generate-data` flag)

###### Sample configuration

```json
{
    "createPackageRelease" {
        // create-package-release sub-command
    },
    "listPackageReleases" {
        // list-package-releases sub-command
    }
}
```

##### With `--generate-data` flag

The test configuration is a JSON object with the following key-values:
- `createPackageRelease`: configuration for the `create-package-release` sub-command (with `--generate-data` flag)
- `listPackageReleases`: configuration for the `list-package-releases` sub-command (with `--generate-data` flag)

###### Sample configuration

```json
{
    "resourceBaseDirectory": ...,
    "packages": [...],
    "createPackageRelease": {
        // create-package-release sub-command
    },
    "listPackageReleases": {
        // list-package-releases sub-command
    }
}
```

## Sample output

```bash
package-registry-compatibility all http://localhost:9229 ./Fixtures/CompatibilityTestSuite/gendata.json --allow-http --generate-data
[0/0] Build complete!
Checking package registry URL...
Warning: Package registry URL must be HTTPS

Reading configuration file at ./Fixtures/CompatibilityTestSuite/gendata.json
Running other test preparations...

------------------------------------------------------------
Create Package Release
------------------------------------------------------------
 - Package registry URL: http://localhost:9229
 - API version: 1

Test case: Create package release test-rfavo9.package-rfavo9@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Create package release test-rfavo9.package-rfavo9@1.1.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Create package release test-rfavo9.package-rfavo9@2.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Create package release test-an0zvr.package-an0zvr@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Publish duplicate package release TEST-RFAVO9.PACKAGE-RFAVO9@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed

Test case: Publish duplicate package release TEST-RFAVO9.PACKAGE-RFAVO9@1.1.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed

Test case: Publish duplicate package release TEST-RFAVO9.PACKAGE-RFAVO9@2.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed

Test case: Publish duplicate package release TEST-AN0ZVR.PACKAGE-AN0ZVR@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed


------------------------------------------------------------
List Package Releases
------------------------------------------------------------
 - Package registry URL: http://localhost:9229
 - API version: 1

Test case: List releases for package test-rfavo9.package-rfavo9 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
Passed

Test case: List releases for package TEST-RFAVO9.PACKAGE-RFAVO9 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
Passed

Test case: List releases for package test-an0zvr.package-an0zvr (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
Passed

Test case: List releases for package TEST-AN0ZVR.PACKAGE-AN0ZVR (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-AN0ZVR/PACKAGE-AN0ZVR
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
Passed

Test case: List releases for unknown package test-7pjcgk.package-7pjcgk (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-7pjcgk/package-7pjcgk
  OK - HTTP response status
  OK - Response body
Passed

Test case: List releases for package test-rfavo9.package-rfavo9 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
Passed

Test case: List releases for package TEST-RFAVO9.PACKAGE-RFAVO9 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
Passed

Test case: List releases for package test-an0zvr.package-an0zvr (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
Passed

Test case: List releases for package TEST-AN0ZVR.PACKAGE-AN0ZVR (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-AN0ZVR/PACKAGE-AN0ZVR.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
Passed

Test case: List releases for unknown package test-7pjcgk.package-7pjcgk (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-7pjcgk/package-7pjcgk.json
  OK - HTTP response status
  OK - Response body
Passed


------------------------------------------------------------
Fetch Package Release Information
------------------------------------------------------------
 - Package registry URL: http://localhost:9229
 - API version: 1

Test case: Fetch info for package release test-rfavo9.package-rfavo9@1.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/1.0.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-RFAVO9.PACKAGE-RFAVO9@1.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/1.0.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release test-rfavo9.package-rfavo9@1.1.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/1.1.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "repositoryURL"
  OK - Metadata key "commitHash"
  OK - "predecessor-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-RFAVO9.PACKAGE-RFAVO9@1.1.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/1.1.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "repositoryURL"
  OK - Metadata key "commitHash"
  OK - "predecessor-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch info for package release test-rfavo9.package-rfavo9@2.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/2.0.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "predecessor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-RFAVO9.PACKAGE-RFAVO9@2.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/2.0.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "predecessor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release test-an0zvr.package-an0zvr@1.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr/1.0.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-AN0ZVR.PACKAGE-AN0ZVR@1.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-AN0ZVR/PACKAGE-AN0ZVR/1.0.0
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch metadata for unknown package release test-7pjcgk.package-7pjcgk@1.0.0 (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-7pjcgk/package-7pjcgk/1.0.0
  OK - HTTP response status
  OK - Response body
Passed

Test case: Fetch info for package release test-rfavo9.package-rfavo9@1.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/1.0.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-RFAVO9.PACKAGE-RFAVO9@1.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/1.0.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release test-rfavo9.package-rfavo9@1.1.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/1.1.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "repositoryURL"
  OK - Metadata key "commitHash"
  OK - "predecessor-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-RFAVO9.PACKAGE-RFAVO9@1.1.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/1.1.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "repositoryURL"
  OK - Metadata key "commitHash"
  OK - "predecessor-version" relation in "Link" response header
  OK - "successor-version" relation in "Link" response header
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch info for package release test-rfavo9.package-rfavo9@2.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/2.0.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "predecessor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-RFAVO9.PACKAGE-RFAVO9@2.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/2.0.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
  OK - "predecessor-version" relation in "Link" response header
Passed

Test case: Fetch info for package release test-an0zvr.package-an0zvr@1.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr/1.0.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch info for package release TEST-AN0ZVR.PACKAGE-AN0ZVR@1.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-AN0ZVR/PACKAGE-AN0ZVR/1.0.0.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - Parse response body
  OK - Key "id"
  OK - Key "version"
  OK - Key "resources"
  OK - Resource name=source-archive, type=application/zip
  OK - Key "metadata"
  OK - Metadata key "commitHash"
  OK - Metadata key "repositoryURL"
  OK - "latest-version" relation in "Link" response header
Passed

Test case: Fetch metadata for unknown package release test-7pjcgk.package-7pjcgk@1.0.0 (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-7pjcgk/package-7pjcgk/1.0.0.json
  OK - HTTP response status
  OK - Response body
Passed


------------------------------------------------------------
Fetch Package Release Manifest
------------------------------------------------------------
 - Package registry URL: http://localhost:9229
 - API version: 1

Test case: Fetch Package.swift for package release test-rfavo9.package-rfavo9@1.0.0
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/1.0.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for package release TEST-RFAVO9.PACKAGE-RFAVO9@1.0.0
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/1.0.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for package release test-rfavo9.package-rfavo9@1.1.0
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/1.1.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for package release TEST-RFAVO9.PACKAGE-RFAVO9@1.1.0
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/1.1.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for package release test-rfavo9.package-rfavo9@2.0.0
  OK - HTTP request: GET http://localhost:9229/test-rfavo9/package-rfavo9/2.0.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for package release TEST-RFAVO9.PACKAGE-RFAVO9@2.0.0
  OK - HTTP request: GET http://localhost:9229/TEST-RFAVO9/PACKAGE-RFAVO9/2.0.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for package release test-an0zvr.package-an0zvr@1.0.0
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr/1.0.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
  OK - "alternate" relation in "Link" response header
Passed

Test case: Fetch Package.swift for package release TEST-AN0ZVR.PACKAGE-AN0ZVR@1.0.0
  OK - HTTP request: GET http://localhost:9229/TEST-AN0ZVR/PACKAGE-AN0ZVR/1.0.0/Package.swift
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
  OK - "alternate" relation in "Link" response header
Passed

Test case: Fetch Package@swift-4.2.swift for package release test-an0zvr.package-an0zvr@1.0.0
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr/1.0.0/Package.swift?swift-version=4.2
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch missing Package@swift-4.30.swift for package release test-an0zvr.package-an0zvr@1.0.0
  OK - HTTP request: GET http://localhost:9229/test-an0zvr/package-an0zvr/1.0.0/Package.swift?swift-version=4.30
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - Response body
  OK - "Content-Disposition" response header
  OK - "Content-Length" response header
Passed

Test case: Fetch Package.swift for unknown package release test-7pjcgk.package-7pjcgk@1.0.0
  OK - HTTP request: GET http://localhost:9229/test-7pjcgk/package-7pjcgk/1.0.0/Package.swift
  OK - HTTP response status
  OK - Response body
Passed


Test summary:
Create Package Release - All tests passed.
List Package Releases - All tests passed.
Fetch Package Release Information - All tests passed.
Fetch Package Release Manifest - All tests passed.
```
