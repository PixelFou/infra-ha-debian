#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        iif "lo" accept
        ct state established,related accept

        # HTTP depuis le réseau DMZ
        iifname "enp0s8" tcp dport 80 accept

        # SSH et rsync sur l'interface HA-SYNC uniquement
        iifname "enp0s10" tcp dport 22 accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}