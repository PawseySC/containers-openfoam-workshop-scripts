#!/bin/bash -l
#SBATCH --ntasks=1
#SBATCH --mem=4G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --time=0:10:00
#SBATCH --partition=workq
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

#2. Going into the case and creating the logs directory
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

#3. Reading OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#4. Point the soft links to the ./bakDir/bak.processor* directories
pointToBak $foam_numberOfSubdomains;success=$? #Calling function to point towards the ./bakDir/bak.processors
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#5. Create the reconstruction array, intended times to be reconstructed are set with the reconstructTimes var
#These formats are the only accepted by function "generateReconstructArray" (check the function definition for further information)
reconstructTimes="all"
#reconstructTimes="-2"
#reconstructTimes="60"
#reconstructTimes="50,60,70,80,90"
#reconstructTimes="0:1"
if [ -z "$reconstructTimes" ]; then
   echo "reconstructTimes string was not set, implying that:"
   echo "No reconstruction will be performed at this point"
   echo "Exiting"; exit 0
else
   unset arrayReconstruct #This global variable will be re-created in the function below
   generateReconstructArray $overlayFSDir "$reconstructTimes" "bak";success=$? #Calling function to generate "arrayReconstruct"
   if [ $success -ne 0 ]; then
      echo "Failed creating the arrayReconstruct"
      echo "Exiting";exit 1
   fi
fi

#6. Generate a list of time directories in ./bakDir/bak.processor* to be preserved decomposed and not removed after reconstruction
ls -dt ./bakDir/bak.processor0/[0-9]* | sed "s,./bakDir/bak.processor0/,," > bakTimes.$SLURM_JOBID
sort -n bakTimes.$SLURM_JOBID -o bakTimesSorted.$SLURM_JOBID
rm bakTimes.$SLURM_JOBID
i=0
bakArr[0]=-1
echo "Already existing times in bak are:"
while read textTimeDir; do
   bakArr[$i]=$textTimeDir
   echo "The $i timeDir is: ${bakArr[$i]}"
   ((i++))
done < bakTimesSorted.$SLURM_JOBID
nTimeBak=$i
rm bakTimesSorted.$SLURM_JOBID
keepTimesArr[0]=-1
nKeepTimes=0
if [ $nTimeBak -eq 0 ]; then
   echo "NO time directories available in ./bakDir/bak.processor0"
else
   echo "The minTime in bak is ${bakArr[0]} and will be preserved after reconstruction"
   keepTimesArr[$nKeepTimes]=${bakArr[0]};(( nKeepTimes++ )) 
   echo "The maxTime in bak is ${bakArr[$((nTimeBak - 1))]} and will be preserved after reconstruction"
   keepTimesArr[$nKeepTimes]=${bakArr[$((nTimeBak -1))]};(( nKeepTimes++ )) 
fi
## Add other times to the list if desired
#keepTimesArr[$nKeepTimes]=28;(( nKeepTimes++ ))
#keepTimesArr[$nKeepTimes]=29;(( nKeepTimes++ ))
#keepTimesArr[$nKeepTimes]=30;(( nKeepTimes++ ))
echo "All times to be preserved in ./bakDir/bak.processor* are:"
echo "${keepTimesArr[@]}"

#7. Check for already reconstructed cases and build the `-time $timeString` argument for the reconstructPar tool
timeString=""
countRec=0
realToDoReconstruct[$countRec]=-1
for ii in ${!arrayReconstruct[@]}; do
   correctReconstruct[$ii]="true" #Initialising this array to be used in the following subsections (9.)
   timeHere=${arrayReconstruct[ii]}
   if [ -f ${timeHere}/.reconstructDone ]; then
      echo "Time ${timeHere} has already been reconstructed. No reconstruction will be performed"
   else
      timeString="${timeString},${timeHere}"
      realToDoReconstruct[$countRec]=$timeHere
      (( countRec++ ))
   fi
done
echo "Times to be reconstructed are:"
echo "${timeString}"

#8. Reconstruct all available times in a single batch.
if [ $countRec -gt 0 ]; then
   echo "Start reconstruction"
   srun -n 1 -N 1 singularity exec $theImage reconstructPar -time ${timeString} 2>&1 | tee $logsDir/log.reconstructPar.$SLURM_JOBID.all
else
   echo "No additional reconstruction needed"
fi

#9. Mark successfully reconstructed times with the "flag" file: .reconstructDone, and remove the decomposed time results
for ii in ${!arrayReconstruct[@]}; do
   timeHere=${arrayReconstruct[ii]}
   indexInRealTodo=$(getIndex "${timeHere}" "${realToDoReconstruct[@]}")
   if [ $indexInRealTodo -ne -1 ]; then
      ##9.1 Check if reconstruction was successful by looking for errors in the log file
      checkOn="false"
      while IFS= read -r line; do
         if [ "${checkOn}" = "true" ]; then
            if [[ "${line}" == *"error"* ]] || [[ $line == *"Error"* ]] || [[ $line == *"ERROR"* ]]  ; then
               echo "Error in reconstruction:"
               echo "The reconstruction of time ${timeHere} failed"
               correctReconstruct[$ii]="false"
               break
            elif [[ "${line}" == *"Time"* ]]; then
               checkOn="false"
               break
            elif [[ "${line}" == *"End"* ]]; then
               checkOn="false"
               break
            fi
         else
            if [ "${line}" = "Time = $timeHere" ]; then
                echo "Starting check for $timeHere"
                checkOn="true"
            fi
         fi
      done < $logsDir/log.reconstructPar.$SLURM_JOBID.all
   
      ##9.2 If reconstruction was correct, mark the reconstructed folder
      if [ "${correctReconstruct[ii]}" = "true" ]; then
         touch ${timeHere}/.reconstructDone
         echo "Reconstruction finished, and file ${timeHere}/.reconstructionDone created."
      else
         echo "Check why Time ${timeHere} failed in reconstruction"
      fi
   fi
   ##9.3 Deleting decomposed results, except those indicated to be kept
   indexKeep=$(getIndex "${timeHere}" "${keepTimesArr[@]}")
   if [ $indexKeep -eq -1 ]; then
      echo "Removing time ${timeHere} in the ./bakDir/bak.processor* directories"
      for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
         if [ -d ./bakDir/bak.processor${jj}/${timeHere} ]; then
            srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find -P ./bakDir/bak.processor${jj}/${timeHere} -type f -print0 -type l -print0 | xargs -0 munlink &
         fi
      done
      wait
      for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
         if [ -d ./bakDir/bak.processor${jj}/${timeHere} ]; then
            srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find ./bakDir/bak.processor${jj}/${timeHere} -depth -type d -empty -delete &
         fi
      done
      wait
   fi
done

#X. Final step
echo "Script done"
