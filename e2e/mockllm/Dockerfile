# This image runs the E2E mock OpenAI-compatible provider.
FROM golang:1.26-bookworm AS build

WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o /out/mockllm ./cmd/mockllm

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/mockllm /mockllm
EXPOSE 8080
ENTRYPOINT ["/mockllm"]
