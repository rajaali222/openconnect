#!/bin/bash

GL_VPN_PORT=$1

if [ "$GL_VPN_PORT" == ""  ]
then
	GL_VPN_PORT="443"
fi

function check_permissions(){
	[[ $EUID != 0 ]] && echo -e "You need to be root to run this script" && exit 1
}

function set_distro (){

	my_distro=$(cat /etc/os-release | grep -w ID | cut -d "=" -f 2)

	if [ "$my_distro" == "ubuntu" ]
	then
		DEBIAN_FRONTEND=noninteractive
		export DEBIAN_FRONTEND
		PACKAGE_CLEANUP="dpkg --configure -a"
		UPDATE="apt -yq update"
		UPGRADE="apt -yq upgrade"
		INSTALL="apt -yq --reinstall install "
		UNINSTALL="apt -y --purge remove "
		PREREQUISITES=" expect libmysqlclient20 mysql-client curl libcurl3-gnutls"
		PACKAGES=" iptables iptables-persistent ocserv gnutls-bin"
		RESET_IPTABLES=" ls"
		SAVE_IPTABLES='iptables-save ;netfilter-persistent save ;netfilter-persistent start ;rm -rf /etc/resolv.conf ; touch /etc/resolv.conf; echo "nameserver 8.8.8.8" >> /etc/resolv.conf; echo "nameserver 208.67.222.222" >> /etc/resolv.conf; echo "nameserver 208.67.220.220" >> /etc/resolv.conf; chattr +i /etc/resolv.conf'

	elif [ "$my_distro" == "\"centos\"" ]
	then
		PACKAGE_CLEANUP="echo test"
		UPDATE="yum update -y -q"
		UPGRADE="yum upgrade -y -q"
		INSTALL="yum install -y -q"
		UNINSTALL="yum remove -y "
		PREREQUISITES=" epel-release expect mysql mariadb-libs libatomic"
		PACKAGES=" iptables iptables-services gnutls gnutls-devel ocserv "
		RESET_IPTABLES=" systemctl stop firewalld; systemctl disable firewalld; iptables -F; rm -rf /etc/sysconfig/iptables; service iptables save "
		SAVE_IPTABLES=" systemctl stop firewalld; systemctl disable firewalld; systemctl enable iptables; service iptables save "

	else
		echo "Sorry, but your distro ($my_distro) is not supported yet"
		exit 1
	fi
}

function configure_ocserv(){
	cd /etc/ocserv/
	certtool --generate-privkey --outfile ca-key.pem
cat >ca.tmpl <<EOF
cn = "HY Annyconnect CA"
organization = "HUAYU"
serial = 1
expiration_days = 3650
ca
signing_key
cert_signing_key
crl_signing_key
EOF
	certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem
	certtool --generate-privkey --outfile server-key.pem
cat >server.tmpl <<EOF
cn = "HY Annyconnect CA"
organization = "HUAYU"
serial = 2
expiration_days = 3650
encryption_key
signing_key
tls_www_server
EOF
	certtool --generate-certificate --load-privkey server-key.pem \
	--load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem \
	--template server.tmpl --outfile server-cert.pem
	touch /etc/ocserv/ocpasswd
	chmod 0600 /etc/ocserv/ocpasswd
	systemctl disable ocserv
	systemctl stop ocserv
	if [ "$GL_VPN_PORT" != "443" ]
	then
		systemctl disable ocserv.socket
		systemctl stop ocserv.socket
		sed -i "s/\(.*\)\(443\)/\1$GL_VPN_PORT/" /lib/systemd/system/ocserv.socket
		systemctl enable ocserv.socket
		systemctl start ocserv.socket
	fi
}

function enable_forwarding() {

	ipv4_fwd_enabled=$(grep ip_forward /etc/sysctl.conf | grep ipv4 | grep -v "#" -c)
	if [ $ipv4_fwd_enabled -eq 0 ]
	then
		echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
	fi

	sysctl -p
	eval $RESET_IPTABLES
	iptables -t nat -A POSTROUTING -j MASQUERADE
	eval $SAVE_IPTABLES
}

function install_prerequisites() {
	eval $INSTALL $PREREQUISITES
}

function install_packages() {
	eval $INSTALL $PACKAGES
}

function cleanup_previous_install () {
	eval $PACKAGE_CLEANUP
	eval $UNINSTALL ocserv
	rm -rf /etc/ocserv
}

function update_and_upgrade () {
	eval $UPDATE
	#eval $UPGRADE
}

function install_ocserv() {

	check_permissions

	set_distro

	update_and_upgrade

	cleanup_previous_install

	install_prerequisites

	install_packages

	enable_forwarding

	configure_ocserv
}

install_ocserv
