package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/labstack/gommon/log"
	"github.com/peterbourgon/ff/v4"
	"github.com/peterbourgon/ff/v4/ffhelp"
	"github.com/peterbourgon/ff/v4/ffval"
	"github.com/peterbourgon/ff/v4/ffyaml"
	"github.com/valkey-io/valkey-go"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

func main() {
	// create client
	fs := ff.NewFlagSet("valkey")
	valkeyCmd := ff.Command{
		Name:  "valkey",
		Usage: "valkey [flags] <subcommand>",
		Flags: fs,
		Exec: func(context.Context, []string) error {
			return flag.ErrHelp
		},
		Subcommands: []*ff.Command{
			newClientCommand(),
		},
	}

	opts := []ff.Option{
		ff.WithConfigFileFlag("config"),
		ff.WithConfigFileParser(ffyaml.Parse),
		ff.WithEnvVarPrefix("VALKEY"),
	}
	if err := valkeyCmd.ParseAndRun(context.Background(), os.Args[1:], opts...); err != nil {
		// print help in cases were there is a flag related error
		if errors.Is(err, ff.ErrHelp) || errors.Is(err, ff.ErrDuplicateFlag) || errors.Is(err, ff.ErrAlreadyParsed) || errors.Is(err, ff.ErrUnknownFlag) || errors.Is(err, ff.ErrNotParsed) {
			fmt.Fprintf(os.Stderr, "\n%s\n", ffhelp.Command(&valkeyCmd))
		}

		// log error if it is not a help error
		if !errors.Is(err, ff.ErrHelp) {
			log.Fatal(err)
		}
		os.Exit(1)
	}
}

// newServeCommand returns a usable ff.Command for the serve subcommand.
func newClientCommand() *ff.Command {
	cfg := &config{}
	fs := ff.NewFlagSet("serve")
	_ = fs.String(0, "config", "", "config file in yaml format (optional)")
	fs.StringVar(&cfg.addr, 0, "addr", "localhost:8001", "Valkey discovery address")
	fs.Value(0, "rootCAs", x509CertificateList(&cfg.rootCAs), "Valkey TLS root CAs")

	cmd := &ff.Command{
		Name:      "client",
		Usage:     "valkey client [flags] <key> <value data...>",
		ShortHelp: "launch valkey client",
		Flags:     fs,
		Exec: func(_ context.Context, args []string) error {
			log.Info("valkey client started")
			return run(cfg)
		},
	}
	return cmd
}

type config struct {
	addr    string
	rootCAs []*x509.Certificate
}

var tokenSource oauth2.TokenSource

func run(cfg *config) error {
	caCertPool := x509.NewCertPool()
	// caCertPool.AppendCertsFromPEM(rootCAs)
	for _, ca := range cfg.rootCAs {
		caCertPool.AddCert(ca)
	}

	var err error
	tokenSource, err = google.DefaultTokenSource(context.Background(), "https://www.googleapis.com/auth/cloud-platform")
	if err != nil {
		return fmt.Errorf("Failed to get default token source: %w", err)
	}

	// Initialize Valkey client with token refresh logic
	client, err := valkey.NewClient(valkey.ClientOption{
		InitAddress: []string{cfg.addr},
		TLSConfig: &tls.Config{
			RootCAs: caCertPool,
		},
		AuthCredentialsFn: retrieveTokenFunc,
	})
	if err != nil {
		return fmt.Errorf("Failed to create client: %w", err)
	}
	defer client.Close()

	for {
		if err := client.Do(context.Background(), client.B().Set().Key("key").Value("OK").Build()).Error(); err != nil {
			return fmt.Errorf("Failed to set key/value: %w", err)
		}

		res, err := client.Do(context.Background(), client.B().Get().Key("key").Build()).ToString()
		if err != nil {
			return fmt.Errorf("Failed to get string: %w", err)
		}
		fmt.Println("Value: ", res)

		time.Sleep(1 * time.Second)
	}
	// return nil
}

// https://cloud.google.com/memorystore/docs/cluster/client-library-connection#iam_auth_and_in_transit_encryption
func retrieveTokenFunc(valkey.AuthCredentialsContext) (valkey.AuthCredentials, error) {
	authCredentials := valkey.AuthCredentials{}
	token, err := tokenSource.Token()
	if err != nil {
		return authCredentials, fmt.Errorf("Failed to get token: %w", err)
	}
	authCredentials = valkey.AuthCredentials{
		Username: "default",
		Password: token.AccessToken,
	}
	return authCredentials, nil
}

// x509CertificateList defines a flag value for a certificate list that can be provided as an array.
func x509CertificateList(certificates *[]*x509.Certificate) *ffval.List[*x509.Certificate] {
	return &ffval.List[*x509.Certificate]{
		ParseFunc: parseX509Certificate,
		Pointer:   certificates,
	}
}

func parseX509Certificate(s string) (*x509.Certificate, error) {
	// Replace "\n" by line breaks in case the certificate was provided as a one liner
	s = strings.ReplaceAll(s, `\n`, "\n")

	// Decode the certificate chain
	block, _ := pem.Decode([]byte(s))
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, errors.New("failed to find a suitable pem block type")
	}

	// Parse the certificate chain
	return x509.ParseCertificate(block.Bytes)
}
