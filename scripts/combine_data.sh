#!/bin/bash
# Combine data script
#    reads stdin as a list of subjects and then combines the stats
#    from $subject/stats_out/$1.txt into $1_combined.txt
#    also adds an errorflag and a warningflag column with the contents
#    of the errorflag/warningflag files


set -e
set -u
\unalias -a

flatten (){
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
    
    local namesep="_"
    
    while getopts "n:" option
    do
        case $option in
    	n) namesep=$OPTARG
    	;;
    	?) >&2 echo "unrecognized option"; exit 2
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
}

combine_flattened (){
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
    
    local topref=
    local delim="\t"
    local rowname
    local fname
    while read rowname fname
    do
        if [ $(wc -l < "$fname") != 2 ]
        then
    	    >&2 echo "$fname does not have exactly 2 lines. Exiting"
    	    exit 1
        fi
        top=$(head -n 1 "$fname")
        if [ -z "$topref" ];
        then 
    	    topref="$top"
    	    echo -e "ID$delim$topref"
        else
    	    if [ "$top" != "$topref" ]
    	    then
    	        >&2 echo "first line of $fname does not match. Exiting"
    	        exit 1
    	    fi
        fi
        echo -e "$rowname\t"$(tail -n 1 "$fname")
    done
}

tmpdir=$(mktemp -d)
while read subject
do
     if [ -e "$subject"/stats_out/${1}.txt ]
     then
         echo -e "errorflag\twarningflag" > $tmpdir/"${subject}"_${1}_flags.txt
         paste "$subject"/errorflag "$subject"/warningflag >> $tmpdir/"${subject}"_${1}_flags.txt
         sed -n '/^[^#]/p' < "$subject"/stats_out/${1}.txt | flatten | paste - $tmpdir/"${subject}"_${1}_flags.txt > $tmpdir/"${subject}"_${1}_flat.txt 
         echo "$subject" $tmpdir/"${subject}"_${1}_flat.txt
     fi
done | combine_flattened > $1_combined.txt
rm -r $tmpdir
