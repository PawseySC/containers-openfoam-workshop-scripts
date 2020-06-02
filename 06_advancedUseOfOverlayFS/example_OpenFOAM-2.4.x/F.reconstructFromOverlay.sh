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
#reconstructTimes="all"
#reconstructTimes="-1"
#reconstructTimes="20"
#reconstructTimes="50,60,70,80,90"
reconstructTimes="5.5:12.5"
unset arrayReconstruct #This global variable will be re-created in the function below
generateReconstructArray "$reconstructTimes" "$insideDir";success=$? #Calling fucntion to generate "arrayReconstruct"
if [ $success -ne 0 ]; then
   echo "Failed creating the arrayReconstruct"
   echo "Exiting";exit 1
fi

#5. Point the soft links to the bak.processor* directories
pointToBak $foam_numberOfSubdomains;success=$? #Calling function to point towards the bak.processors
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#6. Reconstruct times One by One to avoid the presence of many files and to have more control of
#   successful reconstructions.
#   Successful reconstructions will have a dummy file ".reconstructDone" within the reconstructed directory
#   After reconstruction, time directories will be removed from bak.processor*, unless indicated in the keepArray

## 6.1 Generate a list times in bak.processor directories to be preserved and not removed after reconstruction
ls -dt bak.processor0/[0-9]* | sed "s,bak.processor0/,," > bakTimes.$SLURM_JOBID
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
   echo "NO time directories available in bak.processor0"
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
echo "All times to be preserved in bak.processor* are:"
echo "${keepTimesArr[@]}"

## 6.2 Reconstruct and remove times after reconstruction from bak.processors* if not in the keepTimesArr
for ii in ${!arrayReconstruct[@]}; do
   timeHere=${arrayReconstruct[ii]}
   if [ -f ${timeHere}/.reconstructDone ]; then
      echo "Time ${timeHere} has already been reconstructed. No reconstruction will be performed"
   else
      echo "Time ${timeHere} will be reconstructed"
      ##6.2.1 Transfer times from overlays to .bak directories
      unset arrayCopyIntoBak
      arrayCopyIntoBak[0]="${timeHere}"
      replace="true"
      copyIntoBak "$insideDir" "$foam_numberOfSubdomains" "$replace" "${arrayCopyIntoBak[@]}";success=$? #Calling the function to copy time directories into bak.processor*
      if [ $success -ne 0 ]; then
         echo "Failed transferring files into bak.processor* directories"
         echo "Exiting";exit 1
      fi

      ##6.2.2 Execute the reconstruction
      echo "Start reconstruction"
      srun -n 1 -N 1 singularity exec $theImage reconstructPar -time ${timeHere} 2>&1 | tee $logsDir/log.reconstructPar.$SLURM_JOBID.${timeHere} 
      if grep -i 'error\|exiting' $logsDir/log.reconstructPar.$SLURM_JOBID.${timeHere}; then
         echo "The reconstruction of time ${timeHere} failed"
      else
         touch ${timeHere}/.reconstructDone
         echo "Reconstruction finished, and file ${timeHere}/.reconstructionDone created."
      fi
   fi

   ##6.2.3 Remove the files from the bak.processor* directories 
   indexKeep=$(getIndex "${timeHere}" "${keepTimesArr[@]}")
   if [ $indexKeep -eq -1 ]; then
      echo "Removing time ${timeHere} in the bak.processor* directories"
      for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
         if [ -d bak.processor${jj}/${timeHere} ]; then
            srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find -P bak.processor${jj}/${timeHere} -type f -print0 -type l -print0 | xargs -0 munlink &
         fi
      done
      wait
      for jj in $(seq 0 $((foam_numberOfSubdomains -1))); do
         if [ -d bak.processor${jj}/${timeHere} ]; then
            srun -n 1 -N 1 --mem-per-cpu=0 --exclusive find bak.processor${jj}/${timeHere} -depth -type d -empty -delete &
         fi
      done
      wait
   else
      echo "Time ${timeHere} in the bak.processor* directories will be preserved"
   fi
done

#X. Final step
echo "Script done"
