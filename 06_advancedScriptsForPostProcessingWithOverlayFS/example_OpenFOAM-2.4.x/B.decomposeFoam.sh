#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --partition=workq
#SBATCH --time=0:10:00
#SBATCH --export=none

#1. Loading the container settings (order is important)
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh
overlayFunctionsScript=$auxScriptsDir/ofContainersOverlayFunctions.sh
if [ -f "$overlayFunctionsScript" ]; then 
   source $overlayFunctionsScript
else
   echo "The script for the functions to manage OverlaFS files: $overlayFunctionsScript was not found"
   echo "Exiting"; exit 1
fi

#2. Going into the case and creating the logs directory
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=./logs/pre
if ! [ -d $logsDir ]; then
   mkdir -p $logsDir
fi

#3. Reading the OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#4. Perform all preprocessing OpenFOAM steps up to decomposition
srun -n 1 -N 1 singularity exec $theImage blockMesh 2>&1 | tee $logsDir/log.blockMesh
srun -n 1 -N 1 singularity exec $theImage decomposePar -cellDist 2>&1 | tee $logsDir/log.decomposePar

#X. Final step
echo "Script done"

