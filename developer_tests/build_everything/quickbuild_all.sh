#!/usr/bin/env bash

# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download

# Send to emails
TO_EMAIL_ADDRESSES='anorcio@ucar.edu example@ucar.edu'

# Get the top-level directory of DART
export DART=$(git rev-parse --show-toplevel)

# Log file to output results
LOGFILE="all_quickbuilds_results.log"

# Store arguments for compilers in an array
FCS=( $@ )

# Check if the DART directory exists
if [[ ! -d $DART ]] ; then 
  echo "No DART directory: " $DART
  exit 1
fi 

# Check if the script is running in a PBS batch job environment
if [[ -z  $PBS_ENVIRONMENT ]]; then
  echo "ERROR: Run this in a batch job"
  echo "       qsub submit_me.sh"
  echo "       or an interactive session"
  exit 2
fi

# If no compiler is provided, run with all compilers
if [[ "${#FCS[@]}" == 0 ]]; then
	FCS=( intel gnu cce )
fi

# Append today's date to log file
printf '\n%s\n' "$(date)" >"$LOGFILE"

# Loop through each compiler
for FC in "${FCS[@]}"; do

  if [[ $FC == "intel" ]]; then
    template_name="mkmf.template.intel.linux"
  elif [[ $FC == "gnu" ]]; then
    template_name="mkmf.template.gfortran"
  elif [[ $FC == "cce" ]]; then
    template_name="mkmf.template.cce"
  else
    echo "$FC is not a valid argument. It must be either intel/gnu/cce."
    continue
  fi

  printf '\nProcessing %s\n' "$FC"

  # Copy appropriate mkmf template
  cp "$template_name" $DART/build_templates/mkmf.template
  cd $DART

  # Run fixsystem once
  cd assimilation_code/modules/utilities
  ./fixsystem $FC
  cd -

  # Build preprocess once
  pp_dir=$DART/assimilation_code/programs/preprocess
  cd $pp_dir
  $DART/build_templates/mkmf -x -p $pp_dir/preprocess \
        -a $DART $pp_dir/path_names_preprocess
  cd -

  # input.nml
  find . -name input.nml -exec sed -i  -e "/^[[:space:]]*#/! s|.*output_obs_def_mod_file.*|output_obs_def_mod_file = './obs_def_mod.f90'|g" \
        -e "/^[[:space:]]*#/! s|.*output_obs_qty_mod_file.*|output_obs_qty_mod_file = './obs_kind_mod.f90'|g" \
        -e "/^[[:space:]]*#/! s|.*output_obs_kind_mod_file.*|output_obs_qty_mod_file = './obs_kind_mod.f90'|g" {} \;  

  my_dir=$(pwd)
  pids=()
  dirs=()
  status=()

  # Find all quickbuild.sh executables
  files_to_process=( $(find $DART -executable -type f -name quickbuild.sh | sed -E 's#(\./|quickbuild\.sh)##g') )

  for f in "${files_to_process[@]}"; do
    cd $f
    ./quickbuild.sh & 
    pids+=( "$!" )
    dirs+=( "$f" )
    cd $my_dir
  done

  for pid in ${pids[@]}; do
    wait ${pid}
    status+=( "$?" )
  done

  # Loop through the status array to check the exit code for each quickbuild.sh
  i=0
  for st in ${status[@]}; do
      if [[ ${st} -ne 0 ]]; then
          echo "$FC RESULT: $i ${dirs[$i]} failed"
          OVERALL_EXIT=1
      else
          echo "$FC RESULT: $i  ${dirs[$i]} passed"
      fi
      ((i+=1))
  done

done &>"$LOGFILE"

# Send an email with the log file attached
mail_subject=$(printf 'Quickbuild test results: %s' "$(date)")
echo "$mail_subject" | mail -s "$mail_subject" -a "$LOGFILE" $TO_EMAIL_ADDRESSES
