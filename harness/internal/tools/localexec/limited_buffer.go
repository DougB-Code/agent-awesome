// This file implements bounded process output buffers.
package localexec

import "bytes"

// limitedBuffer captures output up to a configured byte limit.
type limitedBuffer struct {
	buf       bytes.Buffer
	limit     int
	truncated bool
}

// Write appends bytes until the limit is reached, while still reporting all
// bytes consumed so child processes do not see short writes.
func (b *limitedBuffer) Write(p []byte) (int, error) {
	if b.limit <= 0 {
		b.truncated = true
		return len(p), nil
	}
	remaining := b.limit - b.buf.Len()
	if remaining <= 0 {
		b.truncated = true
		return len(p), nil
	}
	if len(p) > remaining {
		b.truncated = true
		_, _ = b.buf.Write(p[:remaining])
		return len(p), nil
	}
	_, _ = b.buf.Write(p)
	return len(p), nil
}

// String returns the captured portion of the buffer.
func (b *limitedBuffer) String() string {
	return b.buf.String()
}
