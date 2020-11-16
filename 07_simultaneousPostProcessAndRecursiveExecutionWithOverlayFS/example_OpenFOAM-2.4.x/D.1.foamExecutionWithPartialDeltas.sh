#!/bin/bash -l
#SBATCH --job-name=solverExecution
#SBATCH --output="%x-%j.out"
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
cd $SLURM_SUBMIT_DIR
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=$caseDir/logs/run
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
#   NOTE:IMPORTANT:Use this parameters to control the wholeJob.
#                  But, as the wholeJob in this script is going to be executed in several partial srun's
#                  (each advancing time by partial_Delta), the partial parameters set in the controlDict will vary
#                  for each partial srun.
#foam_startFrom=startTime
foam_startFrom=latestTime
foam_startTime=0.0
#foam_startTime=10.0
#foam_startTime=40.0
#foam_endTime=10.0
#foam_endTime=20.0
#foam_endTime=40.0
#foam_endTime=60.0
#foam_endTime=45.0
foam_endTime=100.0
foam_writeControl=runTime
foam_deltaT=0.2
foam_writeInterval=$foam_deltaT #This should be a reasonable writing frequency
foam_purgeWrite=0 #For the purposes of this test, but ideally should be a reasonable number
#foam_purgeWrite=10 #Only 10 time directories will be kept

#6. Defining the estimated partial_Delta
#   NOTE:IMPORTANT:The suggestion is to estimate the needed Delta for a 5hr srun execution each
#   NOTE:IMPORTANT:The parameters partial_startTime, partial_endTime, partial_startFrom
#                  will be estimated in the cycle of partial srun's using the given partial_Delta.
partial_Delta=5.0
#partial_Delta=10.0

#7. Creating soft links towards directories inside the ./overlayFSDir/overlay* files
#These links and directories will be recognized by each mpi instance of the container
#(Initially these links will appear broken as they are pointing towards the interior of the ./overlayFSDir/overlay* files.
# They will only be recognized within the containers)
pointToOverlay $insideDir $foam_numberOfSubdomains;success=$? #Calling function to point towards the interior
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#9. Execute the case in cycles of partial_Delta
maxCycles=4
for partial_counter in `seq 1 $maxCycles`; do
   echo "Iteration $partial_counter of $maxCycles of the partial srun's execution"
   if [ $partial_counter -eq $maxCycles ]; then
      echo "maxCycles=$maxCycles have been reached."
      echo "This is the last cycle of partial srun's to be executed in the current job."
   fi

   #9.0 Define the partial_startTime and partial_startFrom
   if [ $partial_counter -eq 1 ] && [ "$foam_startFrom" == "startTime" ]; then
      partial_startFrom=$foam_startFrom
      partial_startTime=$foam_startTime
   else
      echo "Starting from the secondLastTime available to avoid possible wrong-written results in latest time"
      partial_startFrom=startTime
      partial_startTime=$(getNResultTime -2 $insideDir);success=$? #Calling function to obtain the secondLast Time available (-2)
      if [ $success -ne 0 ]; then
         echo "Failed obtaining the secondLast Time (-2) available"
         echo "Exiting";exit 1
      fi
   fi
   echo "partial_startFrom=$partial_startFrom"
   echo "partial_startTime=$partial_startTime"

   #9.1 If more than two result directories are present in the overlay* files, then:
   #    A. rename exiting overlay* files (and create a new ones) (done by D.2.setupNewOverlayPerPartialDelta.sh)
   #    B. submit a reconstruction job for the already existing results in the renamed overlay*_JOBID_I files.
   reconstructTimes="all"
   unset arrayReconstruct #This global variable will be re-created in the function below
   surnameTag=""
   generateReconstructArray "$reconstructTimes" $insideDir $surnameTag;success=$? #Calling fucntion to generate "arrayReconstruct"
   if [ $success -ne 0 ]; then
      echo "Failed creating the arrayReconstruct"
      echo "Exiting";exit 1
   fi
   nResults=${#arrayReconstruct[@]}
   echo "There are $nResults results directories in ./overlayFSDir/overlay0"
   if [ $nResults -ge 3 ]; then
      echo "Executing script for renaming existing overlay* files and creating new ones"
      . $SLURM_SUBMIT_DIR/D.2.setupNewOverlayPerPartialDelta.sh
      partial_previousCounter=$((partial_counter-1))
      newSurnameTag="_${SLURM_JOBID}_${partial_previousCounter}"
      echo "Submitting reconstruction for results in: ./overlayFSDir/overlay*${newSurnameTag} files" 
      pathHere=$PWD
      cd $SLURM_SUBMIT_DIR
      sbatch --job-name=reconstruct${newSurnameTag} \
             --export="surnameTag=${newSurnameTag},reconstructTimes=${reconstructTimes}" \
             --clusters=zeus \
             ${SLURM_SUBMIT_DIR}/E.0.reconstruct-recursive-template.sh
      echo "AEG:D.1: reconstructTimes=$reconstructTimes"
      cd $pathHere
   else
      echo "The same set of overlay files will be used for this partial srun"
   fi

   #9.2 Define the partial_endTime = partials_startTime + partial_Delta
   if [ $nResults -eq 1 ]; then
      partial_endTime=`echo "$partial_startTime + $partial_Delta" | bc` 
   else
      partial_endTime=`echo "$partial_startTime + $partial_Delta + $foam_writeInterval" | bc` 
   fi
   st=`echo "$partial_endTime >= $foam_endTime" | bc`
   if [ $st -eq 1 ]; then
      partial_endTime=$foam_endTime
   fi
   echo "partial_endTime=$partial_endTime"

   #9.3 Changing OpenFOAM controlDict settings
   sed -i 's,^startFrom.*,startFrom    '"$partial_startFrom"';,' system/controlDict
   sed -i 's,^startTime.*,startTime    '"$partial_startTime"';,' system/controlDict
   sed -i 's,^endTime.*,endTime    '"$partial_endTime"';,' system/controlDict
   sed -i 's,^deltaT.*,deltaT    '"$foam_deltaT"';,' system/controlDict
   sed -i 's,^writeControl.*,writeControl    '"$foam_writeControl"';,' system/controlDict
   sed -i 's,^writeInterval.*,writeInterval    '"$foam_writeInterval"';,' system/controlDict
   sed -i 's,^purgeWrite.*,purgeWrite    '"$foam_purgeWrite"';,' system/controlDict
   
   #9.4 Execute the case 
   echo "About to execute the case"
   srun -n $SLURM_NTASKS -N $SLURM_JOB_NUM_NODES bash -c "singularity exec --overlay ./overlayFSDir/"'overlay${SLURM_PROCID}'" $theImage pimpleFoam -parallel 2>&1" | tee $logsDir/log.pimpleFoam.$SLURM_JOBID
   echo "Execution finished"

   #9.5 Exiting if the foam_endTime has been reached
   lastTimeReached=$(getNResultTime -1 $insideDir);success=$? #Calling function to obtain the Last Time result available (-1)
   if [ $success -ne 0 ]; then
      echo "Failed obtaining the Last Time (-1) available"
      echo "Exiting";exit 1
   fi
   echo "lastTimeReached=$lastTimeReached"
   st=`echo "$lastTimeReached >= $foam_endTime" | bc`
   if [ $st -eq 1 ]; then
      echo "lastTimeReached ($lastTimeReached) >= foam_endTime ($foam_endTime)"
      echo "Stopping the cycle of partial srun's"
      break
   fi
done

#10. Transfer a few result times available inside the OverlayFS towards the ./bakDir/bak.procesors directories
reconstructTimes=-2 #A negative value "-N" will be interpreted as the last N times by the function "generateReconstructArray"
if [ -z "$reconstructTimes" ]; then
   echo "reconstructTimes string was not set, implying that:"
   echo "No copy of times from the ./overlayFSDir/overlay* files towards the host will be performed at this point"
else
   unset arrayReconstruct #This global variable will be re-created in the function below
   surnameTag=""
   generateReconstructArray "$reconstructTimes" $insideDir $surnameTag;success=$? #Calling fucntion to generate "arrayReconstruct"
   if [ $success -ne 0 ]; then
      echo "Failed creating the arrayReconstruct"
      echo "Exiting";exit 1
   fi
   replace="false"
   copyResultsIntoBak "$insideDir" "$surnameTag" "$foam_numberOfSubdomains" "$replace" "${arrayReconstruct[@]}";success=$? #Calling the function to copy time directories into ./bakDir/bak.processor*
   if [ $success -ne 0 ]; then
      echo "Failed transferring files into ./bakDir/bak.processor* directories"
      echo "Exiting";exit 1
   fi
fi

#11. List the existing times inside the ./overlayFSDir/overlay0 
echo "Listing the available times inside ./overlayFSDir/overlay0"
srun -n 1 -N 1 singularity exec --overlay ./overlayFSDir/overlay0 $theImage ls -lat processor0/

#X. Final step
echo "Script done"
