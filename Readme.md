# Notes

* Run the container with TTY (-t) flag to enable proper stdout log flushing

`docker run --rm --cap-add NET_ADMIN --read-only --tmpfs /var/run -t (docker build -q .)`


Possible required sysctl settings:
sudo sysctl net.ipv4.ip_forward=1
sudo sysctl net.ipv6.conf.all.forwarding=1
sudo sysctl net.ipv6.conf.all.proxy_ndp=1
sudo iptables -A FORWARD -j ACCEPT


## TODO CI

Validate output of `swanctl --list-algs`
