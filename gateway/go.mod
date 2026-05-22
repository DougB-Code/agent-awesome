module agentgateway

go 1.26.0

require (
	agentawesome.dev/platform v0.0.0
	github.com/rs/zerolog v1.35.1
	nhooyr.io/websocket v1.8.17
)

replace agentawesome.dev/platform => ../platform

require (
	github.com/mattn/go-colorable v0.1.14 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	golang.org/x/sys v0.29.0 // indirect
)
