#!/bin/bash -l
#SBATCH --ntasks=1
#@@#SBATCH --mem=4G
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
projectUserDir=$MYGROUP/OpenFOAM/$USER-$theVersion/workshop/02_runningUsersOwnTools
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

#4. Remove not needed stuff
echo "Removing not needed stuff"
rm -rf *DyMFoam SRFP* *.dep

#5. Rename the source files and replace words inside
echo "Renaming the source files"
rename pimpleFoam myPimpleFoam *
sed -i 's,pimpleFoam,myPimpleFoam,g' *.C
sed -i 's,pimpleFoam,myPimpleFoam,g' *.H

#6. Modify files inside the Make directory
echo "Adapting files inside the Make directory"
sed -i 's,pimpleFoam,myPimpleFoam,g' ./Make/files
sed -i 's,FOAM_APPBIN,FOAM_USER_APPBIN,g' ./Make/files

#7. Use the container to compile your own tool 
srun -n 1 -N 1 singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage wclean 2>&1 | tee $logsDir/wclean.$SLURM_JOBID
srun -n 1 -N 1 singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage wmake 2>&1 | tee $logsDir/wmake.$SLURM_JOBID

#8. Very simple test of the new solver
singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage myPimpleFoam -help | tee $logsDir/myPimpleFoam.$SLURM_JOBID

#X. Final step
echo "Script done"
