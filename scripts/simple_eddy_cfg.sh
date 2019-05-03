#!/bin/bash

set -e
set -u

dir=$1
nvol=$2
acqp=$3
index=$4

# from https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/eddy/UsersGuide#A--acqp
indx=""
for ((i=0; i<$nvol; i+=1))
do
    indx="$indx 1"
done
echo $indx > $index

declare -A map
map["i"]=0
map["j"]=1
map["k"]=2
ind=${map["$dir"]}

arr=( 0 0 0 0.05 )
arr[$ind]=1

echo "${arr[*]}" > $acqp
