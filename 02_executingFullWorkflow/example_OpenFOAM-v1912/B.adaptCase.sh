#!/bin/bash -l
#SBATCH --export=NONE
#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --clusters=zeus 
#SBATCH --partition=copyq #Ideally, this job should use the copyq. copyq is on zeus
 
#1. Load the necessary modules
module load singularity
 
#2. Defining the container to be used
theRepo=/group/singularity/pawseyRepository/OpenFOAM
theContainerBaseName=openfoam
theVersion=v1912
theProvider=pawsey
theImage=$theRepo/$theContainerBaseName-$theVersion-$theProvider.sif
 
#3. Defining the case directory
#baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/workshop/01_usingOpenFOAMContainers/run
baseWorkingDir=$SLURM_SUBMIT_DIR/run
caseName=channel395
caseDir=$baseWorkingDir/$caseName

#4. Going into the case directory
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi

#5. Defining OpenFOAM controlDict settings for Pawsey Best Practices
##5.1 Replacing writeFormat, runTimeModifiable and purgeRight settings
foam_writeFormat="binary"
sed -i 's,^writeFormat.*,writeFormat    '"$foam_writeFormat"';,' ./system/controlDict
foam_runTimeModifiable="false"
sed -i 's,^runTimeModifiable.*,runTimeModifiable    '"$foam_runTimeModifiable"';,' ./system/controlDict
foam_purgeWrite=10
sed -i 's,^purgeWrite.*,purgeWrite    '"$foam_purgeWrite"';,' ./system/controlDict

##5.2 Defining the use of collated fileHandler of output results 
echo "OptimisationSwitches" >> ./system/controlDict
echo "{" >> ./system/controlDict
echo "   fileHandler collated;" >> ./system/controlDict
echo "}" >> ./system/controlDict

#X. Final step
echo "Script done"
