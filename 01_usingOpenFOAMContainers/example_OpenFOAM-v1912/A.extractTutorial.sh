#!/bin/bash -l
#SBATCH --export=NONE
#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --partition=copyq
 
#1. Load the necessary modules
module load singularity
 
#2. Defining the container to be used
theRepo=/group/singularity/pawseyRepository/OpenFOAM
theContainerBaseName=openfoam
theVersion=v1912
theProvider=pawsey
theImage=$theRepo/$theContainerBaseName-$theVersion-$theProvider.sif
 
#3. Defining the tutorial and the case directory
tutorialAppDir=incompressible/pimpleFoam/LES
tutorialName=channel395
tutorialCase=$tutorialAppDir/$tutorialName

baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/workshop/01_usingOpenFOAMContainers/run
if ! [ -d $baseWorkingDir ]; then
    echo "Creating baseWorkingDir=$baseWorkingDir"
mkdir -p $baseWorkingDir
fi
caseName=$tutorialName
caseDir=$baseWorkingDir/$caseName

#4. Copy the tutorialCase to the workingDir
if ! [ -d $caseDir ]; then
   srun -n 1 -N 1 singularity exec $theImage bash -c 'cp -r $FOAM_TUTORIALS/'"$tutorialCase $caseDir"
else
   echo "The case=$caseDir already exists, no new copy has been performed"
fi

#5. Going into the case directory
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi

#X. Final step
echo "Script done"
