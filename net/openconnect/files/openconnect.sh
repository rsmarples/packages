#!/bin/sh
. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_openconnect_init_config() {
	proto_config_add_string "server"
	proto_config_add_int "port"
	proto_config_add_string "username"
	proto_config_add_string "serverhash"
	proto_config_add_string "authgroup"
	proto_config_add_string "password"
	no_device=1
	available=1
}

proto_openconnect_setup() {
	local config="$1"

	json_get_vars server port username serverhash authgroup password vgroup

	grep -q tun /proc/modules || insmod tun

	logger -t openconnect "initializing..."
	serv_addr=
	for ip in $(resolveip -t 10 "$server"); do
		( proto_add_host_dependency "$config" "$ip" )
		serv_addr=1
	done
	[ -n "$serv_addr" ] || {
		logger -t openconnect "Could not resolve server address: '$server'"
		sleep 20
		proto_setup_failed "$config"
		exit 1
	}

	[ -n "$port" ] && port=":$port"

	cmdline="$server$port -i vpn-$config --non-inter --syslog --script /lib/netifd/vpnc-script"

	[ -f /etc/openconnect/ca-vpn-$config.pem ] && append cmdline "--cafile /etc/openconnect/ca-vpn-$config.pem"
	[ -f /etc/openconnect/user-cert-vpn-$config.pem ] && append cmdline "-c /etc/openconnect/user-cert-vpn-$config.pem"
	[ -f /etc/openconnect/user-key-vpn-$config.pem ] && append cmdline "--sslkey /etc/openconnect/user-key-vpn-$config.pem"
	[ -n "$serverhash" ] && append cmdline "--servercert=$serverhash"
	[ -n "$authgroup" ] && append cmdline "--authgroup $authgroup"
	[ -n "$username" ] && append cmdline "-u $username"
	[ -n "$password" ] && {
		umask 077
		pwfile="/var/run/openconnect-$config.passwd"
		echo "$password" > "$pwfile"
		append cmdline "--passwd-on-stdin"
	}

	proto_export INTERFACE="$config"
	logger -t openconnect "executing 'openconnect $cmdline'"

	if [ -f "$pwfile" ];then
		proto_run_command "$config" /usr/sbin/openconnect $cmdline <$pwfile
	else
		proto_run_command "$config" /usr/sbin/openconnect $cmdline
	fi
}

proto_openconnect_teardown() {
	pwfile="/var/run/openconnect-$config.passwd"

	rm -f $pwfile
	logger -t openconnect "bringing down openconnect"
	proto_kill_command "$config"
}

add_protocol openconnect
