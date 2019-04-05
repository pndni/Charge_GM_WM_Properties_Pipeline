# TODO: setup either run_subject.sh or run_subject_container.sh for your site.
# see the comments in the respective file for details

# TODO: create a file "subject_list" that contains one subject name on each line
# each subject name is an argument to either run_subject.sh or run_subject_container.sh

ntasks=4  # TODO set to the number of subjects you want to run simultaneously (<= the number of cores on your machine)
logfile=parallel.log  # TODO set to desired name of the parallel log file
# TODO replace run_subject_container.sh with run_subject.sh if not using singularity
parallel -j $ntasks --joblog $logfile ./run_subject_container.sh {} :::: subject_list
