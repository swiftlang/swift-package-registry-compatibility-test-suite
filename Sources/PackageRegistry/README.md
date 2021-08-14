# Swift Package Registry Service

This is a reference implementation of [Swift Package Registry Service](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md),
proposed in [SE-0292](https://github.com/apple/swift-evolution/blob/main/proposals/0292-package-registry-service.md).

:warning: This implementation is intended for local development and testing usages only. It is **NOT** production-ready.

Features not implemented (and their corresponding section in the specification):
- Authentication (3.2)
- Rate limiting (3.4)

## Implementation Details

### API endpoints

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
