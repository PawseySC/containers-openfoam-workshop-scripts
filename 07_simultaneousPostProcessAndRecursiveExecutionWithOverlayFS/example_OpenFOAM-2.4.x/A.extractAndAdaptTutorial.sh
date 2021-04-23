#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --clusters=zeus
#SBATCH --partition=copyq #Ideally, use copyq for this process. copyq is on zeus.
#SBATCH --time=0:10:00
#SBATCH --export=none

#------
echo "1. Loading the container settings, case settings and auxiliary functions (order is important)"
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh
overlayFunctionsScript=$auxScriptsDir/ofContainersOverlayFunctions.sh
if [ -f "$overlayFunctionsScript" ]; then 
   source $overlayFunctionsScript
else
   echo "The script for the functions to manage OverlaFS files: $overlayFunctionsScript was not found"
   echo "Exiting"; exit 1
fi

#------
echo "2. Copy the tutorialCase to the workingDir"
cd $SLURM_SUBMIT_DIR
if ! [ -d $caseDir ]; then
   echo "The tutorial case to copy is: $tutorialCase"
   echo "Into caseDir=$caseDir"
   srun -n 1 -N 1 singularity exec $theImage bash -c 'cp -r $FOAM_TUTORIALS/'"$tutorialCase $caseDir" 
else
   echo "The case=$caseDir already exists, no new copy has been performed"
fi

#------
echo "3. Going into the case directory"
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi

#------
echo "4. Defining OpenFOAM controlDict settings for Pawsey Best Practices"
foam_writeFormat="binary"
sed -i 's,^writeFormat.*,writeFormat    '"$foam_writeFormat"';,' ./system/controlDict
foam_runTimeModifiable="false"
sed -i 's,^runTimeModifiable.*,runTimeModifiable    '"$foam_runTimeModifiable"';,' ./system/controlDict

#------
echo "X. Final step"
echo "Script done"

