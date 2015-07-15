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
# Install docker 1.6 (workaround for a bug (?) in 70-docker.sh)
#############################################

DOCKER_APT_REPO=https://get.docker.io/ubuntu
sudo curl https://get.docker.io/gpg | sudo apt-key add -
sudo sh -c "echo deb $DOCKER_APT_REPO docker main > /etc/apt/sources.list.d/docker.list"
sudo apt-get update
sudo apt-get install -y lxc-docker-1.6.2


#############################################
# Get nova-docker
#############################################

git clone https://github.com/ggiamarchi/nova-docker.git /opt/stack/nova-docker
(cd /opt/stack/nova-docker && git checkout devstack)
git clone --depth 1 https://git.openstack.org/openstack/nova /opt/stack/nova
cp /opt/stack/nova-docker/contrib/devstack/extras.d/70-docker.sh /opt/stack/devstack/extras.d/
cp /opt/stack/nova-docker/contrib/devstack/lib/nova_plugins/hypervisor-docker /opt/stack/devstack/lib/nova_plugins/


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
IMAGE_URLS=""
VIRT_DRIVER=docker
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
# Allow insecure private docker registry
#############################################

sudo sed -i -e 's/\(DOCKER_OPTS="[^"]*\).*/\1 --insecure-registry docker.openstack"/' /etc/default/docker

sudo service docker restart


#############################################
# Add docker image(s) in Glance
#############################################

add_docker_image() {
    image=${1}
    if [ $(glance image-list | grep "${image}" | wc -l) -eq 0 ] ; then
        sudo docker pull "${image}"
        sudo docker save "${image}" | \
            glance image-create --is-public=True --container-format=docker \
                                --disk-format=raw --name "${image}"
    fi
}

. /opt/stack/devstack/openrc admin admin

add_docker_image 'docker.openstack/cirros'

set +x
echo "### Success ###"
