#!/bin/bash
# Combine flattened data
#    Combine several 2 line files of the form:
  
#    column names
#    values
  
#    The first line of each file must be identical (this is checked for)
  
#    Each line of stdin must have the form
  
#    rowname1 fname1
#    rowname2 fname2
#    ...
  
#    where filename is a 2 line file as described above and rowname
#    is the name that will appear in the output
  
#    Output is
  
#    column names
#    rowname1\tvalues1
#    rowname2\tvalues2
  
#    where values1 is the values line from fname1, etc

# #+NAME: combine_flattened

set -e
set -u
\unalias -a

topref=
delim="\t"
while read rowname fname
do
    if [ $(wc -l < $fname) != 2 ]
    then
	>&2 echo "$fname does not have exactly 2 lines. Exiting"
	exit 1
    fi
    top=$(head -n 1 $fname)
    if [ -z "$topref" ];
    then 
	topref="$top"
	echo -e "ID$delim$topref"
    else
	if [ "$top" != "$topref" ]
	then
	    >&2 echo "first line of $fname does not match. Exiting"
	    exit 2
	fi
    fi
    echo -e "$rowname\t$(tail -n 1 $fname)"
done
