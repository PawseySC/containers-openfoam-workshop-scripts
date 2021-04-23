#!/bin/bash -l
#-----------------------
##Defining the needed resources with SLURM parameters (modify as needed)
#SBATCH --job-name=checkMissing
#SBATCH --output="%x---%j.out"
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=28
#SBATCH --cluster=zeus
#SBATCH --partition=copyq
#SBATCH --time=0:10:00
#SBATCH --export=none

#========================
echo '#0. Initial settings:'
unset XDG_RUNTIME_DIR #To avoid some annoying warnings when using some containers

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
echo "#4. Identifying the overlay files to check"
i=0
surnamesList[0]=""
surnamesNeeded[0]="false" #Initialised in false, updated when submission, checked at the end
((i++))
for jj in $(ls ${caseDir}/overlayFSDir/overlay0_*);do
   surnamesList[$i]=$(echo ${jj#*lay0})
   surnamesNeeded[$i]="false"
   ((i++))
done
echo "Overlay files to check are:"
for jj in ${!surnamesList[@]}; do
   surnameTag=${surnamesList[jj]}
   echo "overlay0${surnameTag}"
done

#========================
echo "#5. Point the soft links to the ./bakDir/bak.processor* directories"
pointToBak $foam_numberOfSubdomains;success=$? #Calling function to point towards the ./bakDir/bak.processors
if [ $success -ne 0 ]; then
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#========================
echo "#6. Checking which overlays still need some times to be reconstructed"
#@@for jj in $(seq 0 4); do
for jj in ${!surnamesList[@]}; do
   surnameTag=${surnamesList[jj]}
   #---------
   echo "#6.1 Create reconstruction array for file overlay0${surnameTag}"
   cd $caseDir
   #(intended times to be reconstructed are set with $reconstructTimes)
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

   #---------
   echo "#6.2 Check for already reconstructed cases for overlay0${surnameTag}" 
   countRec=0
   unset realToDoReconstruct
   unset correctReconstruct
   realToDoReconstruct[$countRec]=-1
   for ii in ${!arrayReconstruct[@]}; do
      correctReconstruct[$ii]="true" 
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

   #---------
   echo "#6.3 File overlay0${surnameTag} still needs reconstruction"
   if [ $countRec -gt 0 ]; then
      echo "YES need for reconstruction for results in: ./overlayFSDir/overlay0${surnameTag} file" 
      surnamesNeeded[$jj]="true"
   else
      echo "NO reconstruction needed for results in: ./overlayFSDir/overlay0${surnameTag} file" 
   fi
done

#========================
echo "#X. Final step"
echo "Overlay files that still need further reconstructions:"
for jj in ${!surnamesList[@]}; do
   surnameTag=${surnamesList[jj]}
   if [ "${surnamesNeeded[jj]}" == "true" ]; then
      echo "    file: overlay0${surnameTag}"
      echo "    Check the text in this output file with the word/mark in capitals \"YES\" above"
      echo "    Above that mark, the times that still need reconstruction for this file are listed"
   fi
done

echo "Script done"
