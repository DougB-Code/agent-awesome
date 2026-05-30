// This file tests deterministic workflow contract inference and validation.
package contracts

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"testing"
)

// TestInferObservedContractDerivesSchemaAndFacets verifies examples become usable contracts.
func TestInferObservedContractDerivesSchemaAndFacets(t *testing.T) {
	contract, observed := InferObservedContract([]map[string]any{{
		"customer": map[string]any{"email": "ada@example.com"},
		"invoice":  map[string]any{"total": 42.5},
	}})

	if len(observed) == 0 {
		t.Fatalf("observed = empty, want inferred fields")
	}
	if !hasString(contract.Facets, "customer.email") {
		t.Fatalf("facets = %#v, want customer.email", contract.Facets)
	}
	if !hasString(contract.Facets, "invoice.total") {
		t.Fatalf("facets = %#v, want invoice.total", contract.Facets)
	}
	customer, _ := contract.Schema["properties"].(map[string]any)["customer"].(map[string]any)
	if customer["type"] != "object" {
		t.Fatalf("customer schema = %#v, want object", customer)
	}
}

// TestVerifyManifestRequiresExternalTrust verifies non-AA tools prove provenance.
func TestVerifyManifestRequiresExternalTrust(t *testing.T) {
	if err := ValidateManifest(ToolManifest{ID: "aa.mail.send", Version: "1"}); err != nil {
		t.Fatalf("ValidateManifest() internal error = %v", err)
	}
	err := VerifyManifest(ToolManifest{ID: "vendor.mail.send", Version: "1", Source: ManifestSourceExternal}, nil)
	if err == nil {
		t.Fatalf("VerifyManifest() error = nil, want external trust requirements")
	}

	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateKey() error = %v", err)
	}
	manifest := ToolManifest{
		ID:      "vendor.mail.send",
		Version: "1",
		Source:  ManifestSourceExternal,
		Runtime: Runtime{Sandbox: RuntimeSandboxProcess},
		Signing: Signing{
			SignerID:  "vendor",
			Algorithm: "ed25519",
		},
	}
	digest, err := ManifestDigest(manifest)
	if err != nil {
		t.Fatalf("ManifestDigest() error = %v", err)
	}
	manifest.Signing.Digest = digest
	manifest.Signing.Signature = base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, []byte(digest)))
	err = VerifyManifest(manifest, []TrustedSigner{{
		ID:        "vendor",
		Algorithm: "ed25519",
		PublicKey: base64.StdEncoding.EncodeToString(publicKey),
	}})
	if err != nil {
		t.Fatalf("VerifyManifest() external signed error = %v", err)
	}
}

// TestValidateManifestRejectsExternalAARuntime verifies third-party manifests cannot claim in-process execution.
func TestValidateManifestRejectsExternalAARuntime(t *testing.T) {
	err := ValidateManifest(ToolManifest{
		ID:      "vendor.unsafe.tool",
		Version: "1",
		Source:  ManifestSourceExternal,
		Runtime: Runtime{Sandbox: RuntimeSandboxAA},
		Signing: Signing{
			SignerID:  "vendor",
			Algorithm: "ed25519",
			Digest:    "sha256:abc",
			Signature: "abc",
		},
	})
	if err == nil {
		t.Fatalf("ValidateManifest() error = nil, want external sandbox rejection")
	}
}

// hasString reports whether a string list contains a value.
func hasString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
