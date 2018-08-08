#!/bin/bash

set -ex
mkdir test

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

