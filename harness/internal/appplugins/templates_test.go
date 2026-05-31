// This file tests built-in app plugin manifest templates.
package appplugins

import "testing"

// TestAppleCalendarTemplateDeclaresExternalIntegration verifies Apple Calendar
// support stays in the app plugin contract.
func TestAppleCalendarTemplateDeclaresExternalIntegration(t *testing.T) {
	manifest := AppleCalendarTemplate("Personal")
	if got, want := manifest["id"], "apple-calendar"; got != want {
		t.Fatalf("manifest id = %v, want %v", got, want)
	}
	integrations, ok := manifest["integrations"].([]any)
	if !ok || len(integrations) != 1 {
		t.Fatalf("integrations = %#v, want one integration", manifest["integrations"])
	}
	integration, ok := integrations[0].(map[string]any)
	if !ok || integration["kind"] != "apple-calendar" {
		t.Fatalf("integration = %#v, want apple-calendar", integrations[0])
	}
	credential, ok := integration["credential"].(map[string]any)
	if !ok {
		t.Fatalf("credential = %#v, want map", integration["credential"])
	}
	if got, want := credential["passwordRef"], "AA_APPLE_CALENDAR_PERSONAL_APP_PASSWORD"; got != want {
		t.Fatalf("passwordRef = %v, want %v", got, want)
	}
}
