#!/bin/bash

#Choosing the tutorial case
tutorialAppDir=incompressible/pimpleFoam
tutorialName=channel395
tutorialCase=$tutorialAppDir/$tutorialName

#Choosing the working directory for the case to solve
#baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/run
#baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/workshop/06_usingOverlayVirtualFS/run
baseWorkingDir=$SLURM_SUBMIT_DIR/run
if ! [ -d $baseWorkingDir ]; then
    echo "Creating baseWorkingDir=$baseWorkingDir"
    mkdir -p $baseWorkingDir
fi
caseName=$tutorialName
caseDir=$baseWorkingDir/$caseName

#@@##Choosing the OpenFOAM user directory in the local host (equivalent to WM_PROJECT_USER_DIR) for own defined tools
#@@##userProjectDir=$MYGROUP/OpenFOAM/$USER-$theVersion
#@@##userProjectDir=$MYGROUP/OpenFOAM/$USER-$theVersion/workshop/06_usingOverlayVirtualFS
#@@#userProjectDir=$SLURM_SUBMIT_DIR/userProjectDir
#@@#if ! [ -d $userProjectDir ]; then
#@@#   echo "Creating userProjectDir=$userProjectDir"
#@@#   mkdir -p $userProjectDir
#@@#fi

#Defining the name of the directory inside the ./overlayFSDir/overlay* files at which results will be saved
baseInsideDir=/overlayOpenFOAM/run
insideName=$caseName
insideDir=$baseInsideDir/$insideName

#These are not settings, but the directories where the results are going to be saved are:
#$caseDir/bakDir for the bak.processor* directories, and
#$caseDir/overlayFSDir for the overlay* files
#(See the script C.setupOverlayFoam.sh for the creation of those directories)
