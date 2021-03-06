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

### Edit ssh 
ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""

echo "[enter the hostname that you want to use as master and worker node and ip address respectively]"
read -p "****how many \"masters\" : " number

for i in $(seq $number); do
   read  -p "#${i} input master node's <hostname> <x.x.x.x> :" hostname ip_address
   master_array[${i}-1]=$hostname
   echo $hostname ip=$ip_address>>inventory/local/host.ini
   ssh-copy-id $hostname
done

read -p "****how many \"workers\" : " number
for i in $(seq $number); do
   read  -p "#${i} input worker node's <hostname> <x.x.x.x> :" hostname ip_address
   worker_array[${i}-1]=$hostname
   echo $hostname ip=$ip_address>>inventory/local/host.ini
   ssh-copy-id $hostname
done

# host.ini
echo "[kube-master]">>inventory/local/host.ini
for arr_item in ${master_array[*]}
do
  echo $arr_item >>inventory/local/host.ini
done

echo "[etcd]">>inventory/local/host.ini
for arr_item in ${master_array[*]}; do
  echo $arr_item >>inventory/local/host.ini
done

echo "[kube-node]">>inventory/local/host.ini
for arr_item in ${master_array[*]}; do
  echo $arr_item >>inventory/local/host.ini
done
for arr_item in ${worker_array[*]}; do
  echo $arr_item >>inventory/local/host.ini
done

echo """[k8s-cluster:children]
kube-node
kube-master""">>inventory/local/host.ini

echo "[controller-node]">>inventory/local/host.ini
for arr_item in ${master_array[*]}; do
  echo $arr_item >>inventory/local/host.ini
done

echo "[compute-node]">>inventory/local/host.ini
for arr_item in ${worker_array[*]}; do
  echo $arr_item >>inventory/local/host.ini
done

echo """[controller-node:vars]
node_labels={"openstack-control-plane":"enabled", "openvswitch":"enabled"}
[compute-node:vars]
node_labels={"openstack-compute-node":"enabled", "openvswitch":"enabled"}""" >>inventory/local/host.ini

ansible-playbook -u root -b -i ~/apps/upstream-kubespray/inventory/local/host.ini ~/apps/upstream-kubespray/cluster.yml

curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | cat > /tmp/helm_script.sh \
&& chmod 755 /tmp/helm_script.sh && /tmp/helm_script.sh --version v2.9.1

#helm init --upgrade

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
