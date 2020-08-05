#!/bin/bash

#Module environment
module load singularity
#module rm xalt

#Defining the container to be used
theRepo=/group/singularity/pawseyRepository/OpenFOAM
#theRepo=/group/pawsey0001/espinosa/singularity/myRepository/OpenFOAM
theContainerBaseName=openfoam
theVersion=2.4.x
theProvider=pawsey
theImage=$theRepo/$theContainerBaseName-$theVersion-$theProvider.sif

#Defining settings for the OverlayFS
overlaySizeGb=1

#Defining the path of the auxiliary scripts for dealing with overlayFS
#(Define the path to a more permanent directory for production workflows)
auxScriptsDir=$SLURM_SUBMIT_DIR/../../A1_auxiliaryScripts
