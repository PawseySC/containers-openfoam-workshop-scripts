#!/bin/bash -l
#SBATCH --ntasks=4
#SBATCH --mem=4G
#SBATCH --clusters=zeus
#SBATCH --partition=copyq #Ideally, use copyq for this process. copyq is on zeus.
#SBATCH --time=0:10:00
#SBATCH --export=none

#0. Initial settings:
unset XDG_RUNTIME_DIR #To avoid some annoying warnings when using some containers
: ${partial_counter:="1"} #Counter of the partial "deposit" of results in overlay* files it is usually defined in a previous calling script

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

#2. Check existence of the case
cd $SLURM_SUBMIT_DIR
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting";exit 1
fi

#3. Check the existence of the directory where the OverlayFS files are going to be kept
if ! [ -d ./overlayFSDir ]; then
   echo "For some reason, the directory ./overlayFSDir for saving the overlay* files does not exists."
   echo "Error. Check what happened."
   echo "Exiting";exit 1
fi

#4. Reading the OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#5. Check the existence of the bak.processor* directories
#(OpenFOAM wont be able to see these directories)
#(Access will be performed through soft links)
if ! [ -d ./bakDir/bak.processor0 ]; then
   echo "Error: The directory ./bakDir/bak.processor0 does not exists"
   echo "Exiting";exit 1
fi

#6. Create the reconstruction array, the intended times to be moved into the new overlay* are set in the reconstructTimes var
#These formats are the only accepted by function "generateReconstructArray" (check the function definition for further information)
#reconstructTimes="all"
#reconstructTimes="-1"
#reconstructTimes="+1"
#reconstructTimes="20"
#reconstructTimes="50,60,70,80,90"
reconstructTimes="-2"
unset arrayReconstruct #This global variable will be re-created in the function below
surnameTag=""
generateReconstructArray "$reconstructTimes" $insideDir $surnameTag;success=$? #Calling fucntion to generate "arrayReconstruct"
if [ $success -ne 0 ]; then
   echo "Failed creating the arrayReconstruct"
   echo "Exiting";exit 1
fi

#7. Copy results to be moved into the new overlay* first into the bak.processor* directories
replace="true"
copyResultsIntoBak "$insideDir" "$foam_numberOfSubdomains" "$replace" "${arrayReconstruct[@]}";success=$? #Calling the function to copy time directories into ./bakDir/bak.processor*
if [ $success -ne 0 ]; then
   echo "Failed transferring $arrayReconstruct[@] decomposed time directories into ./bakDir/bak.processor* directories"
   echo "Exiting";exit 1
fi

#8. Rename the existing overlays as the "deposit" of the partial results
partial_previousCounter=$((partial_counter-1))
newSurnameTag="_${SLURM_JOBID}_${partial_previousCounter}"
echo 'Will try to rename ./overlayFSDir/overlay* into ./overlayFSDir/overlay*_${newSurnameTag} files'
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
    if [ ! -f ./overlayFSDir/overlay${ii} ]; then
       echo "./overlayFSDir/overlay${ii} does not exist"
       echo "There was a problem in the renaming process"
       echo "Exiting";exit 1
    else
       echo "Renaming ./overlayFSDir/overlay${ii} into ./overlayFSDir/overlay${ii}${newSurnameTag}"
       srun -n 1 -N 1 --mem-per-cpu=0 --exclusive mv ./overlayFSDir/overlay${ii} ./overlayFSDir/overlay${ii}_${newSurnameTag}&
    fi
done
wait

#9. Creating again the new first ./overlayFSDir/overlay* file (./overlayFSDir/overlay0)
createOverlay0 $overlaySizeGb;success=$? #Calling the function for creating the ./overlayFSDir/overlay0 file
if [ $success -eq 222 ]; then 
   echo "./overlayFSDir/overlay0 already exists"
   echo "Exiting";exit 1
elif [ $success -ne 0 ]; then 
   echo "Failed creating ./overlayFSDir/overlay0, exiting"
   echo "Exiting";exit 1
fi

#10. Replicating the ./overlayFSDir/overlay0 file into the needed number of ./overlayFSDir/overlay* files (as many as processors*)
echo "Replication ./overlayFSDir/overlay0 into the rest of the ./overlayFSDir/overlay* files"
for ii in $(seq 1 $(( foam_numberOfSubdomains - 1 ))); do
    if [ -f ./overlayFSDir/overlay${ii} ]; then
       echo "./overlayFSDir/overlay${ii} already exists"
       echo "Deal with it first and remove it from the working directory"
       echo "Exiting";exit 1
    else
       echo "Replicating ./overlayFSDir/overlay0 into ./overlayFSDir/overlay${ii}"
       srun -n 1 -N 1 --mem-per-cpu=0 --exclusive cp ./overlayFSDir/overlay0 ./overlayFSDir/overlay${ii} &
    fi
done
wait

#11. Creating the processor* directories inside the ./overlayFSDir/overlay* files
createInsideProcessorDirs $insideDir $foam_numberOfSubdomains;success=$? #Calling the function for creatingthe inside directories 
if [ $success -eq 222 ]; then 
   echo "$insideDir/processor0 already exists inside the ./overlayFSDir/overlay0 file"
   echo "Exiting";exit 1
elif [ $success -ne 0 ]; then 
   echo "Failed creating the inside directories, exiting"
   echo "Exiting";exit 1
fi

#12. Transfer the partial results from the ./bakDir/bak.processor* directories into the ./overlayFSDir/overlay* files
echo "Copying OpenFOAM the partial results inside ./bakDir/bak.processor* into the ./overlayFSDir/overlay* files"
#Calling the function for copying into the ./overlayFSDir/overlay* (see usage instructions in the function definition)
#Note the use of single quotes '...${ii}...' in the place where the number of the overlay${ii} (or processor${ii}) is needed
for timeHere in ${arrayReconstruct[@]}; do
   copyIntoOverlayII './bakDir/bak.processor${ii}/'"$timeHere" "$insideDir/"'processor${ii}/' "$foam_numberOfSubdomains" "true";success=$? 
   if [ $success -ne 0 ]; then 
      echo "Failed copying time directory $timeHere, exiting"
      echo "Exiting";exit 1
   fi
done
copyIntoOverlayII './bakDir/bak.processor${ii}/constant/' "$insideDir/"'processor${ii}/' "$foam_numberOfSubdomains" "true";success=$? 
if [ $success -ne 0 ]; then 
   echo "Failed copying time constant directory, exiting"
   echo "Exiting";exit 1
fi

#13. Remove the time directories that have been copied into the new overlay*
for timeHere in ${arrayReconstruct[@]}; do
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
done

#14. List the content of directories inside the ./overlayFSDir/overlay* files
echo "Listing the content in ./overlayFSDir/overlay0 $insideDir/processor0"
srun -n 1 -N 1 singularity exec --overlay ./overlayFSDir/overlay0 $theImage ls -lat $insideDir/processor0/

#X. Final step
echo "Script done"
