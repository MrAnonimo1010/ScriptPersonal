#!/bin/bash

# OpenVPN road warrior installer for Debian, Ubuntu and CentOS

# This script will work on Debian, Ubuntu, CentOS and probably other distros

# of the same families, although no support is offered for them. It isn't

# bulletproof but it will probably work if you simply want to setup a VPN on

# your Debian/Ubuntu/CentOS box. It has been designed to be as unobtrusive and

# universal as possible.

# Detect Debian users running the script with "sh" instead of bash

if readlink /proc/$$/exe | grep -qs "dash"; then

	echo "Este script debe ejecutarse con el intérprete bash, no con el intérprete sh."

	exit 1

fi

if [[ "$EUID" -ne 0 ]]; then

	echo "Lo siento, usted necesita ejecutar este script como root."

	exit 2

fi

if [[ ! -e /dev/net/tun ]]; then

	echo "El adaptador TUN no está disponible. Póngase en contacto con el soporte de su servicio de alojamiento."

	exit 3

fi

if grep -qs "CentOS release 5" "/etc/redhat-release"; then

	echo "CentOS 5 está desactualizado, utilice un sistema más reciente."

	exit 4

fi

if [[ -e /etc/debian_version ]]; then

	OS=debian

	GROUPNAME=nogroup

	RCLOCAL='/etc/rc.local'

elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then

	OS=centos

	GROUPNAME=nobody

	RCLOCAL='/etc/rc.d/rc.local'

	# Needed for CentOS 7

	chmod +x /etc/rc.d/rc.local

else

	echo "Parece que usted no está ejecutando este script en el sistema Debian, Ubuntu o CentOS."

	exit 5

fi

newclient () {

	# Generates the custom client.ovpn

	cp /etc/openvpn/client-common.txt ~/$1.ovpn

	echo "<ca>" >> ~/$1.ovpn

	cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn

	echo "</ca>" >> ~/$1.ovpn

	echo "<cert>" >> ~/$1.ovpn

	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn

	echo "</cert>" >> ~/$1.ovpn

	echo "<key>" >> ~/$1.ovpn

	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn

	echo "</key>" >> ~/$1.ovpn

	echo "<tls-auth>" >> ~/$1.ovpn

	cat /etc/openvpn/ta.key >> ~/$1.ovpn

	echo "</tls-auth>" >> ~/$1.ovpn

}

# Try to get our IP from the system and fallback to the Internet.

# I do this to make the script compatible with NATed servers (lowendspirit.com)

# and to avoid getting an IPv6.

IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)

if [[ "$IP" = "" ]]; then

		IP=$(wget -qO- ipv4.icanhazip.com)

fi

if [[ -e /etc/openvpn/server.conf ]]; then

	while :

	do

	clear

		tput setaf 3 ; echo "Parece que el OpenVPN ya está instalado." ; tput sgr0

		echo ""

		echo "Qué quieres hacer?"

		echo ""

		tput setaf 6

		echo " 1) Agregar un certificado a un nuevo usuario"

		echo " 2) Quitar el certificado de un usuario existente"

		echo " 3) Desinstalar OpenVPN"

		echo " 4) Salir"

		tput sgr0

		echo ""

		read -p "Selecciona una opcion [1-4]: " option

		case $option in

			1) 

			echo ""

			echo "Dígame un nombre para crear el certificado del usuario."

			echo "Por favor, utilice sólo una sola palabra, sin caracteres especiales."

			echo ""

			read -p "Nombre de usuario: " -e -i cliente CLIENT

			cd /etc/openvpn/easy-rsa/

			./easyrsa build-client-full $CLIENT nopass

			# Generates the custom client.ovpn

			echo ""

			newclient "$CLIENT"

			echo ""

			echo " el usuario $CLIENT se ha agregado, certificado disponible en ~/$CLIENT.ovpn"

			exit

			;;

			2)

			# This option could be documented a bit better and maybe even be simplimplified

			# ...but what can I say, I want some sleep too

			NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")

			if [[ "$NUMBEROFCLIENTS" = '0' ]]; then

				echo ""

				echo "No tienes ningún usuario en OpenVPN!"

				exit 6

			fi

			echo ""

			echo "Seleccione el certificado del usuario que desea eliminar."

			tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '

			if [[ "$NUMBEROFCLIENTS" = '1' ]]; then

				read -p "Seleccioné un usuário [1]: " CLIENTNUMBER

			else

				read -p "Seleccioné un usuário [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER

			fi

			CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)

			cd /etc/openvpn/easy-rsa/

			./easyrsa --batch revoke $CLIENT

			./easyrsa gen-crl

			rm -rf pki/reqs/$CLIENT.req

			rm -rf pki/private/$CLIENT.key

			rm -rf pki/issued/$CLIENT.crt

			rm -rf /etc/openvpn/crl.pem

			cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem

			# CRL is read with each client connection, when OpenVPN is dropped to nobody

			chown nobody:$GROUPNAME /etc/openvpn/crl.pem

			echo ""

			echo "Certificado para el usuario $ CLIENT quitado"

			exit

			;;

			3) 

			echo ""

			read -p "Usted realmente quiere desinstalar el OpenVPN? [s/n]: " -e -i n REMOVE

			if [[ "$REMOVE" = 's' ]]; then

				PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)

				if pgrep firewalld; then

					# Using both permanent and not permanent rules to avoid a firewalld reload.

					firewall-cmd --zone=public --remove-port=$PORT/tcp

					firewall-cmd --zone=trusted --remove-source=10.8.0.0/24

					firewall-cmd --permanent --zone=public --remove-port=$PORT/tcp

					firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24

				fi

				if iptables -L -n | grep -qE 'REJECT|DROP'; then

					sed -i "/iptables -I INPUT -p tcp --dport $PORT -j ACCEPT/d" $RCLOCAL

					sed -i "/iptables -I FORWARD -s 10.8.0.0\/24 -j ACCEPT/d" $RCLOCAL

					sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL

				fi

				sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0\/24 -j SNAT --to /d' $RCLOCAL

				if hash sestatus 2>/dev/null; then

					if sestatus | grep "Current mode" | grep -qs "enforcing"; then

						if [[ "$PORT" != '1194' ]]; then

							semanage port -d -t openvpn_port_t -p tcp $PORT

						fi

					fi

				fi

				if [[ "$OS" = 'debian' ]]; then

					apt-get remove --purge -y openvpn openvpn-blacklist

				else

					yum remove openvpn -y

				fi

				rm -rf /etc/openvpn

				rm -rf /usr/share/doc/openvpn*

				echo ""

				echo "OpenVPN se ha desinstalado!"

			else

				echo ""

				echo "Se ha cancelado la desinstalación de OpenVPN!"

			fi

			exit

			;;

			4) exit;;

		esac

	done

else

	clear

	tput setaf 3 ; echo "Bienvenido al script instalador de OpenVPN" ; tput sgr0

	tput setaf 6 ; echo "Hecho y adaptado para el protocolo TCP por @Mr_Anonimo"

	echo "Script original: https://github.com/Nyr/openvpn-install" ; tput sgr0

	echo ""

	# OpenVPN setup and first user creation

	echo "Necesito preguntarle algunas cosas antes de empezar a configurar."

	echo "Para confirmar la respuesta predeterminada basta con pulsar la tecla ENTER"

	echo ""

	echo "Primero necesito saber la dirección IPv4 de la interfaz de red externa de su servidor."

	read -p "Endereço IP: " -e -i $IP IP

	echo ""

	echo "En qué puerto desea ejecutar OpenVPN?"

	read -p "Porta: " -e -i 8053 PORT

	echo ""

	echo "Qué DNS desea utilizar con esta VPN?"

	echo ""

	echo " 1) DNS Personalizado del Sistema"

	echo " 2) Google"

	echo " 3) OpenDNS"

	echo " 4) NTT"

	echo " 5) Hurricane Electric"

	echo " 6) Verisign"

	echo ""

	read -p "DNS [1-6]: " -e -i 6 DNS

	echo ""

	echo "Listo, ahora dime un nombre para el certificado del usuario."

	echo "Por favor, utilice sólo una sola palabra, sin caracteres especiales."

	echo ""

	read -p "Nombre de usuario: " -e -i cliente CLIENT

	echo ""

	echo "Cierto, eso es todo lo que necesitaba. Ya estamos listos para configurar su servidor OpenVPN"

	echo ""

	read -n1 -r -p "Presione cualquier tecla para continuar..."

		if [[ "$OS" = 'debian' ]]; then

		apt-get update

		apt-get install openvpn iptables openssl ca-certificates -y

	else

		# Else, the distro is CentOS

		yum install epel-release -y

		yum install openvpn iptables openssl wget ca-certificates -y

	fi

	# An old version of easy-rsa was available by default in some openvpn packages

	if [[ -d /etc/openvpn/easy-rsa/ ]]; then

		rm -rf /etc/openvpn/easy-rsa/

	fi

	# Get easy-rsa

	wget -O ~/EasyRSA-3.0.1.tgz https://github.com/OpenVPN/easy-rsa/releases/download/3.0.1/EasyRSA-3.0.1.tgz

	tar xzf ~/EasyRSA-3.0.1.tgz -C ~/

	mv ~/EasyRSA-3.0.1/ /etc/openvpn/

	mv /etc/openvpn/EasyRSA-3.0.1/ /etc/openvpn/easy-rsa/

	chown -R root:root /etc/openvpn/easy-rsa/

	rm -rf ~/EasyRSA-3.0.1.tgz

	cd /etc/openvpn/easy-rsa/

	# Create the PKI, set up the CA, the DH params and the server + client certificates

	./easyrsa init-pki

	./easyrsa --batch build-ca nopass

	./easyrsa gen-dh

	./easyrsa build-server-full server nopass

	./easyrsa build-client-full $CLIENT nopass

	./easyrsa gen-crl

	# Move the stuff we need

	cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/server.crt pki/private/server.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn

	# CRL is read with each client connection, when OpenVPN is dropped to nobody

	chown nobody:$GROUPNAME /etc/openvpn/crl.pem

	# Generate key for tls-auth

	openvpn --genkey --secret /etc/openvpn/ta.key

	# Generate server.conf

	echo "port $PORT

proto tcp-server

dev tun

sndbuf 0

rcvbuf 0

ca ca.crt

cert server.crt

key server.key

dh dh.pem

tls-auth ta.key 0

topology subnet

server 10.8.0.0 255.255.255.0

ifconfig-pool-persist ipp.txt" > /etc/openvpn/server.conf

	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf

	# DNS

	case $DNS in

		1) 

		# Obtain the resolvers from resolv.conf and use them for OpenVPN

		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do

			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf

		done

		;;

		2) 

		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server.conf

		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server.conf

		;;

		3)

		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server.conf

		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server.conf

		;;

		4) 

		echo 'push "dhcp-option DNS 129.250.35.250"' >> /etc/openvpn/server.conf

		echo 'push "dhcp-option DNS 129.250.35.251"' >> /etc/openvpn/server.conf

		;;

		5) 

		echo 'push "dhcp-option DNS 74.82.42.42"' >> /etc/openvpn/server.conf

		;;

		6) 

		echo 'push "dhcp-option DNS 64.6.64.6"' >> /etc/openvpn/server.conf

		echo 'push "dhcp-option DNS 64.6.65.6"' >> /etc/openvpn/server.conf

		;;

	esac

	echo "keepalive 10 120

cipher AES-128-CBC

comp-lzo no

user nobody

group $GROUPNAME

persist-key

persist-tun

status openvpn-status.log

verb 3

crl-verify crl.pem" >> /etc/openvpn/server.conf

	# Enable net.ipv4.ip_forward for the system

	sed -i '/\<net.ipv4.ip_forward\>/c\net.ipv4.ip_forward=1' /etc/sysctl.conf

	if ! grep -q "\<net.ipv4.ip_forward\>" /etc/sysctl.conf; then

		echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

	fi

	# Avoid an unneeded reboot

	echo 1 > /proc/sys/net/ipv4/ip_forward

	# Set NAT for the VPN subnet

	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP

	sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL

	if pgrep firewalld; then

		# We don't use --add-service=openvpn because that would only work with

		# the default port. Using both permanent and not permanent rules to

		# avoid a firewalld reload.

		firewall-cmd --zone=public --add-port=$PORT/udp

		firewall-cmd --zone=trusted --add-source=10.8.0.0/24

		firewall-cmd --permanent --zone=public --add-port=$PORT/udp

		firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24

	fi

	if iptables -L -n | grep -qE 'REJECT|DROP'; then

		# If iptables has at least one REJECT rule, we asume this is needed.

		# Not the best approach but I can't think of other and this shouldn't

		# cause problems.

		iptables -I INPUT -p tcp --dport $PORT -j ACCEPT

		iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT

		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

		sed -i "1 a\iptables -I INPUT -p tcp --dport $PORT -j ACCEPT" $RCLOCAL

		sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL

		sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL

	fi

	# If SELinux is enabled and a custom port was selected, we need this

	if hash sestatus 2>/dev/null; then

		if sestatus | grep "Current mode" | grep -qs "enforcing"; then

			if [[ "$PORT" != '1194' ]]; then

				# semanage isn't available in CentOS 6 by default

				if ! hash semanage 2>/dev/null; then

					yum install policycoreutils-python -y

				fi

				semanage port -a -t openvpn_port_t -p tcp $PORT

			fi

		fi

	fi

	# And finally, restart OpenVPN

	if [[ "$OS" = 'debian' ]]; then

		# Little hack to check for systemd

		if pgrep systemd-journal; then

			systemctl restart openvpn@server.service

		else

			/etc/init.d/openvpn restart

		fi

	else

		if pgrep systemd-journal; then

			systemctl restart openvpn@server.service

			systemctl enable openvpn@server.service

		else

			service openvpn restart

			chkconfig openvpn on

		fi

	fi

	# Try to detect a NATed connection and ask about it to potential LowEndSpirit users

	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)

	if [[ "$IP" != "$EXTERNALIP" ]]; then

		echo ""

		echo "Parece que su servidor está detrás de un interfaz NAT!"

		echo ""

		echo "Si su servidor utiliza NAT (por ejemplo LowEndSpirit), Necesito saber la dirección IP externa."

		echo "Si no es el caso, sólo ignore esto y deje el próximo campo en blanco."

		read -p "IP Externo: " -e USEREXTERNALIP

		if [[ "$USEREXTERNALIP" != "" ]]; then

			IP=$USEREXTERNALIP

		fi

	fi

	# client-common.txt is created so we have a template to add further users later

	echo "client

dev tun

proto tcp-client

sndbuf 0

rcvbuf 0

remote $IP $PORT

resolv-retry infinite

nobind

persist-key

persist-tun

remote-cert-tls server

cipher AES-128-CBC

comp-lzo no

setenv opt block-outside-dns

key-direction 1

verb 3

" > /etc/openvpn/client-common.txt

	# Generates the custom client.ovpn

	newclient "$CLIENT"

	echo ""

	tput setaf 3 ; echo "Concluído!" ; tput sgr0

	echo ""

	echo "El certificado de usuario de $ CLIENT está disponible en ~ / $ CLIENT.ovpn"

	echo "Si desea agregar más usuarios, simplemente ejecute este script de nuevo."

	echo ""

fi
