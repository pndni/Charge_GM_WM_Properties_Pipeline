#!/bin/bash
# Flatten data
#    Flatten a tsv like file
#    All fields are deliminated with whitespace (default awk)
#    so advanced tsv features like quoting are not supported
   
#    If stdin is
   
#       col1 col2
#    row1 v11 v12
#    row2 v21 v22
#    row3 v31 v32
   
#    then the output is
   
#    row1_col1       row1_col2       row2_col1       row2_col2       row3_col1       row3_col2
#    v11     v12     v21     v22     v31     v32
   
#    All field separaters for input and output are default awk
#    the charactering combining row and column names (default "_") can be changed with
#    the "-n" flag

# #+NAME: flatten

set -e
set -u
\unalias -a

namesep="_"

while getopts "n:" option
do
    case $option in
	n) namesep=$OPTARG
	;;
    esac
done

awk -v namesep=$namesep \
    'BEGIN {outind=0}
     NR == 1 {for (i=1;i<=NF;i++) {colnames[i] = $(i)}}
     NR > 1 { for (col in colnames) {out[outind] = $(col + 1); outnames[outind] = $1 namesep colnames[col]; outind++}}
     END {for (i=0;i<outind-1;i++) {printf "%s\t", outnames[i]};
          printf "%s", outnames[outind - 1];
	  printf "\n";
	  for (i=0;i<outind-1;i++) {printf "%s\t", out[i]};
	  printf "%s", out[outind - 1];
	  printf "\n"}' <&0
