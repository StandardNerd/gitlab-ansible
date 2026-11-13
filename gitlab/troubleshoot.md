● Bash(ip route; arp -n; docker ps)
  ⎿  default via 192.168.4.1 dev enp1s0 proto static
            172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
            192.168.4.0/24 dev enp1s0 proto kernel scope link src 192.168.4.121
            bash: line 1: arp: command not found
            permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
● Bash(ip neigh)
  ⎿  <output +2 lines>
            192.168.4.117 dev enp1s0 lladdr a2:84:9d:b3:4e:bb STALE
            192.168.4.1 dev enp1s0 lladdr 7a:c4:d5:0d:1e:35 REACHABLE
            192.168.4.6 dev enp1s0 lladdr d2:29:f9:69:7c:6d REACHABLE
            192.168.4.122 dev enp1s0 lladdr 96:d5:61:27:15:00 STALE
            192.168.4.120 dev enp1s0 lladdr f6:d1:f9:fe:0b:2c STALE
            192.168.4.21 dev enp1s0 lladdr ce:79:bf:17:f1:cc STALE
            192.168.4.114 dev enp1s0 lladdr 9a:47:0d:aa:55:e0 STALE
            192.168.4.112 dev enp1s0 lladdr f6:4c:67:11:80:91 STALE
            192.168.4.115 dev enp1s0 lladdr 4e:21:50:aa:40:43 STALE
            192.168.4.8 dev enp1s0 lladdr 36:48:6b:4c:76:a2 STALE
● Bash(ping -c 2 -W 1 192.168.4.112)
  ⎿  PING 192.168.4.112 (192.168.4.112) 56(84) bytes of data.
            64 bytes from 192.168.4.112: icmp_seq=1 ttl=64 time=0.345 ms
            64 bytes from 192.168.4.112: icmp_seq=2 ttl=64 time=0.556 ms

            --- 192.168.4.112 ping statistics ---
            2 packets transmitted, 2 received, 0% packet loss, time 1041ms
            rtt min/avg/max/mdev = 0.345/0.450/0.556/0.105 ms
● Bash(nc -zv -w 2 192.168.4.112 22) (ctrl+o to collapse)

Command
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Requesting permission for:
   nc -zv -w 2 192.168.4.112 22


---

gitlab runner


  curl -k -s -H "PRIVATE-TOKEN: admin_token" https://192.168.4.112/api/v4/application/settings | jq 'keys' 2>/dev/null || curl -k -s
-H "PRIVATE-TOKEN: admin_token" https://192.168.4.112/api/v4/application/settings | grep -i runner