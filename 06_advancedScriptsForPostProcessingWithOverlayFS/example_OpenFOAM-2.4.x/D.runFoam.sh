#!/bin/bash -l
#SBATCH --ntasks=5
#SBATCH --ntasks-per-node=28
#SBATCH --cluster=zeus
#@@#SBATCH --ntasks-per-node=24
#@@#SBATCH --cluster=magnus
#SBATCH --partition=workq
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
   echo "The script for the functions to manage OverlaFS files: $overlayFunctionsScript was not found"
   echo "Exiting"; exit 1
fi

#2. Going into the case, creating the logs dir if it does not exists
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

#3. Reading OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#4. Checking if the number of tasks coincide with the number of subdomains
if [[ $foam_numberOfSubdomains -ne $SLURM_NTASKS ]]; then
   echo "foam_numberOfSubdomains read from ./system/decomposeParDict is $foam_numberOfSubdomains"
   echo "and"
   echo "SLURM_NTASKS in this job is $SLURM_NTASKS"
   echo "These should be the same"
   echo "Therefore, exiting this job"
   echo "Exiting"; exit 1
fi

#5. Defining OpenFOAM controlDict settings for this run
foam_startFrom=startTime
#foam_startFrom=latestTime
foam_startTime=0
#foam_startTime=10
#foam_startTime=40
#foam_endTime=10
#foam_endTime=20
foam_endTime=40
#foam_endTime=45
#foam_endTime=100
foam_writeInterval=1 #For the purposes of this test, but ideally should be a reasonable writing frequency
foam_purgeWrite=0 #For the purposes of this test, but ideally should be a reasonable number
#foam_purgeWrite=10 #Only 10 time directories will be kept

#6. Changing OpenFOAM controlDict settings
sed -i 's,^startFrom.*,startFrom    '"$foam_startFrom"';,' system/controlDict
sed -i 's,^startTime.*,startTime    '"$foam_startTime"';,' system/controlDict
sed -i 's,^endTime.*,endTime    '"$foam_endTime"';,' system/controlDict
sed -i 's,^writeInterval.*,writeInterval    '"$foam_writeInterval"';,' system/controlDict
sed -i 's,^purgeWrite.*,purgeWrite    '"$foam_purgeWrite"';,' system/controlDict

#7. Creating soft links towards directories inside the overlayFS files
#These links and directories will be recognized by each mpi instance of the container
#(Initially these links will appear broken as they are pointing towards the interior of the overlay* files.
# They will only be recognized within the containers)
pointToOverlay $overlayFSDir $insideDir $foam_numberOfSubdomains;success=$? #Calling function to point towards the interior
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#8. Execute the case 
echo "About to execute the case"
srun -n $SLURM_NTASKS -N $SLURM_JOB_NUM_NODES bash -c "singularity exec --overlay ${overlayFSDir}/"'overlay${SLURM_PROCID}'" $theImage pimpleFoam -parallel 2>&1" | tee $logsDir/log.pimpleFoam.$SLURM_JOBID
echo "Execution finished"

#9. Transfer a few result times available inside the OverlayFS towards the ./bakDir/bak.procesors directories
#reconstructTimes=-2 #A negative value "-N" will be interpreted as the last N times by the function "generateReconstructArray"
if [ -z "$reconstructTimes" ]; then
   echo "reconstructTimes string was not set, implying that:"
   echo "No copy of times from the overlays to the host will be performed at this point"
else
   unset arrayReconstruct #This global variable will be re-created in the function below
   generateReconstructArray $overlayFSDir "$reconstructTimes" $insideDir;success=$? #Calling fucntion to generate "arrayReconstruct"
   if [ $success -ne 0 ]; then
      echo "Failed creating the arrayReconstruct"
      echo "Exiting";exit 1
   fi
   replace="false"
   copyResultsIntoBak "$overlayFSDir" "$insideDir" "$foam_numberOfSubdomains" "$replace" "${arrayReconstruct[@]}";success=$? #Calling the function to copy time directories into ./bakDir/bak.processor*
   if [ $success -ne 0 ]; then
      echo "Failed transferring files into ./bakDir/bak.processor* directories"
      echo "Exiting";exit 1
   fi
fi

#X. Final step
echo "Script done"
