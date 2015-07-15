#!/bin/bash

set -x

wget -qO- https://get.docker.com/ | sh
sudo docker run -d -p 80:5000 --restart=always --name registry registry:2

sudo docker pull cirros
sudo docker tag cirros localhost/cirros
sudo docker push localhost/cirros
