#!/bin/bash

docker pull ubuntu
docker rm -f $(docker ps -a -q)
docker run --privileged --network host --device=/dev/kvm -v /home/developer:/home/developer -itd ubuntu
docker start $(docker ps -a -q)
docker attach $(docker ps -a -q)