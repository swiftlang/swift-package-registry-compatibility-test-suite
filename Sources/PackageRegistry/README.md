# Swift Package Registry Service

This is a reference implementation of [Swift Package Registry Service](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md),
proposed in [SE-0292](https://github.com/apple/swift-evolution/blob/main/proposals/0292-package-registry-service.md).

:warning: This implementation is intended for local development and testing usages only. It is **NOT** production-ready.

Features not implemented (and their corresponding section in the specification):
- Authentication (3.2)
- Rate limiting (3.4)

## Implementation Details

### API endpoints

- Error response JSON is represented by `PackageRegistryModels.ProblemDetails`. (3.3)
- Server responses, with the exception of `OPTIONS` requests ad  `204` and redirects (`3xx`) statuses, include `Content-Type` and `Content-Version` headers. (3.5)
- Package scope and name are validated using SwiftPM's `PackageModel.PackageIdentity.Scope` (3.6.1) and `PackageModel.PackageIdentity.Name` (3.6.2). Case-insensitivity is done through lowercasing strings before comparison.
- All `GET` endpoints support `HEAD` requests. (4)
- All API paths support `OPTIONS` requests. (4)

#### Create package release (`POST /{scope}/{name}/{version}`) (4.6) 

This API is in proposal stage: [pitch](https://forums.swift.org/t/package-registry-service-publish-endpoint/51067)

- Package `scope` and `name` are validated according to section 3.6 of the specification. 
- The source archive being published must be generated using the `package archive-source` command.
- `PackageRegistryModels.PackageReleaseMetadata` is the only metadata model supported by this server implementation. 
- Refer to the API specification or `PackageRegistryClient`'s source code for the request body format. Note the `\r`s and the terminating boundary line (i.e., `--boundary--\r\n`). The `metadata` part is required. Send `{}` if there is no metadata.
- The `PackageRegistryTool` module provides a CLI tool for interacting with a package registry. 
- The server executes `swift package compute-checksum` to compute the checksum. Manifest(s) are extracted and saved to the database as part of publication.
- The server does not take special actions on the `Expect: 100-continue` HTTP header. In other words, the server never returns HTTP status `417` even if it doesn't support `Expect`.
- For simplicity, only synchronous publication is supported (i.e., the server returns status `201` on successful publication). The `Prefer` HTTP header, if present in the request, is ignored.
- A published package release cannot be modified.
- If the package release already exists, the server returns HTTP status `409`.

### Database schema

There are primarily three tables in the Postgres database, all populated via the "create package release" API.

#### `package_releases` table

Package release information and metadata (e.g., `repository_url`, `commit_hash`) provided by the publisher:

| Column               | Value Type       | Description                                           |
| -------------------- |:----------------:| ----------------------------------------------------- |
| `scope`              | text             | Package scope                                         |
| `name`               | text             | Package name                                          |
| `version`            | text             | Package release version                               |
| `repository_url`     | text             | URL of the package's source repository. Optional.     |
| `commit_hash`        | text             | Commit hash associated with the release. Optional.    |
| `status`             | text             | One of: `published`, `deleted`                        |
| `created_at`         | timestamp        | Timestamp at which the release was created            |
| `updated_at`         | timestamp        | Timestamp at which the release was last updated       |

Except `status` and `updated_at`, data in this table do not change.

#### `package_resources` table

Package release resources such as source archives:

| Column               | Value Type       | Description                                           |
| -------------------- |:----------------:| ----------------------------------------------------- |
| `scope`              | text             | Package scope                                         |
| `name`               | text             | Package name                                          |
| `version`            | text             | Package release version                               |
| `checksum`           | text             | Checksum of the resource computed using the `swift package compute-checksum` tool |
| `type`               | text             | Resource type. Only `source-archive` is supported.    |
| `bytes`              | blob             | Resource bytes                                        |

Data in this table cannot be modified via the APIs.

#### `package_manifests` table

Package release manifest(s) (e.g., `Package.swift`):

| Column                  | Value Type       | Description                                           |
| ----------------------- |:----------------:| ----------------------------------------------------- |
| `scope`                 | text             | Package scope                                         |
| `name`                  | text             | Package name                                          |
| `version`               | text             | Package release version                               |
| `swift_version`         | text             | Swift version in case of version-specific manifest    |
| `filename`              | text             | Name of the manifest file                             |
| `swift_tools_version`   | text             | Tools version as specified in the manifest            |
| `bytes`                 | blob             | Manifest bytes                                        |

Data in this table cannot be modified via the APIs.

## Local Deployment

Local deployment requires docker.

To bring up a local instance of package registry service:

```bash
docker-compose -f deployment/local/docker-compose.yml up
```

The server by default runs on [http://localhost:9229](http://localhost:9229).

### Postgres

This implementation of package registry service uses Postgres database. To connect to Postgres, install `psql` by running
`brew install postgresql`. Then:

```bash
psql -h localhost -p 5432 -U postgres
```

Password is `postgres`.

To connect to a Postgres database:

```bash
psql -h localhost -p 5432 -U postgres -d <DATABASE_NAME>
```

OR

```bash
postgres-# \c <DATABASE_NAME>
```

## Run Tests

```bash
docker-compose -f docker/docker-compose.yml -f docker/docker-compose.1804.54.yml run test-registry
```
