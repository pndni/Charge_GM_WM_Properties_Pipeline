#!/bin/bash
# Combine data script
#    reads stdin as a list of subjects and then combines the stats
#    from $subject/stats_out/$1.txt into $1_combined.txt, creating
#    $subject/stats_out/$1_flat.txt as an intermediary


set -e
set -u
\unalias -a

while read subject
do
     sed -n '/^[^#]/p' < $subject/stats_out/$1.txt | ./charge_flatten.sh > $subject/stats_out/$1_flat.txt 
     echo $subject $subject/stats_out/$1_flat.txt
done | ./charge_combine_flattened.sh > $1_combined.txt
