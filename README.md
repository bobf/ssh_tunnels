# SshTunnels

Interactive _SSH_ tunnel management. Console UI powered by [ncurses](https://invisible-island.net/ncurses/).

![example](doc/demo.png)

## Installation

```bash
gem install ssh_tunnels
```

## Usage

```bash
ssh_tunnels -c config.yml
```

Alternatively, default to using `~/.ssh_tunnels.yml` for configuration:

```bash
ssh_tunnels
```

## Configuration

### Gateways

There are two ways to configure an SSH gateway. Both can be used together, but at least one must be defined:

1. Define a `default_gateway` section in your configuration file.
1. Define a `gateways` section in your conifguration file.

The `default_gateway` is a map containing these keys:

* `host`: hostname or IP address of gateway (required).
* `port`: SSH port on gateway (default: `22`).
* `user`: Username on gateway to connect with (default: `$USER`).

The `gateways` section is also a map, but each key represents a named gateway, and each gateway is configured using the same parameters as `default_gateway`.

Each named gateway can be referred to in the `gateway` field for each tunnel.

```yaml
# config.yml

default_gateway:
  host: gateway.example.com

gateways:
  aws:
    host: 111.111.111.111
    user: ubuntu
  azure:
    host: 222.222.222.222
    user: william
```

### Tunnels

The `tunnels` section is a map where each key represents a named tunnel. Each tunnel can be configured using the following parameters:

* `host`: The remote host to connect to from the gateway.
* `remote`: The remote port to use for forwarding.
* `local`: The local port to bind to (defaults to the `remote` port).
* `local_ip`: The local IP address to bind to (optional, defaults to the top-level `default_local_ip` if set, otherwise `127.0.0.1`). Equivalent to the `<local-ip>` component in `ssh -L <local-ip>:<local-port>:<remote-host>:<remote-port>`. Takes precedence over `default_local_ip`.

### Default local IP

The top-level `default_local_ip` option sets the local bind IP address used for all tunnels that do not specify their own `local_ip`:

```yaml
# config.yml

default_local_ip: 0.0.0.0
```

```yaml
# config.yml

default_gateway:
  host: gateway.example.com

gateways:
  aws:
    host: 111.111.111.111
    user: ubuntu

tunnels:
  my_host:
    local: 1234
    host: my.host.example.com
    remote: 4567
  other_host:
    gateway: aws
    local: 1111
    host: other.host.example.com
    remote: 5555
  bound_host:
    local_ip: 192.168.1.100
    local: 2222
    host: internal.host.example.com
    remote: 8080
```

## Live reload

The configuration file is checked once a second while the app is running. Saving a change updates the tunnel list in place, so there is no need to quit and reconnect:

* New tunnels appear and can be connected straight away.
* Tunnels that are disconnected take their new settings immediately.
* Tunnels that are connected keep running on their current settings. They are marked `config changed, reconnect to apply` and pick up the new settings when next disconnected.
* Tunnels deleted from the file are removed from the list if disconnected. If connected they stay listed, marked `removed from config`, until disconnected.
* An invalid or half-saved file is reported in the status line and leaves the current tunnels untouched until the next successful reload.

## Contributing

Pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
