# Swift Package Registry Compatibility Test Suite

This is a command-line tool for running compatibility tests against a Swift package registry server that implements
[SE-0292](https://github.com/apple/swift-evolution/blob/main/proposals/0292-package-registry-service.md),
[SE-0321](https://github.com/apple/swift-evolution/blob/main/proposals/0321-package-registry-publish.md)
and the corresponding [service specification](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md).

## `package-registry-compatibility` command

The compatibility test suite covers these API endpoints:

| Sub-Command                                                     | API Endpoint                                                  | API Required |
| :-------------------------------------------------------------- | :------------------------------------------------------------ | :----------: |
| [`list-package-releases`](#list-package-releases-sub-command)   | `GET /{scope}/{name}`                                         | Yes          |
| `fetch-package-release-info`                                    | `GET /{scope}/{name}/{version}`                               | Yes          |
| `fetch-package-release-manifest`                                | `GET /{scope}/{name}/{version}/Package.swift{?swift-version}` | Yes          |
| `download-source-archive`                                       | `GET /{scope}/{name}/{version}.zip`                           | Yes          |
| `lookup-package-identifiers`                                    | `GET /identifiers{?url}`                                      | Yes          |
| [`create-package-release`](#create-package-release-sub-command) | `PUT /{scope}/{name}/{version}`                               | No           |
| [`all`](#all-sub-command)                                       | All of the above                                              | N/A          |

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
8. Repeat steps 2-7 with uppercased `scope` and `name` in the request URL to test for case-insensitivity.

B. For each package in `unknownPackages`:
1. Send `GET /{scope}/{name}` request and wait for server response.
2. Response status code must be `404`.
3. Response body should be a problem details JSON object.

C. The same as A except the request URI is `/{scope}/{name}.json`.

D. The same as B except the request URI is `/{scope}/{name}.json`.

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
1. Send `PUT /{scope}/{name}/{version}` request with uppercased `scope` and `name` and wait for server response.
2. Response status code must be `409` since the package release already exists and package identity should be case-insensitive.
3. Response body should be non-empty since the server should return a problem details JSON object.

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

Test case: Create package release test-tqodye.package-tqodye@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Create package release test-tqodye.package-tqodye@1.1.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Create package release test-tqodye.package-tqodye@2.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Create package release test-ke0gos.package-ke0gos@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - "Content-Version" response header
  OK - "Location" response header
Passed

Test case: Publish duplicate package release TEST-TQODYE.PACKAGE-TQODYE@1.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed

Test case: Publish duplicate package release TEST-TQODYE.PACKAGE-TQODYE@1.1.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed

Test case: Publish duplicate package release TEST-TQODYE.PACKAGE-TQODYE@2.0.0
  OK - Read source archive file
  OK - Read metadata file
  OK - HTTP request to create package release
  OK - HTTP response status
  OK - Response body
Passed

Test case: Publish duplicate package release TEST-KE0GOS.PACKAGE-KE0GOS@1.0.0
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

Test case: List releases for package test-tqodye.package-tqodye (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-tqodye/package-tqodye
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
Passed

Test case: List releases for package TEST-TQODYE.PACKAGE-TQODYE (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-TQODYE/PACKAGE-TQODYE
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
Passed

Test case: List releases for package test-ke0gos.package-ke0gos (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-ke0gos/package-ke0gos
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

Test case: List releases for package TEST-KE0GOS.PACKAGE-KE0GOS (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-KE0GOS/PACKAGE-KE0GOS
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

Test case: List releases for unknown package test-3sg6we.package-3sg6we (without .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-3sg6we/package-3sg6we
  OK - HTTP response status
  OK - Response body
Passed

Test case: List releases for package test-tqodye.package-tqodye (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-tqodye/package-tqodye.json
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

Test case: List releases for package TEST-TQODYE.PACKAGE-TQODYE (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-TQODYE/PACKAGE-TQODYE.json
  OK - HTTP response status
  OK - "Content-Type" response header
  OK - "Content-Version" response header
  OK - "latest-version" relation in "Link" response header
  OK - Parse response body
  OK - Number of releases
  OK - Release versions
  OK - Parse details object for release 2.0.0
  OK - "url" for release 2.0.0
  OK - Parse details object for release 1.0.0
  OK - "url" for release 1.0.0
  OK - Parse details object for release 1.1.0
  OK - "url" for release 1.1.0
Passed

Test case: List releases for package test-ke0gos.package-ke0gos (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-ke0gos/package-ke0gos.json
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

Test case: List releases for package TEST-KE0GOS.PACKAGE-KE0GOS (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/TEST-KE0GOS/PACKAGE-KE0GOS.json
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

Test case: List releases for unknown package test-3sg6we.package-3sg6we (with .json in the URI)
  OK - HTTP request: GET http://localhost:9229/test-3sg6we/package-3sg6we.json
  OK - HTTP response status
  OK - Response body
Passed


Test summary:
Create Package Release - All tests passed.
List Package Releases - All tests passed.
```
