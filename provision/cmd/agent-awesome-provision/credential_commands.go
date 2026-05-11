// Package main implements external credential command handlers.
package main

import (
	"flag"
	"fmt"
	"os"

	"agentprovision/internal/state"
)

// setCredential stores one external provider credential in the OS keyring.
func setCredential(args []string) error {
	fs := flag.NewFlagSet("credentials set", flag.ContinueOnError)
	valueFlag := fs.String("value", "", "secret value; omit to read from stdin")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: agent-awesome-provision credentials set NAME [--value VALUE]")
	}
	name, err := externalCredentialName(fs.Arg(0))
	if err != nil {
		return err
	}
	value, err := readCredentialValue(*valueFlag, os.Stdin, os.Stderr, name)
	if err != nil {
		return err
	}
	if err := state.DefaultSecretStore().Set(name, value); err != nil {
		return err
	}
	fmt.Printf("Stored credential %s in the OS keyring\n", name)
	return nil
}

// removeCredential removes one external provider credential from the OS keyring.
func removeCredential(args []string) error {
	fs := flag.NewFlagSet("credentials remove", flag.ContinueOnError)
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: agent-awesome-provision credentials remove NAME")
	}
	name, err := externalCredentialName(fs.Arg(0))
	if err != nil {
		return err
	}
	if err := state.DefaultSecretStore().Delete(name); err != nil {
		return err
	}
	fmt.Printf("Removed credential %s from the OS keyring\n", name)
	return nil
}
