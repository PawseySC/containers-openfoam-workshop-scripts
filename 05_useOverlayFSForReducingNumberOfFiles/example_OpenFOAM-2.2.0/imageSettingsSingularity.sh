#!/bin/bash

#Module environment
module load singularity
#module rm xalt

#Defining the container to be used
theRepo=/group/singularity/pawseyRepository/OpenFOAM
#theRepo=/group/pawsey0001/espinosa/singularity/myRepository/OpenFOAM
theContainerBaseName=openfoam
theVersion=2.2.0
theProvider=pawsey
theImage=$theRepo/$theContainerBaseName-$theVersion-$theProvider.sif

#Defining settings for the OverlayFS
overlaySizeGb=1
