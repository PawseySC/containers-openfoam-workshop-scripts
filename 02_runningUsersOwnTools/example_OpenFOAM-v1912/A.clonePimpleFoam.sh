#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --partition=copyq
#SBATCH --time=0:05:00
#SBATCH --export=none

#1. Load the necessary modules
module load singularity

#2. Defining the container to be used
theRepo=/group/singularity/pawseyRepository/OpenFOAM
theContainerBaseName=openfoam
theVersion=v1912
theProvider=pawsey
theImage=$theRepo/$theContainerBaseName-$theVersion-$theProvider.sif

#3. Copy the original solver to the user directory in the host
appDirOrg=applications/solvers/incompressible
solverOrg=pimpleFoam
projectUserDir=$MYGROUP/OpenFOAM/$USER-$theVersion/workshop/02_runningUsersOwnTools
solverNew=myPimpleFoam
if ! [ -d $projectUserDir/applications/$solverNew ]; then
   if ! [ -d $projectUserDir/applications ]; then
      mkdir -p $projectUserDir/applications
   fi
   srun -n 1 -N 1 singularity exec $theImage bash -c 'cp -r $WM_PROJECT_DIR/'"$appDirOrg/$solverOrg $projectUserDir/applications/$solverNew" 
else
   echo "The directory $projectUserDir/applications/$solverNew already exists, no new copy has been performed"
fi

#4. Going into the new solver directory
if [ -d $projectUserDir/applications/$solverNew ]; then
   cd $projectUserDir/applications/$solverNew
   echo "pwd=$(pwd)"
else
   echo "For some reason, the directory $projectUserDir/applications/$solverNew, does not exist"
   echo "Exiting"; exit 1
fi

#5. Removing 

#X. Final step
echo "Script done"
