module github.com/volsu/pc-management-exporter

go 1.25

require (
	github.com/prometheus-community/windows_exporter v0.30.0
	github.com/prometheus/client_golang v1.23.2
	github.com/prometheus/common v0.67.4
	github.com/prometheus/node_exporter v1.8.2
)

require (
	cyphar.com/go-pathrs v0.2.1 // indirect
	github.com/alecthomas/kingpin/v2 v2.4.0 // indirect
	github.com/alecthomas/units v0.0.0-20240927000941-0f3dac36c52b // indirect
	github.com/beevik/ntp v1.5.0 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/bmatcuk/doublestar/v4 v4.9.1 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/coreos/go-systemd/v22 v22.6.0 // indirect
	github.com/cyphar/filepath-securejoin v0.6.0 // indirect
	github.com/dennwc/btrfs v0.0.0-20241002142654-12ae127e0bf6 // indirect
	github.com/dennwc/ioctl v1.0.0 // indirect
	github.com/dimchansky/utfbom v1.1.1 // indirect
	github.com/ema/qdisc v1.0.0 // indirect
	github.com/go-ole/go-ole v1.3.0 // indirect
	github.com/godbus/dbus/v5 v5.1.0 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	github.com/hashicorp/go-envparse v0.1.0 // indirect
	github.com/hodgesds/perf-utils v0.7.0 // indirect
	github.com/illumos/go-kstat v0.0.0-20210513183136-173c9b0a9973 // indirect
	github.com/jsimonetti/rtnetlink/v2 v2.1.0 // indirect
	github.com/kr/text v0.2.0 // indirect
	github.com/lufia/iostat v1.2.1 // indirect
	github.com/mattn/go-xmlrpc v0.0.3 // indirect
	github.com/mdlayher/ethtool v0.5.0 // indirect
	github.com/mdlayher/genetlink v1.3.2 // indirect
	github.com/mdlayher/netlink v1.8.0 // indirect
	github.com/mdlayher/socket v0.5.1 // indirect
	github.com/mdlayher/wifi v0.7.0 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/opencontainers/selinux v1.13.0 // indirect
	github.com/power-devops/perfstat v0.0.0-20240221224432-82ca36839d55 // indirect
	github.com/prometheus-community/go-runit v0.1.0 // indirect
	github.com/prometheus/client_model v0.6.2 // indirect
	github.com/prometheus/procfs v0.19.2 // indirect
	github.com/safchain/ethtool v0.6.2 // indirect
	github.com/xhit/go-str2duration/v2 v2.1.0 // indirect
	go.uber.org/atomic v1.7.0 // indirect
	go.uber.org/multierr v1.6.0 // indirect
	go.yaml.in/yaml/v2 v2.4.3 // indirect
	go.yaml.in/yaml/v3 v3.0.4 // indirect
	golang.org/x/crypto v0.45.0 // indirect
	golang.org/x/exp v0.0.0-20250911091902-df9299821621 // indirect
	golang.org/x/net v0.47.0 // indirect
	golang.org/x/sync v0.18.0 // indirect
	golang.org/x/sys v0.38.0 // indirect
	google.golang.org/protobuf v1.36.10 // indirect
	howett.net/plist v1.0.1 // indirect
)

// Use local cloned repositories
replace (
	github.com/prometheus-community/windows_exporter => ./windows
	github.com/prometheus/node_exporter => ./unix
)
