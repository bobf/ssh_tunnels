# SshTunnels

Interactive _SSH_ tunnel management.

## Installation

```bash
gem install ssh_tunnels
```

## Usage

```bash
ssh_tunnels -c config.yml
```

## Configuration

```yaml
# config.yml

gateway:
  host: gateway.example.com
  port: 22

tunnels:
  my_host:
    local: 1234
    host: my.host.example.com
    remote: 4567
  other_host:
    local: 1111
    host: other.host.example.com
    remote: 5555
```

## Contributing

Pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
