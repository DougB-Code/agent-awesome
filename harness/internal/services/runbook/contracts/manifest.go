// This file validates and verifies runbook tool manifests.
package contracts

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
)

// ValidateManifest checks marketplace-readiness metadata for a tool manifest.
func ValidateManifest(manifest ToolManifest) error {
	if strings.TrimSpace(manifest.ID) == "" {
		return fmt.Errorf("tool manifest id is required")
	}
	if strings.TrimSpace(manifest.Version) == "" {
		return fmt.Errorf("tool manifest %q version is required", manifest.ID)
	}
	if err := validateSandbox(manifest.Runtime.Sandbox); err != nil {
		return fmt.Errorf("tool manifest %q: %w", manifest.ID, err)
	}
	if isExternalManifest(manifest) {
		if strings.TrimSpace(manifest.Runtime.Sandbox) == "" {
			return fmt.Errorf("external tool manifest %q must declare runtime sandbox", manifest.ID)
		}
		if strings.TrimSpace(manifest.Signing.SignerID) == "" ||
			strings.TrimSpace(manifest.Signing.Algorithm) == "" ||
			strings.TrimSpace(manifest.Signing.Signature) == "" ||
			strings.TrimSpace(manifest.Signing.Digest) == "" {
			return fmt.Errorf("external tool manifest %q must include signing metadata", manifest.ID)
		}
		if !strings.EqualFold(strings.TrimSpace(manifest.Signing.Algorithm), "ed25519") {
			return fmt.Errorf("external tool manifest %q signing algorithm must be ed25519", manifest.ID)
		}
		if !externalSandboxSupported(manifest.Runtime.Sandbox) {
			return fmt.Errorf("external tool manifest %q must use process, wasm, container, mcp, or command-daemon sandbox", manifest.ID)
		}
	}
	return nil
}

// VerifyManifest validates an external manifest signature against trusted signers.
func VerifyManifest(manifest ToolManifest, trusted []TrustedSigner) error {
	if err := ValidateManifest(manifest); err != nil {
		return err
	}
	if !isExternalManifest(manifest) {
		return nil
	}
	digest, err := ManifestDigest(manifest)
	if err != nil {
		return err
	}
	if strings.TrimSpace(manifest.Signing.Digest) != digest {
		return fmt.Errorf("external tool manifest %q digest does not match manifest body", manifest.ID)
	}
	signer, ok := trustedSigner(manifest.Signing, trusted)
	if !ok {
		return fmt.Errorf("external tool manifest %q signer %q is not trusted", manifest.ID, manifest.Signing.SignerID)
	}
	publicKey, err := decodeBinary(signer.PublicKey)
	if err != nil {
		return fmt.Errorf("decode trusted signer %q public key: %w", signer.ID, err)
	}
	if len(publicKey) != ed25519.PublicKeySize {
		return fmt.Errorf("trusted signer %q public key has invalid length", signer.ID)
	}
	signature, err := decodeBinary(manifest.Signing.Signature)
	if err != nil {
		return fmt.Errorf("decode manifest %q signature: %w", manifest.ID, err)
	}
	if !ed25519.Verify(ed25519.PublicKey(publicKey), []byte(digest), signature) {
		return fmt.Errorf("external tool manifest %q signature is invalid", manifest.ID)
	}
	return nil
}

// ManifestDigest returns the stable digest that external signatures cover.
func ManifestDigest(manifest ToolManifest) (string, error) {
	unsigned := manifest
	unsigned.Signing.Digest = ""
	unsigned.Signing.Signature = ""
	encoded, err := json.Marshal(unsigned)
	if err != nil {
		return "", fmt.Errorf("encode manifest for digest: %w", err)
	}
	sum := sha256.Sum256(encoded)
	return "sha256:" + hex.EncodeToString(sum[:]), nil
}

// SandboxSupported reports whether a runtime sandbox name is allowed.
func SandboxSupported(sandbox string) bool {
	return validateSandbox(sandbox) == nil
}

// isExternalManifest reports whether marketplace signing/sandbox rules apply.
func isExternalManifest(manifest ToolManifest) bool {
	source := strings.ToLower(strings.TrimSpace(manifest.Source))
	if source == ManifestSourceExternal || source == "marketplace" || source == "third_party" || source == "non_aa" {
		return true
	}
	if source == "" || source == ManifestSourceAA || source == ManifestSourceInternal {
		return false
	}
	id := strings.TrimSpace(manifest.ID)
	return id != "" && !strings.HasPrefix(id, "aa.") && strings.Contains(id, ".")
}

// validateSandbox checks declared runtime isolation names.
func validateSandbox(sandbox string) error {
	trimmed := strings.TrimSpace(sandbox)
	if trimmed == "" {
		return nil
	}
	switch trimmed {
	case RuntimeSandboxAA,
		RuntimeSandboxHarnessContext,
		RuntimeSandboxMCP,
		RuntimeSandboxCommandDaemon,
		RuntimeSandboxModel,
		RuntimeSandboxProcess,
		RuntimeSandboxWASM,
		RuntimeSandboxContainer:
		return nil
	default:
		return fmt.Errorf("runtime sandbox %q is not supported", trimmed)
	}
}

// externalSandboxSupported reports whether an external tool has a real isolation boundary.
func externalSandboxSupported(sandbox string) bool {
	switch strings.TrimSpace(sandbox) {
	case RuntimeSandboxProcess, RuntimeSandboxWASM, RuntimeSandboxContainer, RuntimeSandboxMCP, RuntimeSandboxCommandDaemon:
		return true
	default:
		return false
	}
}

// trustedSigner finds a matching signer id and algorithm.
func trustedSigner(signing Signing, trusted []TrustedSigner) (TrustedSigner, bool) {
	for _, signer := range trusted {
		if strings.TrimSpace(signer.ID) == strings.TrimSpace(signing.SignerID) &&
			strings.EqualFold(strings.TrimSpace(signer.Algorithm), strings.TrimSpace(signing.Algorithm)) {
			return signer, true
		}
	}
	return TrustedSigner{}, false
}

// decodeBinary decodes base64 or hex binary text.
func decodeBinary(value string) ([]byte, error) {
	trimmed := strings.TrimSpace(value)
	if decoded, err := base64.StdEncoding.DecodeString(trimmed); err == nil {
		return decoded, nil
	}
	if decoded, err := base64.RawStdEncoding.DecodeString(trimmed); err == nil {
		return decoded, nil
	}
	return hex.DecodeString(trimmed)
}
