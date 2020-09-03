#!/bin/bash -l
#SBATCH --ntasks=4
#SBATCH --mem=16G
#SBATCH --ntasks-per-node=28
#SBATCH --cluster=zeus
#@@#SBATCH --mem=58G
#@@#SBATCH --ntasks-per-node=24
#@@#SBATCH --cluster=magnus
#SBATCH --partition=workq
#SBATCH --time=0:10:00
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
#baseWorkingDir=$MYSCRATCH/OpenFOAM/$USER-$theVersion/workshop/01_usingOpenFOAMContainers/run
baseWorkingDir=$SLURM_SUBMIT_DIR/run
caseName=channel395
caseDir=$baseWorkingDir/$caseName

#4. Going into the case and creating the logs dir
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=./logs/run
if ! [ -d $logsDir ]; then
   mkdir -p $logsDir
fi

#5. Reading OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#6. Defining the ioRanks for collating I/O
# groups of 2 for this exercise (please read our documentation for the recommendations for production runs)
export FOAM_IORANKS='(0 2 4 6)'

#7. Checking if the number of tasks coincide with the number of subdomains
if [[ $foam_numberOfSubdomains -ne $SLURM_NTASKS ]]; then
   echo "foam_numberOfSubdomains read from ./system/decomposeParDict is $foam_numberOfSubdomains"
   echo "and"
   echo "SLURM_NTASKS in this job is $SLURM_NTASKS"
   echo "These should be the same"
   echo "Therefore, exiting this job"
   echo "Exiting"; exit 1
fi

#8. Defining OpenFOAM controlDict settings for this run
foam_startFrom=startTime
#foam_startFrom=latestTime
foam_startTime=0
#foam_startTime=15
foam_endTime=10
#foam_endTime=30
foam_writeInterval=1
foam_purgeWrite=10

#9. Changing OpenFOAM controlDict settings
sed -i 's,^startFrom.*,startFrom    '"$foam_startFrom"';,' system/controlDict
sed -i 's,^startTime.*,startTime    '"$foam_startTime"';,' system/controlDict
sed -i 's,^endTime.*,endTime    '"$foam_endTime"';,' system/controlDict
sed -i 's,^writeInterval.*,writeInterval    '"$foam_writeInterval"';,' system/controlDict
sed -i 's,^purgeWrite.*,purgeWrite    '"$foam_purgeWrite"';,' system/controlDict

#10. Defining the solver
of_solver=myPimpleFoam

#11. Defining the projectUserDir to be mounted into the path of the internal WM_PROJECT_USER_DIR
projectUserDir=$SLURM_SUBMIT_DIR/projectUserDir

#12. Execute the case 
echo "About to execute the case"
srun -n $SLURM_NTASKS -N $SLURM_JOB_NUM_NODES singularity exec -B $projectUserDir:/home/ofuser/OpenFOAM/ofuser-$theVersion $theImage $of_solver -parallel 2>&1 | tee $logsDir/log.$theSolver.$SLURM_JOBID
echo "Execution finished"

#X. Final step
echo "Script done"
