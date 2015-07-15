#!/bin/bash

set -ex

#
# The network interface that will be used by OpenStack services.
# The IP address of this interface will be used in the service
# catalog for admin and internal endpoints.
#
net_interface=eth0

#
# The IP address to use in the service catalog for public endpoints.
# If not provided, publicURL will be the same as internalURL.
#
ip_pub=


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

cat > /opt/stack/devstack/local.conf <<EOF
[[local|localrc]]

ADMIN_PASSWORD=password
MYSQL_PASSWORD=password
RABBIT_PASSWORD=password
SERVICE_PASSWORD=password
SERVICE_TOKEN=password

LOGFILE=/opt/stack/logs/stack.sh.log
VERBOSE=True
LOG_COLOR=True
SCREEN_LOGDIR=/opt/stack/logs
HOST_IP=0.0.0.0
RECLONE=False
GIT_BASE=https://git.openstack.org
IP_VERSION=4
MULTI_HOST=True

disable_service n-net n-cpu tempest 
enable_service q-svc q-agt q-dhcp q-l3 q-meta q-fwaas q-lbaas

[[post-config|/etc/glance/glance-api.conf]]
[DEFAULT]
container_formats=ami,ari,aki,bare,ovf,ova,docker
EOF

ip=$(ifconfig ${net_interface} | grep 'inet addr:' | sed -e "s/ *inet addr:\([^ ]*\).*/\1/")
sed -i "s/HOST_IP=.*/HOST_IP=${ip}/" /opt/stack/devstack/local.conf


#############################################
# Source admin creds in user .profile
#############################################

echo '
. /opt/stack/devstack/openrc admin admin' >> ~/.profile


#############################################
# Run Devstack
#############################################

( cd /opt/stack/devstack && ./stack.sh )


#############################################
# Service catalog configuration
#############################################

ip_pub=${ip_pub:-$ip}

echo "
export OS_ENDPOINT_TYPE=internalURL" >> /opt/stack/devstack/openrc

. /opt/stack/devstack/openrc admin admin

function endpoint_create() {
    #
    # endpoint_create SERVICE_NAME PUB_PORT ADMIN_PORT INTERNAL_PORT RESOURCE
    #
    openstack endpoint create                                                    \
                       --region        RegionOne                                 \
                       --publicurl     http://${ip_pub}:${2}${5}                 \
                       --adminurl      http://${ip}:${3}${5}                     \
                       --internalurl   http://${ip}:${4}${5}                     \
                       $(openstack service show ${1} -f value -c id 2>/dev/null) \
                       2>/dev/null
}

for e in $(openstack endpoint list | grep -v identity | grep -e '^| [a-f0-9]' | awk '{print $2}') ; do
    openstack endpoint delete ${e}
done

openstack endpoint delete $(openstack endpoint list -c ID -f csv --quote none | tail -1)

keystone --os-token    $(openstack token issue -f value -c id 2>/dev/null) \
         --os-endpoint http://127.0.0.1:35357/v2.0                         \
         endpoint-create                                                   \
             --service     keystone                                        \
             --adminurl    http://${ip}:35357/v2.0                         \
             --internalurl http://${ip}:5000/v2.0                          \
             --publicurl   http://${ip_pub}:5000/v2.0                      \
             --region      RegionOne

endpoint_create ec2       8773  8773 8733
endpoint_create glance    9292  9292 9292
endpoint_create cinderv2  8776  8776 8776 '/v2/$(tenant_id)s'
endpoint_create neutron   9696  9696 9696
endpoint_create nova      8774  8774 8774 '/v2/$(tenant_id)s'
endpoint_create novav21   8774  8774 8774 '/v2.1/$(tenant_id)s'
endpoint_create cinder    8776  8776 8776 '/v1/$(tenant_id)s'


#############################################
# Customization
#############################################

#
# NAT for floating IP network
#
sudo iptables -t nat -A POSTROUTING -s 172.24.4.0/24 -o eth0 -j MASQUERADE

. /opt/stack/devstack/openrc demo demo

#
# Allow all in default security group
#
for r in $(neutron security-group-rule-list | grep -e '^| [a-f0-9]' | awk '{print $2}') ; do
    neutron security-group-rule-delete ${r}
done

for p in tcp udp icmp ; do
    for d in egress ingress ; do
        neutron security-group-rule-create --protocol ${p} --direction ${d} default
    done
done

#
# Create keypair for demo user
#
nova keypair-add devstack > ~/key-demo
chmod 400 ~/key-demo

export OS_USERNAME=admin

. /opt/stack/devstack/openrc admin admin

#
# Create keypair for demo admin
#
nova keypair-add devstack > ~/key-admin
chmod 400 ~/key-admin

#
# Make m1.small smaller
#
small_flavor_id=$(nova flavor-delete m1.small | grep -e '^| [a-f0-9]' | awk '{print $2}')
nova flavor-create --is-public True m1.small ${small_flavor_id} 1024 10 1

set +x
echo "### Success ###"
