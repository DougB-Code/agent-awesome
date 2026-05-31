// This file tests Go-struct contract generation.
package contracts

import "testing"

// TestInputContractFromStructUsesJSONAndAATags verifies reflection contracts are schema-assisted.
func TestInputContractFromStructUsesJSONAndAATags(t *testing.T) {
	type SendEmailInput struct {
		To      string   `json:"to" aa:"facet=email.recipient,required"`
		Subject string   `json:"subject,omitempty" aa:"facet=email.subject"`
		Body    string   `json:"body"`
		Tags    []string `json:"tags,omitempty"`
		Secret  string   `json:"-"`
	}

	contract, err := InputContractFromStruct(SendEmailInput{})
	if err != nil {
		t.Fatalf("InputContractFromStruct() error = %v", err)
	}
	if len(contract.Accepts) != 1 || contract.Accepts[0].Kind != "object" {
		t.Fatalf("accepts = %#v, want object carrier", contract.Accepts)
	}
	if len(contract.RequiredFacets) != 1 || contract.RequiredFacets[0] != "email.recipient" {
		t.Fatalf("required facets = %#v, want email.recipient", contract.RequiredFacets)
	}
	properties, _ := contract.Schema["properties"].(map[string]any)
	if _, ok := properties["secret"]; ok {
		t.Fatalf("properties included json:- field: %#v", properties)
	}
	required, _ := contract.Schema["required"].([]any)
	if len(required) != 1 || required[0] != "to" {
		t.Fatalf("required fields = %#v, want to", required)
	}
}
