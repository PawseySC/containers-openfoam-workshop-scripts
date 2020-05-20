#!/bin/bash -l
#SBATCH --ntasks=1
#@@#SBATCH --mem=32G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --time=0:10:00
#SBATCH --partition=workq
#SBATCH --export=none

#1. Load the necessary modules
module load singularity
 
#2. Defining the container to be used
theRepo=/group/singularity/pawseyRepository/OpenFOAM
theContainerBaseName=openfoam
theVersion=v1912
theProvider=pawsey
theImage=$theRepo/$theContainerBaseName-$theVersion-$theProvider.sif
 
#3. Defining the case directory
#baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/run
baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/workshop/01_usingOpenFOAMContainers/run
caseName=channel395
caseDir=$baseWorkingDir/$caseName

#4. Going into the case and creating the logs directory
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=./logs/post
if ! [ -d $logsDir ]; then
   mkdir -p $logsDir
fi

#5. Reading OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#6. Defining the ioRanks for collating I/O
# groups of 2 for this exercise (please read our documentation for the recommendations for production runs)
export FOAM_IORANKS='(0 2 4 6)'

#7. Execute reconstruction
echo "Start reconstruction"
srun -n 1 -N 1 singularity exec $theImage reconstructPar -latestTime 2>&1 | tee $logsDir/log.reconstructPar.$SLURM_JOBID

#X. Final step
echo "Script done"
