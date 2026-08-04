# grpcurl

`grpcurl` is a command-line tool for interacting with gRPC servers, filling the
role `curl` plays for HTTP APIs. It invokes unary and streaming RPCs from the
shell with JSON or protobuf-text request bodies, and can discover a server's
service surface at runtime through the gRPC server reflection protocol.

Where reflection is unavailable it works from local `.proto` sources or a
compiled protoset instead — which also lets it `list` and `describe` service,
method, message and enum descriptors entirely offline, with no server involved.

## What's included

- **grpcurl** — the gRPC command-line client: invoke RPCs, and list or describe
  descriptors from server reflection, `.proto` sources, or a protoset

## Links

- [grpcurl on GitHub](https://github.com/fullstorydev/grpcurl)
- [gRPC Server Reflection Protocol](https://github.com/grpc/grpc/blob/master/doc/server-reflection.md)
