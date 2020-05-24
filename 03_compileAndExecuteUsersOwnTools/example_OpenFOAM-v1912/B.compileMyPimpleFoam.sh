#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --partition=workq
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

#3. Going into the new solver directory and creating the logs directory
#projectUserDir=$MYGROUP/OpenFOAM/$USER-$theVersion/workshop/02_runningUsersOwnTools
projectUserDir=$SLURM_SUBMIT_DIR/projectUserDir
solverNew=myPimpleFoam
if [ -d $projectUserDir/applications/$solverNew ]; then
   cd $projectUserDir/applications/$solverNew
   echo "pwd=$(pwd)"
else
   echo "For some reason, the directory $projectUserDir/applications/$solverNew, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=./logs/compile
if ! [ -d $logsDir ]; then
   mkdir -p $logsDir
fi

#4. Use container's "wclean" to clean previously existing compilation 
echo "Cleaning previous compilation"
srun -n 1 -N 1 singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage wclean 2>&1 | tee $logsDir/wclean.$SLURM_JOBID

#5. Use container's "wmake" (and compiler) to compile your own tool
echo "Compiling myPimpleFoam"
srun -n 1 -N 1 singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage wmake 2>&1 | tee $logsDir/wmake.$SLURM_JOBID

#6. Very simple test of the new solver
echo "Performing a basic test"
singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage myPimpleFoam -help | tee $logsDir/myPimpleFoam.$SLURM_JOBID

#X. Final step
echo "Script done"
