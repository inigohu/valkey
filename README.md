# Valkey

**Valkey** is a lightweight command‑line client written in Go for interacting with a Valkey service—a key‑value store with support for OAuth2 authentication and TLS. This repository demonstrates how to use the [valkey‑go](https://github.com/valkey-io/valkey-go) client library to perform basic operations such as setting and retrieving key‑value pairs.

## Features

- **Simple Client Interface:** Uses subcommands (currently, a `client` subcommand) for interacting with a Valkey service.
- **Secure Communication:** Supports TLS with custom root CAs.
- **OAuth2 Authentication:** Leverages Google’s default token source for authentication.
- **Flexible Configuration:** Configure via command‑line flags, YAML configuration files, or environment variables (using the `VALKEY_` prefix).
- **Deployment Ready:** Includes Kubernetes and Terraform configurations to help deploy the service.

## Installation

### Prerequisites

- [Go 1.23.1](https://golang.org/dl/) or later

### Steps

1. **Clone the repository:**

   ```sh
   git clone https://github.com/inigohu/valkey.git
   cd valkey
   ```

2. **Build the project:**

   ```sh
   go build
   ```

3. **Run the client directly (for example, to start the client subcommand):**

   ```sh
   ./valkey client <key> <value data...>
   ```

   Alternatively, you can run it without building a binary:

   ```sh
   go run main.go client <key> <value data...>
   ```

## Usage

The client subcommand (`client`) demonstrates a simple loop that sets a key to a fixed value (`"OK"`) and then retrieves it every second. Here’s a summary of its usage:

```sh
./valkey client [flags] <key> <value data...>
```

### Available Flags

- **`-addr`**  
  Valkey discovery address (default: `localhost:8001`).

- **`-rootCAs`**  
  Provide PEM‑encoded TLS root CA certificates. This flag can be specified multiple times if needed.

- **`-config`**  
  Path to a YAML configuration file (optional).

### Environment Variables

You can also use environment variables with the `VALKEY_` prefix. For example:

- `VALKEY_ADDR` – To set the discovery address.

## Configuration

The client accepts a YAML configuration file if you prefer not to use command‑line flags. Simply pass the configuration file path using the `-config` flag. Environment variables prefixed with `VALKEY_` are also supported to override or supplement configuration values.

## Deployment

This repository contains additional directories with deployment configurations:

- **Kubernetes:**  
  The [`kubernetes`](./kubernetes) folder includes configuration files to deploy the Valkey service in a Kubernetes cluster.

- **Terraform:**  
  The [`terraform`](./terraform) folder provides Terraform scripts for provisioning the necessary infrastructure.

Refer to the respective directories for detailed deployment instructions.

## Credits

- **valkey‑go:** Built on top of the [valkey‑go](https://github.com/valkey-io/valkey-go) client library.
- **ff Library:** Uses [ff](https://github.com/peterbourgon/ff) for robust command‑line flag parsing.
