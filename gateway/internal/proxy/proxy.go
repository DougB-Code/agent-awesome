// This file forwards gateway HTTP traffic to upstream services with body caps.
package proxy

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
)

const maxRequestBodyBytes int64 = 8 << 20

var errRequestBodyTooLarge = errors.New("request body too large")

// Proxy forwards ADK-compatible API traffic to the configured harness.
type Proxy struct {
	upstream        *url.URL
	client          *http.Client
	mountPrefix     string
	requestTimeout  time.Duration
	upstreamHeaders http.Header
	transformBody   BodyTransformer
	routeGroup      string
}

// BodyTransformer rewrites a request body before it is forwarded upstream.
type BodyTransformer func(*http.Request, []byte) ([]byte, error)

// Option customizes proxy request forwarding.
type Option func(*Proxy)

// WithBodyTransformer installs one generic request body transformer.
func WithBodyTransformer(transformer BodyTransformer) Option {
	return func(p *Proxy) {
		p.transformBody = transformer
	}
}

// WithUpstreamHeader sets one trusted header after caller headers are copied.
func WithUpstreamHeader(key string, value string) Option {
	return func(p *Proxy) {
		key = http.CanonicalHeaderKey(strings.TrimSpace(key))
		if key == "" || value == "" {
			return
		}
		if p.upstreamHeaders == nil {
			p.upstreamHeaders = make(http.Header)
		}
		p.upstreamHeaders.Set(key, value)
	}
}

// WithRouteGroup sets the safe route-group name used for proxy diagnostics.
func WithRouteGroup(routeGroup string) Option {
	return func(p *Proxy) {
		p.routeGroup = strings.TrimSpace(routeGroup)
	}
}

// New creates a proxy for one upstream API base URL.
func New(upstreamBaseURL string, mountPrefix string, timeout time.Duration, options ...Option) (*Proxy, error) {
	upstream, err := url.Parse(upstreamBaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse upstream URL: %w", err)
	}
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	proxy := &Proxy{
		upstream:       upstream,
		client:         &http.Client{},
		mountPrefix:    strings.TrimRight(mountPrefix, "/"),
		requestTimeout: timeout,
	}
	for _, option := range options {
		option(proxy)
	}
	return proxy, nil
}

// ServeHTTP proxies one request and preserves streaming response bodies.
func (p *Proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), p.requestTimeout)
	defer cancel()

	body, err := p.requestBody(w, r)
	if err != nil {
		if errors.Is(err, errRequestBodyTooLarge) {
			http.Error(w, "payload too large", http.StatusRequestEntityTooLarge)
			return
		}
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
	copyUpstreamHeaders(req.Header, p.upstreamHeaders)
	req.Host = p.upstream.Host

	resp, err := p.client.Do(req)
	if err != nil {
		log.Error().
			Err(err).
			Str("route_group", p.routeGroupName()).
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Msg("upstream request failed")
		http.Error(w, "upstream harness unavailable: "+err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 500 {
		log.Warn().
			Int("status", resp.StatusCode).
			Str("route_group", p.routeGroupName()).
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Msg("upstream returned server error")
	}
	copyResponseHeaders(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(flushingWriter{writer: w}, resp.Body)
}

// routeGroupName returns a stable log group for this proxy.
func (p *Proxy) routeGroupName() string {
	if strings.TrimSpace(p.routeGroup) == "" {
		return "unknown"
	}
	return p.routeGroup
}

// requestBody returns a possibly rewritten request body for upstream forwarding.
func (p *Proxy) requestBody(w http.ResponseWriter, r *http.Request) (io.Reader, error) {
	if r.Body == nil {
		return nil, nil
	}
	bodyReader := http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)
	defer bodyReader.Close()
	body, err := io.ReadAll(bodyReader)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return nil, errRequestBodyTooLarge
		}
		return nil, fmt.Errorf("read request body: %w", err)
	}
	if p.transformBody != nil {
		next, err := p.transformBody(r, body)
		if err != nil {
			return nil, fmt.Errorf("transform request body: %w", err)
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

// copyUpstreamHeaders adds gateway-owned headers to the upstream request.
func copyUpstreamHeaders(dst http.Header, src http.Header) {
	for key, values := range src {
		dst.Del(key)
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
