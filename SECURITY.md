# Security Policy

## Threat model

NetICU is a network *measurement* tool. Its probes are HTTP(S) `HEAD` requests that carry no user data; responses are discarded and only timing is recorded. Two design decisions deserve explicit documentation:

### TLS certificate validation

- For targets entered as a **named host** (e.g. `google.com`), TLS certificates are validated with the **system's default validation** — no exceptions.
- For targets entered as a **raw IP address** (e.g. `1.1.1.1`), certificate validation is **bypassed**. Public CAs rarely issue certificates for bare IPs, so without this exception such targets would be unmeasurable over HTTPS. Since no data is sent or consumed, the impact of a man-in-the-middle on these probes is limited to falsified *timing*.

The implementation is `ProbeTrustDelegate` in `PingEngine.swift`, gated by `HostClassifier.isRawIPAddress` and covered by unit tests.

### Public-IP lookup

The dashboard can display your public IP. This requires asking a third-party service: `api.ipify.org`, `ifconfig.me`, or `icanhazip.com` (tried in that order). **Automatic polling is off by default** — these services are contacted only when you press the refresh button, or every 5 minutes if you enable auto-refresh in Settings. No other telemetry of any kind is sent anywhere.

### Proxy support

Per-monitor proxy settings route probes through a user-specified local SOCKS5/HTTP proxy. NetICU never configures, discovers, or modifies system proxies, and proxy credentials are not supported or stored.

## Reporting a vulnerability

If you find a security issue, please **do not open a public issue**. Email the maintainer instead: **soorira@gmail.com**. You should receive a response within a few days. Please include reproduction steps and the app version (`About → Version`).

## Supported versions

Only the latest release receives security fixes.
