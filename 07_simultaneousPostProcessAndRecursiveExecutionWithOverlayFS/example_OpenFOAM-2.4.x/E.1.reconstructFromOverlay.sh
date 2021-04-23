#!/bin/bash -l
#SBATCH --job-name=reconstructFromOverlay
#SBATCH --output=%x---%j.out
#SBATCH --ntasks=4
#SBATCH --mem=4G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --time=0:10:00
#SBATCH --partition=workq
#SBATCH --export=none

#========================
echo '#0. Initial settings:'
unset XDG_RUNTIME_DIR #To avoid some annoying warnings when using some containers
: ${surnameTag:=""}

#========================
echo '#1. Loading the container settings, case settings and auxiliary functions (order is important)'
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh
overlayFunctionsScript=$auxScriptsDir/ofContainersOverlayFunctions.sh
if [ -f "$overlayFunctionsScript" ]; then 
   source $overlayFunctionsScript
else
   echo "The script for the functions to manage OverlaFS files: $overlayFunctionsScript was not found"
   echo "Exiting"; exit 1
fi

#========================
echo '#2. Going into the case and creating the logs directory'
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=$caseDir/logs/post
if ! [ -d $logsDir ]; then
   mkdir -p $logsDir
fi

#========================
echo '#3. Reading OpenFOAM decomposeParDict settings'
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#========================
echo '#4. Create the reconstruction directory and cd into it'
: ${reconstructDir:="${caseDir}/reconstructDir/${SLURM_JOB_NAME}"}
if ! [ -d $reconstructDir ]; then
   mkdir -p $reconstructDir
   ln -s ${caseDir}/system ${reconstructDir}/system
   ln -s ${caseDir}/constant ${reconstructDir}/constant
   ln -s ${caseDir}/overlayFSDir ${reconstructDir}/overlayFSDir
   for ii in $(seq 0 $((foam_numberOfSubdomains - 1))); do
      if ! [ -d ${reconstructDir}/bakDir/bak.processor${ii} ]; then
         mkdir -p ${reconstructDir}/bakDir/bak.processor${ii} 
      fi
      ln -s ${caseDir}/bakDir/bak.processor${ii}/constant ${reconstructDir}/bakDir/bak.processor${ii}/constant
   done
fi
cd $reconstructDir

#========================
echo '#5. Create reconstruction array (intended times to be reconstructed are set with $reconstructTimes)'
#IMPORTANT: Note the use of : ${var:="value"} bash syntax. This allows to receive this variable
#           from a parent script, or as an "exported" value when submitting this script.
#           This is useful for recursive jobs.
#ALSO: The formats inside the apostrophes ("format") are the only accepted by function:
#      "generateReconstructArray" (check the function definition for further information)
: ${reconstructTimes:="all"}
#: ${reconstructTimes:="-2"}
#: ${reconstructTimes:="+2"}
#: ${reconstructTimes:="20"}
#: ${reconstructTimes:="50,60,70,80,90"}
#: ${reconstructTimes:="0:10"}
#: ${reconstructTimes:="10:24"}
unset arrayReconstruct #This global variable will be re-created in the function below
generateReconstructArray "$reconstructTimes" $insideDir $surnameTag;success=$? #Calling fucntion to generate "arrayReconstruct"
if [ $success -ne 0 ]; then
   echo "Failed creating the arrayReconstruct"
   echo "Exiting";exit 1
fi

#========================
#6. Point the soft links to the ./bakDir/bak.processor* directories
pointToBak $foam_numberOfSubdomains;success=$? #Calling function to point towards the ./bakDir/bak.processors
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#========================
#7. Define the directories to be preserved (and not removed after reconst) in the ./bakDir/bak.processor*
##7.1 Generate a list of the time directories already inside ./bakDir/bak.processor*
ls -dt ${reconstructDir}/bakDir/bak.processor0/[0-9]* | sed "s,${reconstructDir}/bakDir/bak.processor0/,," > bakTimes.$SLURM_JOBID
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
## Decide if we want to keep the first and last times in the ./bakDir/bak.processor* decomposed directories
keepFirstAndLast=false
if [ "$keepFirstAndLast" = "true" ]; then
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
fi
## Add other times to the list if desired
#keepTimesArr[$nKeepTimes]=28;(( nKeepTimes++ ))
#keepTimesArr[$nKeepTimes]=29;(( nKeepTimes++ ))
#keepTimesArr[$nKeepTimes]=30;(( nKeepTimes++ ))
echo "All times to be preserved in ${reconstructDir}/bakDir/bak.processor* are:"
echo "${keepTimesArr[@]}"

#========================
#8. Check for already reconstructed cases and set the `-time $timeString` argument for the reconstructPar tool
countRec=0
realToDoReconstruct[$countRec]=-1
for ii in ${!arrayReconstruct[@]}; do
   correctReconstruct[$ii]="true" #Initialising this array to be used in the following subsections: (12.,)
   timeHere=${arrayReconstruct[ii]}
   if [ -f ${caseDir}/${timeHere}/.reconstructDone ]; then
      echo "Time ${timeHere} has already been reconstructed in ${caseDir}. No reconstruction will be performed"
   else
      realToDoReconstruct[$countRec]=$timeHere
     (( countRec++ ))
   fi
done
echo "Times to be reconstructed are:"
echo "${realToDoReconstruct[@]}"

#========================
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
      #---------
      ## 9. Create the batch to reconstruct
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

      #---------
      ## 10. Copy from the ./overlayFSDir/overlay* the full batch into ./bakDir/bak.processor*
      unset arrayCopyIntoBak
      arrayCopyIntoBak=("${hereToDoReconstruct[@]}")
      replace="true"
      copyResultsIntoBak "$insideDir" "$surnameTag" "$foam_numberOfSubdomains" "$replace" "${arrayCopyIntoBak[@]}";success=$? #Calling the function to copy time directories into ./bakDir/bak.processor*
      if [ $success -ne 0 ]; then
         echo "Failed transferring files into ./bakDir/bak.processor* directories"
         echo "Exiting";exit 1
      fi
      
      #---------
      ## 11. Reconstruct all times for this batch.
      echo "Start reconstruction of timeString=$timeString"
      logFileHere=$logsDir/log.reconstructPar.${SLURM_JOBID}_${hereToDoReconstruct[0]}-${hereToDoReconstruct[-1]}
      srun -n 1 -N 1 singularity exec $theImage reconstructPar -time ${timeString} 2>&1 | tee $logFileHere
      
      #---------
      ## 12. Mark successfully reconstructed times with the "flag" file: .reconstructDone, and remove the decomposed time results, and move the reconstructed results to the case directory
      noErrors="true"
      for ii in ${!arrayReconstruct[@]}; do
         timeHere=${arrayReconstruct[ii]}
         indexInHereTodo=$(getIndex "${timeHere}" "${hereToDoReconstruct[@]}")
         if [ $indexInHereTodo -ne -1 ]; then
            ###12.1 Check if reconstruction was successful by looking for errors in the log file
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
         
            ###12.2 If reconstruction was correct, mark the reconstructed folder
            if [ "${correctReconstruct[ii]}" = "true" ]; then
               if [ -d ${reconstructDir}/${timeHere} ]; then
                  touch ${reconstructDir}/${timeHere}/.reconstructDone
                  echo "Reconstruction finished, and file ${timeHere}/.reconstructionDone created."
                  echo "Moving the whole directory ${timeHere} to ${caseDir}"
                  mv "${reconstructDir}/${timeHere}" "${caseDir}/${timeHere}"
                  if [ ! -f ${caseDir}/${timeHere}/.reconstructDone ]; then
                     echo "${caseDir}/${timeHere}/.reconstructDone was not found"
                     noErrors="false"
                  fi
               else
                  echo "The directory ${reconstructDir}/${timeHere} does not exist"
                  noErrors="false"
               fi
            else
               echo "Check why Time ${timeHere} failed in reconstruction"
               noErrors="false"
            fi
         fi
      done

      #---------
      ## 13. Remove the decomposed time results if they have been successfully reconstructed (except those indicated to be kept)
      if [ "${noErrors}" = "true" ]; then
         for ii in ${!arrayReconstruct[@]}; do
            timeHere=${arrayReconstruct[ii]}
            indexKeep=$(getIndex "${timeHere}" "${keepTimesArr[@]}")
            if [ $indexKeep -eq -1 ] && \
               [ $(echo "$timeHere <= ${realToDoReconstruct[((kNext-1))]}" | bc -l) -eq 1 ] && \
               [ $(echo "$timeHere >= ${realToDoReconstruct[$kStart]}" | bc -l) -eq 1 ]; then
               echo "Removing time ${timeHere} in the ./bakDir/bak.processor* directories"
               usedCores=0
               for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
                  if [ -d ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} ]; then
                     srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find -P ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} -type f -print0 -type l -print0 | xargs -0 munlink &
                     (( usedCores++ ))
                  fi
                  if [ $usedCores -ge $SLURM_NTASKS ]; then
                     wait
                     usedCores=0
                  fi
               done
               wait
               usedCores=0
               for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
                  if [ -d ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} ]; then
                     srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} -depth -type d -empty -delete &
                     (( usedCores++ ))
                  fi
                  if [ $usedCores -ge $SLURM_NTASKS ]; then
                     wait
                     usedCores=0
                  fi
               done
               wait
            fi
         done
      else
         echo "There were some errors during reconstruction. This script will stop here"
         echo "Please check the log files to investigate the possible sources of reconstruction errors"
         echo "Decomposed results currently in the host will not be removed to assist with the investigation"
         echo "Warning message: Warn Recursive Jobs, and stop if error keeps repeating"
         echo "Exiting"; exit 1
      fi
      kStart=$kNext
   done
else
   echo "The times asked to be reconstructed are already reconstructed."
fi

#========================
#14. As a final step, remove any decomposed time result that was left in the host file system, but to be removed
#    (as it was already reconstructed successfully and is not indicated to be kept)
##14.0 Check if there are times left in ./bakDir/bak.processor* directories (asking for the last one here)
echo "Check for leftovers left in the ./abkDir/bak.processor* directories"
lastTimeReached=$(getNResultTime -1 "bak");success=$? #Calling function to obtain the Last Time result available (-1)
echo "lastTimeReached=$lastTimeReached"
if [ $lastTimeReached -eq -1 ]; then
   echo "The ./bakDir/bak.processor* directories have no more results saved within"
   echo "Nothing else to be removed from the file system"
else
   #---------
   ##14.1 Generating the array of existing decomposed times in the local host
   unset arrayReconstruct #This global variable will be re-created in the function below
   generateReconstructArray "$reconstructTimes" $insideDir $surnameTag;success=$? #Calling fucntion to generate "arrayReconstruct"
   if [ $success -ne 0 ]; then
      echo "Failed creating the arrayReconstruct"
      echo "Exiting";exit 1
   fi
   cleanRangeFirst=${arrayReconstruct[0]}
   cleanRangeLast=${arrayReconstruct[-1]}
   unset arrayReconstruct #This global variable will be re-created in the function below
   generateReconstructArray "$cleanRangeFirst:$cleanRangeLast" "bak";success=$? #Calling function to generate "arrayReconstruct"
   if [ $success -ne 0 ]; then
      echo "Failed creating the arrayReconstruct"
      echo "Exiting";exit 1
   fi
   #---------
   ##14.2 Deleting decomposed results, except those indicated to be kept
   for ii in ${!arrayReconstruct[@]}; do
      timeHere=${arrayReconstruct[ii]}
      indexKeep=$(getIndex "${timeHere}" "${keepTimesArr[@]}")
      if [ -f ${reconstructDir}/${timeHere}/.reconstructDone ]; then
         mv ${reconstructDir}/${timeHere} ${caseDir}/${timeHere}
      fi
      if [ $indexKeep -eq -1 ]; then
         if [ -f ${caseDir}/${timeHere}/.reconstructDone ]; then
            echo "Removing time ${timeHere} in the ./bakDir/bak.processor* directories"
            usedCores=0
            for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
               if [ -d ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} ]; then
                  srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find -P ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} -type f -print0 -type l -print0 | xargs -0 munlink &
                  (( usedCores++ ))
               fi
               if [ $usedCores -ge $SLURM_NTASKS ]; then
                  wait
                  usedCores=0
               fi
            done
            wait
            usedCores=0
            for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
               if [ -d ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} ]; then
                  srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find ${reconstructDir}/bakDir/bak.processor${jj}/${timeHere} -depth -type d -empty -delete &
                  (( usedCores++ ))
               fi
               if [ $usedCores -ge $SLURM_NTASKS ]; then
                  wait
                  usedCores=0
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
fi

#========================
#15. If working recursively, send the Finishing message if there was no reconstruction executed
if [ $countRec -eq 0 ]; then
   echo "No times were marked to reconstruction in this job"
   echo "Times to be reconstructed = ${realToDoReconstruct[@]}"
   echo "Therefore, if there is any recursive call for reconstruction it can be considered finished"
   echo "Finish message: Finish Recursive Jobs, if any"
fi

#========================
#X. Final step
echo "Script done"
