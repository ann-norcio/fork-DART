#!/usr/bin/env bash

main() {

[ -z "$DART" ] && echo "ERROR: Must set DART environment variable" && exit 9
source $DART/build_templates/buildconvfunctions.sh

CONVERTER=ROMS
LOCATION=threed_sphere
EXTRA="$DART/models/ROMS/model_mod.f90"


programs=( \
convert_roms_obs \
obs_seq_to_netcdf \
obs_sequence_tool \
advance_time
)

# build arguments
arguments "$@"

# clean the directory
\rm -f *.o *.mod Makefile .cppdefs

# build and run preprocess before making any other DART executables
buildpreprocess

# build 
buildconv


# clean up
\rm -f *.o *.mod

}

main "$@"
