#!/bin/bash

set -ex

#
# The network interface that will be used by OpenStack services.
# The IP address of this interface will be used in the service
# catalog for admin and internal endpoints.
#
net_interface=eth0


#############################################
# Get Devstack
#############################################

sudo apt-get update
sudo apt-get install -y git vim

sudo mkdir -p /opt/stack/devstack
sudo chown -R stack:stack /opt/stack

git clone https://git.openstack.org/openstack-dev/devstack.git /opt/stack/devstack


#############################################
# Write devstack configuration
#############################################

HOST_CTL_IP=ctrl.openstack

cat > /opt/stack/devstack/local.conf <<EOF
[[local|localrc]]
HOST_IP=0.0.0.0
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=password
MYSQL_PASSWORD=password
RABBIT_PASSWORD=password
SERVICE_PASSWORD=password
SERVICE_TOKEN=password
DATABASE_TYPE=mysql
SERVICE_HOST=$HOST_CTL_IP
MYSQL_HOST=$HOST_CTL_IP
RABBIT_HOST=$HOST_CTL_IP
CINDER_SERVICE_HOST=$HOST_CTL_IP
GLANCE_HOSTPORT=$HOST_CTL_IP:9292
Q_HOST=$HOST_CTL_IP
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$HOST_CTL_IP:6080/vnc_auto.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN

ENABLED_SERVICES=n-cpu,c-vol,n-novnc,n-cauth,neutron,q-agt
EOF

ip=$(ifconfig ${net_interface} | grep 'inet addr:' | sed -e "s/ *inet addr:\([^ ]*\).*/\1/")
sed -i "s/HOST_IP=.*/HOST_IP=${ip}/" /opt/stack/devstack/local.conf


#############################################
# Run Devstack
#############################################

( cd /opt/stack/devstack && ./stack.sh )
