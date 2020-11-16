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
logsDir=$caseDir/logs/post
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
reconstructTimes="10:20"
unset arrayReconstruct #This global variable will be re-created in the function below
generateReconstructArray "$reconstructTimes" $insideDir;success=$? #Calling fucntion to generate "arrayReconstruct"
if [ $success -ne 0 ]; then
   echo "Failed creating the arrayReconstruct"
   echo "Exiting";exit 1
fi

#5. Generate a list of times that already exist in the ./bakDir/bak.processor directories
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
if [ $nTimeBak -eq 0 ]; then
   echo "NO time directories available in ./bakDir/bak.processor0"
else
   echo "The minTime already in bak is ${bakArr[0]}"
   echo "The minTime to be transferred is ${arrayReconstruct[0]}"
   echo "The maxTime already in bak is ${bakArr[-1]}"
   echo "The maxTime to be transferred is ${arrayReconstruct[-1]}"
fi

#6. Check for the times that really need to be extracted
countRec=0
realToDoReconstruct[$countRec]=-1
for ii in ${!arrayReconstruct[@]}; do
   timeHere=${arrayReconstruct[ii]}
   if [ -f ${timeHere}/.reconstructDone ]; then
      echo "Time ${timeHere} has already been reconstructed. No extraction from the ./overlayFSDir/overlay* will be performed"
      echo "If you still need that time to be extracted, do it manually or in other script"
   else
      realToDoReconstruct[$countRec]=$timeHere
      (( countRec++ ))
   fi
done
echo "Times to be copied from the /overlayFSDir/overlay* are:"
echo "${realToDoReconstruct[@]}"

#7. Copy times from ./overlayFSDir/overlay* into ./bakDir/bak.processors* if not already successfully reconstructed
maxTimeTransfersFromOverlays=10
for ii in ${!realToDoReconstruct[@]}; do
   if [ $ii -ge $maxTimeTransfersFromOverlays ]; then
      echo "Warning: current copy would try to transfer $countRec times from the ./overlayFSDir/overlay* files"
      echo "This script is set to allow maxTimeTransfersFromOverlays=$maxTimeTransfersFromOverlays"
      echo "The limit has been reached. No more transfers will be performed."
      echo "We recommend you to postprocess (reconstruct) the already transferred results first before trying again to copy more results into the host file system"
      echo "Remember that the goal of all this effort is to keep a low number of files in the host file system."
      echo "Exiting"; exit 0
   fi
   timeHere=${realToDoReconstruct[ii]}
   echo "Time ${timeHere} will be copied into bak"
   ##6.2.1 Transfer result time directories from ./overlayFSDir/overlay* files to ./bakDir/bak.processor* directories
   unset arrayCopyIntoBak
   arrayCopyIntoBak[0]="${timeHere}"
   replace="true"
   copyResultsIntoBak "$insideDir" "$foam_numberOfSubdomains" "$replace" "${arrayCopyIntoBak[@]}";success=$? #Calling the function to copy time directories into ./bakDir/bak.processor*
   if [ $success -ne 0 ]; then
      echo "Failed transferring $arrayCopyIntoBak[@] decomposed time directories into ./bakDir/bak.processor* directories"
      echo "Exiting";exit 1
   fi
done

#X. Final step
echo "Script done"
