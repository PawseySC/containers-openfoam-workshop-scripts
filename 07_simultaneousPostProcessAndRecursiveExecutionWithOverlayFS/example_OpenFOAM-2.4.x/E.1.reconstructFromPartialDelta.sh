#!/bin/bash -l
#SBATCH --ntasks=4
#SBATCH --mem=4G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --time=0:10:00
#SBATCH --partition=workq
#SBATCH --export=none

#0. Initial settings:
unset XDG_RUNTIME_DIR #To avoid some annoying warnings when using some containers
: ${surnameTag:=""}
#: ${surnameTag:="_1234567_0"}

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

#4. Create the reconstruction array, intended times to be reconstructed are set with the reconstructTimes var
#These formats are the only accepted by function "generateReconstructArray" (check the function definition for further information)
reconstructTimes="all"
#reconstructTimes="-2"
#reconstructTimes="+2"
#reconstructTimes="20"
#reconstructTimes="50,60,70,80,90"
#reconstructTimes="0:10"
#reconstructTimes="10:24"
unset arrayReconstruct #This global variable will be re-created in the function below
generateReconstructArray "$reconstructTimes" $insideDir $surnameTag;success=$? #Calling fucntion to generate "arrayReconstruct"
if [ $success -ne 0 ]; then
   echo "Failed creating the arrayReconstruct"
   echo "Exiting";exit 1
fi

#5. Point the soft links to the ./bakDir/bak.processor* directories
pointToBak $foam_numberOfSubdomains;success=$? #Calling function to point towards the ./bakDir/bak.processors
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#6. Generate a list of the time directories already inside ./bakDir/bak.processor* to be preserved and not removed after reconstruction
#   (The earlier and latest times will be preserved)
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
   echo "The minTime already in bak is ${bakArr[0]}"
   echo "The minTime to be reconstructed is ${arrayReconstruct[0]}"
   if [ $(echo "${bakArr[0]} < ${arrayReconstruct[0]}" | bc -l) -eq 1 ]; then
      keepTimesArr[$nKeepTimes]=${bakArr[0]};(( nKeepTimes++ )) 
   else
      keepTimesArr[$nKeepTimes]=${arrayReconstruct[0]};(( nKeepTimes++ )) 
   fi
   echo "Time ${keepTimesArr[$((nKeepTimes-1))]} will be preserved after reconstruction"
   echo "The maxTime already in bak is ${bakArr[-1]}"
   echo "The maxTime to be reconstructed is ${arrayReconstruct[-1]}"
   if [ $(echo "${bakArr[-1]} > ${arrayReconstruct[-1]}" | bc -l) -eq 1 ]; then
      keepTimesArr[$nKeepTimes]=${bakArr[-1]};(( nKeepTimes++ )) 
   else
      keepTimesArr[$nKeepTimes]=${arrayReconstruct[-1]};(( nKeepTimes++ )) 
   fi
   echo "Time ${keepTimesArr[$((nKeepTimes-1))]} will be preserved after reconstruction"
fi
## Add other times to the list if desired
#keepTimesArr[$nKeepTimes]=28;(( nKeepTimes++ ))
#keepTimesArr[$nKeepTimes]=29;(( nKeepTimes++ ))
#keepTimesArr[$nKeepTimes]=30;(( nKeepTimes++ ))
echo "All times to be preserved in ./bakDir/bak.processor* are:"
echo "${keepTimesArr[@]}"

#7. Check for already reconstructed cases and set the `-time $timeString` argument for the reconstructPar tool
countRec=0
realToDoReconstruct[$countRec]=-1
for ii in ${!arrayReconstruct[@]}; do
   correctReconstruct[$ii]="true" #Initialising this array to be used in the following subsections (9.)
   timeHere=${arrayReconstruct[ii]}
   if [ -f ${timeHere}/.reconstructDone ]; then
      echo "Time ${timeHere} has already been reconstructed. No reconstruction will be performed"
   else
      realToDoReconstruct[$countRec]=$timeHere
     (( countRec++ ))
   fi
done
echo "Times to be reconstructed are:"
echo "${realToDoReconstruct[@]}"

#----------------------------------------------
#NOTE: Executing the following steps in batches within a while loop.
#      In each cycle of the loop, a batch of size $maxTimeTransfersFromOverlays will be processed.
#----------------------------------------------
if [ $countRec -gt 0 ]; then
   maxTimeTransfersFromOverlays=10
   kStart=0
   kNext=0
   unset leftToDoReconstruct
   leftToDoReconstruct=("${realToDoReconstruct[@]}")
   while [ $kStart -lt ${#realToDoReconstruct[@]} ]; do
      ## 8. Create the batch to reconstruct
      timeString=""
      countHere=0
      unset hereToDoReconstruct
      hereToDoReconstruct[$countHere]=-1
      countLeft=0
      unset auxToDo
      auxToDo[$countLeft]=-1
      if [ $(echo "${leftToDoReconstruct[0]} >= 0" | bc -l) -eq 1 ]; then
         for ii in ${!leftToDoReconstruct[@]}; do
            timeHere=${leftToDoReconstruct[ii]}
            if [ $ii -lt $maxTimeTransfersFromOverlays ]; then
               timeString="${timeString},${timeHere}"
               hereToDoReconstruct[$countHere]=$timeHere
               (( countHere++ ))
            else
               auxToDo[$countLeft]=$timeHere
               (( countLeft++ ))
            fi
         done
         unset leftToDoReconstruct
         leftToDoReconstruct=("${auxToDo[@]}")
         echo "Times to be reconstructed in this batch are:"
         echo "${timeString}"
      else
         echo "No more times left to do"
         echo "Breaking the cycle of reconstruction"
         break
      fi
      if [ $countHere -eq 0 ]; then
         echo "The number of times to reconstruct is countRec=$countRec"
         echo "Breaking the cycle of reconstruction"
         break
      else
         (( kNext = kStart + countHere ))
         echo "kStart=$kStart"
         echo "kNext=$kNext"
      fi

      ## 9. Copy from the ./overlayFSDir/overlay* the full batch into ./bakDir/bak.processor*
      unset arrayCopyIntoBak
      arrayCopyIntoBak=("${hereToDoReconstruct[@]}")
      replace="true"
      copyResultsIntoBak "$insideDir" "$surnameTag" "$foam_numberOfSubdomains" "$replace" "${arrayCopyIntoBak[@]}";success=$? #Calling the function to copy time directories into ./bakDir/bak.processor*
      if [ $success -ne 0 ]; then
         echo "Failed transferring files into ./bakDir/bak.processor* directories"
         echo "Exiting";exit 1
      fi
      
      ## 10. Reconstruct all times for this batch.
      echo "Start reconstruction"
      logFileHere=$logsDir/log.reconstructPar.${SLURM_JOBID}_${hereToDoReconstruct[0]}-${hereToDoReconstruct[-1]}
      srun -n 1 -N 1 singularity exec $theImage reconstructPar -time ${timeString} 2>&1 | tee $logFileHere
      
      ## 11. Mark successfully reconstructed times with the "flag" file: .reconstructDone, and remove the decomposed time results
      noErrors="true"
      for ii in ${!arrayReconstruct[@]}; do
         timeHere=${arrayReconstruct[ii]}
         indexInHereTodo=$(getIndex "${timeHere}" "${hereToDoReconstruct[@]}")
         if [ $indexInHereTodo -ne -1 ]; then
            ###11.1 Check if reconstruction was successful by looking for errors in the log file
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
            done < $logFileHere
         
            ###11.2 If reconstruction was correct, mark the reconstructed folder
            if [ "${correctReconstruct[ii]}" = "true" ]; then
               touch ${timeHere}/.reconstructDone
               echo "Reconstruction finished, and file ${timeHere}/.reconstructionDone created."
            else
               echo "Check why Time ${timeHere} failed in reconstruction"
               noErrors="false"
            fi
         fi
      done
      ## 12. Remove the decomposed time results if they have been successfully reconstructed (except those indicated to be kept)
      if [ "${noErrors}" = "true" ]; then
         for ii in ${!arrayReconstruct[@]}; do
            timeHere=${arrayReconstruct[ii]}
            indexKeep=$(getIndex "${timeHere}" "${keepTimesArr[@]}")
            if [ $indexKeep -eq -1 ] && \
               [ $(echo "$timeHere <= ${realToDoReconstruct[((kNext-1))]}" | bc -l) -eq 1 ] && \
               [ $(echo "$timeHere >= ${realToDoReconstruct[$kStart]}" | bc -l) -eq 1 ]; then
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
      else
         echo "There were some errors during reconstruction. This script will stop here"
         echo "Please check the log files to investigate the possible sources of reconstruction errors"
         echo "Decomposed results currently in the host will not be removed to assist with the investigation"
         echo "Exiting"; exit 1
      fi
      kStart=$kNext
   done
else
   echo "The times asked to be reconstructed are already reconstructed"
fi

#13. As a final step, remove any decomposed time result that was left in the host file system, but to be reomoved
#    (as it was already reconstructed successfully and is not indicated to be kept)
##13.1 Generating the array of existing decomposed times in the local host
unset arrayReconstruct #This global variable will be re-created in the function below
generateReconstructArray "${keepTimesArr[0]}:${keepTimesArr[-1]}" "bak";success=$? #Calling function to generate "arrayReconstruct"
if [ $success -ne 0 ]; then
   echo "Failed creating the arrayReconstruct"
   echo "Exiting";exit 1
fi
##13.2 Deleting decomposed results, except those indicated to be kept
for ii in ${!arrayReconstruct[@]}; do
   timeHere=${arrayReconstruct[ii]}
   indexKeep=$(getIndex "${timeHere}" "${keepTimesArr[@]}")
   if [ $indexKeep -eq -1 ]; then
      if [ -f ${timeHere}/.reconstructDone ]; then
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
      else
         echo "Cannot remove time ${timeHere} in the ./bakDir/bak.processor* directories"
         echo "Because the reconstruction is not marked with ${timeHere}/.reconstructDone"
         echo "Something has gone wrong. Please revise the log files to catch the problem"
         echo "Exiting"; exit 1
      fi 
   fi
done

#X. Final step
echo "Script done"
