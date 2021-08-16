ARG SWIFT_VERSION=5.4
FROM docker.apple.com/apple-swift/swift:${SWIFT_VERSION}
#FROM swiftlang/swift:nightly-5.5-focal

RUN apt-get update && apt-get install -y libsqlite3-dev unzip # required by SwiftPM/TSC
RUN apt-get update && apt-get install -y netcat
