package proxy

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Proxy forwards ADK-compatible API traffic to the configured harness.
type Proxy struct {
	upstream       *url.URL
	client         *http.Client
	mountPrefix    string
	requestTimeout time.Duration
}

// New creates a proxy for one harness API base URL.
func New(upstreamBaseURL string, mountPrefix string, timeout time.Duration) (*Proxy, error) {
	upstream, err := url.Parse(upstreamBaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse upstream URL: %w", err)
	}
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	return &Proxy{
		upstream:       upstream,
		client:         &http.Client{},
		mountPrefix:    strings.TrimRight(mountPrefix, "/"),
		requestTimeout: timeout,
	}, nil
}

// ServeHTTP proxies one request and preserves streaming response bodies.
func (p *Proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), p.requestTimeout)
	defer cancel()

	body, err := p.requestBody(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	target := p.targetURL(r)
	req, err := http.NewRequestWithContext(ctx, r.Method, target.String(), body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	copyRequestHeaders(req.Header, r.Header)
	req.Host = p.upstream.Host

	resp, err := p.client.Do(req)
	if err != nil {
		http.Error(w, "upstream harness unavailable: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	copyResponseHeaders(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(flushingWriter{writer: w}, resp.Body)
}

// requestBody returns a possibly rewritten request body for upstream forwarding.
func (p *Proxy) requestBody(r *http.Request) (io.Reader, error) {
	if r.Body == nil {
		return nil, nil
	}
	defer r.Body.Close()
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return nil, fmt.Errorf("read request body: %w", err)
	}
	if r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, "/run_sse") {
		next, _, err := InjectRuntimePolicy(body)
		if err != nil {
			return nil, fmt.Errorf("inject runtime policy: %w", err)
		}
		body = next
	}
	return bytes.NewReader(body), nil
}

// targetURL builds the upstream URL for one mounted gateway path.
func (p *Proxy) targetURL(r *http.Request) *url.URL {
	target := *p.upstream
	relativePath := strings.TrimPrefix(r.URL.Path, p.mountPrefix)
	target.Path = joinURLPath(p.upstream.Path, relativePath)
	target.RawQuery = r.URL.RawQuery
	return &target
}

// copyRequestHeaders forwards caller headers except hop-by-hop transport headers.
func copyRequestHeaders(dst http.Header, src http.Header) {
	for key, values := range src {
		if isHopByHopHeader(key) || strings.EqualFold(key, "authorization") {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

// copyResponseHeaders forwards upstream response headers.
func copyResponseHeaders(dst http.Header, src http.Header) {
	for key, values := range src {
		if isHopByHopHeader(key) {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

// isHopByHopHeader reports whether a header should stay on one HTTP transport leg.
func isHopByHopHeader(key string) bool {
	switch strings.ToLower(key) {
	case "connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade":
		return true
	default:
		return false
	}
}

// joinURLPath combines a base path and a mounted relative path.
func joinURLPath(basePath string, relativePath string) string {
	basePath = strings.TrimRight(basePath, "/")
	relativePath = strings.TrimLeft(relativePath, "/")
	if basePath == "" {
		return "/" + relativePath
	}
	if relativePath == "" {
		return basePath
	}
	return basePath + "/" + relativePath
}

// flushingWriter flushes streaming chunks as they are copied from upstream.
type flushingWriter struct {
	writer http.ResponseWriter
}

// Write forwards bytes and flushes when the response supports streaming flushes.
func (w flushingWriter) Write(data []byte) (int, error) {
	count, err := w.writer.Write(data)
	if flusher, ok := w.writer.(http.Flusher); ok {
		flusher.Flush()
	}
	return count, err
}
