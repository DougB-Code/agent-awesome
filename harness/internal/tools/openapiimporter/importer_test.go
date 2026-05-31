// This file tests OpenAPI-to-tool-package import behavior.
package openapiimporter

import "testing"

// TestImportBuildsCurlOperations verifies required REST inputs become command
// operation schemas and curl argv templates.
func TestImportBuildsCurlOperations(t *testing.T) {
	tools, err := Import([]byte(`
openapi: 3.1.0
info:
  title: Pet Store
servers:
  - url: https://api.example.test/v1
paths:
  /pets/{petId}:
    parameters:
      - name: petId
        in: path
        required: true
        schema:
          type: string
    get:
      operationId: getPet
      summary: Get one pet.
      parameters:
        - name: include
          in: query
          required: true
          schema:
            type: string
  /pets:
    post:
      operationId: create-pet
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
`), Options{})
	if err != nil {
		t.Fatalf("Import() error = %v", err)
	}
	if got, want := tools.Name, "Pet Store"; got != want {
		t.Fatalf("Tools.Name = %q, want %q", got, want)
	}
	if !tools.LocalExec.Enabled {
		t.Fatalf("LocalExec.Enabled = false, want true")
	}
	command := tools.LocalExec.Commands[0]
	if got, want := command.Name, "Pet_Store"; got != want {
		t.Fatalf("command.Name = %q, want %q", got, want)
	}
	if got, want := len(command.Operations), 2; got != want {
		t.Fatalf("len(Operations) = %d, want %d", got, want)
	}
	getPet := command.Operations[1]
	if got, want := getPet.Name, "getPet"; got != want {
		t.Fatalf("getPet.Name = %q, want %q", got, want)
	}
	if got, want := getPet.Args[len(getPet.Args)-1], "https://api.example.test/v1/pets/{{petId}}?include={{include}}"; got != want {
		t.Fatalf("getPet URL arg = %q, want %q", got, want)
	}
	required := getPet.InputSchema["required"].([]string)
	if len(required) != 2 || required[0] != "petId" || required[1] != "include" {
		t.Fatalf("required = %#v, want petId and include", required)
	}
	createPet := command.Operations[0]
	if got, want := createPet.Name, "create_pet"; got != want {
		t.Fatalf("createPet.Name = %q, want %q", got, want)
	}
	if !containsArg(createPet.Args, "{{body}}") {
		t.Fatalf("createPet.Args = %#v, want request body placeholder", createPet.Args)
	}
}

// TestImportRequiresBaseURLWhenSchemaHasNoServer verifies no-server schemas
// remain portable by exposing base_url as a required operation input.
func TestImportRequiresBaseURLWhenSchemaHasNoServer(t *testing.T) {
	tools, err := Import([]byte(`{"openapi":"3.0.0","info":{"title":"No Server"},"paths":{"/health":{"get":{"operationId":"health"}}}}`), Options{})
	if err != nil {
		t.Fatalf("Import() error = %v", err)
	}
	operation := tools.LocalExec.Commands[0].Operations[0]
	if got, want := operation.Args[len(operation.Args)-1], "{{base_url}}/health"; got != want {
		t.Fatalf("URL arg = %q, want %q", got, want)
	}
	required := operation.InputSchema["required"].([]string)
	if len(required) != 1 || required[0] != "base_url" {
		t.Fatalf("required = %#v, want base_url", required)
	}
}

// containsArg reports whether args contains one exact value.
func containsArg(args []string, value string) bool {
	for _, arg := range args {
		if arg == value {
			return true
		}
	}
	return false
}
