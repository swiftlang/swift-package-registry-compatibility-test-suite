# Swift Package Registry Service

This is a reference implementation of [Swift Package Registry Service](https://github.com/apple/swift-package-manager/blob/main/Documentation/Registry.md),
proposed in [SE-0292](https://github.com/apple/swift-evolution/blob/main/proposals/0292-package-registry-service.md).

:warning: This implementation is intended for local development and testing usages only. It is **NOT** production-ready.

Features not implemented (and their corresponding section in the specification):
- Authentication (3.2)
- Rate limiting (3.4)

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
