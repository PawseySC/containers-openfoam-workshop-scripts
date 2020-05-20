#!/bin/bash

#Choosing the tutorial case
tutorialAppDir=incompressible/pimpleFoam
tutorialName=channel395
tutorialCase=$tutorialAppDir/$tutorialName

#Choosing the working directory for the case to solve
#baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/run
baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/workshop/06_usingOverlayVirtualFS/run
if ! [ -d $baseWorkingDir ]; then
    echo "Creating baseWorkingDir=$baseWorkingDir"
    mkdir -p $baseWorkingDir
fi
caseName=$tutorialName
caseDir=$baseWorkingDir/$caseName

#Choosing the OpenFOAM user directory in the local host (equivalent to WM_PROJECT_USER_DIR) for own defined tools
#userProjectDir=$MYGROUP/OpenFOAM/$USER-$theVersion
userProjectDir=$MYGROUP/OpenFOAM/$USER-$theVersion/workshop/06_usingOverlayVirtualFS
if ! [ -d $userProjectDir ]; then
   echo "Creating userProjectDir=$userProjectDir"
   mkdir -p $userProjectDir
fi

#Defining the name of the directories inside the overlays
baseInsideDir=/overlayOpenFOAM/run
insideName=$caseName
insideDir=$baseInsideDir/$insideName
