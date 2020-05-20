#!/bin/bash -l
#SBATCH --ntasks=1
#@@#SBATCH --ntasks-per-node=28
#@@#SBATCH --clusters=zeus
#SBATCH --partition=copyq
#SBATCH --time=0:10:00
#SBATCH --export=none

#0. Initial settings:
unset XDG_RUNTIME_DIR #To avoid some annoying warnings when using some containers

#1. Loading the container settings, case settings and auxiliary functions (order is important)
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh
overlayFunctionsScript=$auxScriptsDir/ofContainersOverlayFunctions.sh
if [ -f "$overlayFunctionsScript" ]; then 
   source $overlayFunctionsScript
else
   echo "The script for the auxiliary functions = $auxFucntionsScript was not found"
   echo "Exiting"; exit 1
fi

#2. Copy the tutorialCase to the workingDir
if ! [ -d $caseDir ]; then
   srun -n 1 -N 1 singularity exec $theImage bash -c 'cp -r $FOAM_TUTORIALS/'"$tutorialCase $caseDir" 
else
   echo "The case=$caseDir already exists, no new copy has been performed"
fi

#3. Going into the case directory
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi

#4. Defining OpenFOAM controlDict settings for Pawsey Best Practices
foam_writeFormat="binary"
sed -i 's,^writeFormat.*,writeFormat    '"$foam_writeFormat"';,' ./system/controlDict
foam_runTimeModifiable="false"
sed -i 's,^runTimeModifiable.*,runTimeModifiable    '"$foam_runTimeModifiable"';,' ./system/controlDict
#foam_purgeWrite=10
#sed -i 's,^purgeWrite.*,purgeWrite    '"$foam_purgeWrite"';,' ./system/controlDict

#X. Final step
echo "Script done"

