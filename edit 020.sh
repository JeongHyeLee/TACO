#!/bin/bash

set -ex
export PATH=$PATH:/usr/local/bin
cd ~/
mkdir -p ~/apps
TACO_KUBESPRAY_DIR=~/apps/taco-kubespray
if [ -d $TACO_KUBESPRAY_DIR ]; then
  rm -rf $TACO_KUBESPRAY_DIR
fi
UPSTREAM_KUBESPRAY_DIR=~/apps/upstream-kubespray
if [ -d $UPSTREAM_KUBESPRAY_DIR ]; then
  rm -rf $UPSTREAM_KUBESPRAY_DIR
fi
KUBESPRAY_DIR=~/apps/kubespray
if [ -d $KUBESPRAY_DIR ]; then
  rm -rf $KUBESPRAY_DIR
fi
CACHE_FILE=/tmp/taco-aio
if [ -f $CACHE_FILE ]; then
  rm -f $CACHE_FILE
fi

cd ~/apps
git clone https://github.com/kubernetes-incubator/kubespray.git upstream-kubespray && cd upstream-kubespray
pip install -r requirements.txt

# need to enter the hostname and ip address formed "<hostname> <ip=0.0.0.0>"
# to enter the information 1) the user have to put it 2) get the info using "sed"
# I have to choose the way to do this 
# Furthermore this version of TACO will be installed for multi-node, So we need that info
# what is the master , what is the node, how the cluster dependency set... etc.
echo """[enter the hostname that you want to use as master and worker node respectively]
how many nodes you want?"""

read number

for i in number
do 
  echo "hostname:"
  read hostname
  name=$(echo $hostname | awk '{print $1}') >/test/test.txt
  ipad=$(echo $hostname | sed 's/ip=//' | awk '{print $2}') >>/test/test.txt
done 




echo """$hostname  

[kube-master]
taco-aio

[etcd]
taco-aio

[kube-node]
taco-aio

[k8s-cluster:children]
kube-node
kube-master""" > /inventory/local/host.ini

ansible-playbook -u root -b -i ~/apps/upstream-kubespray/inventory/host.ini ~/apps/upstream-kubespray/cluster.yml

curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | cat > /tmp/helm_script.sh \
&& chmod 755 /tmp/helm_script.sh && /tmp/helm_script.sh --version v2.9.1

helm init --upgrade

# compute-node로 가야 할 곳에 nameserver fmf 8.8.8.8로만 맞춰주는것도 해야한다. 물론 controller server도 건들여야하고 
echo """
nameserver 8.8.8.8

search openstack.svc.cluster.local svc.cluster.local cluster.local
options ndots:5""" > /etc/resolv.conf

set -e

# This code is just checkout that the kubernetes installation is correct 

# From Kolla-Kubernetes, orginal authors Kevin Fox & Serguei Bezverkhi
# Default wait timeout is 600 seconds
end=$(expr $(date +%s) + 600)
while true; do
    kubectl get pods --namespace=kube-system -o json | jq -r \
        '.items[].status.phase' | grep Pending > /dev/null && \
        PENDING=True || PENDING=False
    query='.items[]|select(.status.phase=="Running")'
    query="$query|.status.containerStatuses[].ready"
    kubectl get pods --namespace=kube-system -o json | jq -r "$query" | \
        grep false > /dev/null && READY="False" || READY="True"
    kubectl get jobs -o json --namespace=kube-system | jq -r \
        '.items[] | .spec.completions == .status.succeeded' | \
        grep false > /dev/null && JOBR="False" || JOBR="True"
    [ $PENDING == "False" -a $READY == "True" -a $JOBR == "True" ] && \
        break || true
    sleep 5
    now=$(date +%s)
    [ $now -gt $end ] && echo containers failed to start. && \
        kubectl get pods --namespace kube-system -o wide && exit -1
done