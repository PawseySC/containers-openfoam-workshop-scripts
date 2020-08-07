#!/bin/bash -l
#SBATCH --ntasks=4
#SBATCH --mem=4G
#SBATCH --clusters=zeus
#SBATCH --partition=copyq #Ideally, use copyq for this process. copyq is on zeus.
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

#2. Check existence of the case
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting";exit 1
fi

#3. Create the directory where the OverlayFS files are going to be kept
if ! [ -d ./overlayFSDir ]; then
   echo "Creating the directory ./overlayFSDir which will contain the overlay* files:"
   mkdir -p ./overlayFSDir
else
   echo "For some reason, the directory ./overlayFSDir for saving the overlay* files already exists:"
   echo "Warning:No creation needed"
fi

#4. Reading the OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#5. Rename the processor* directories into bak.processor* and move them into ./bakDir
#(OpenFOAM wont be able to see these directories)
#(Access will be performed through soft links)
echo "Renaming the processor directories"
rename processor bak.processor processor*
if ! [ -d ./bakDir ]; then
   echo "Creating the directory ./bakDir that will contain the bak.processor* directories:"
   mkdir -p ./bakDir
else
   echo "For some reason, the directory ./bakDir for containing the bak.processor* dirs already exists:"
   echo "Warning:No creation needed"
fi

if ! [ -d ./bakDir/bak.processor0 ]; then
   echo "Moving all bak.processor* directories into ./bakDir"
   mv bak.processor* ./bakDir
else
   echo "The directory ./bakDir/bak.processor0 already exists"
   echo "No move/replacement of bak.processor* directories will be performed"
   echo "Exiting";exit 1
fi

#6. Creating a first ./overlayFSDir/overlayII file (./overlayFSDir/overlay0)
createOverlay0 $overlaySizeGb;success=$? #Calling the function for creating the ./overlayFSDir/overlay0 file
if [ $success -eq 222 ]; then 
   echo "./overlayFSDir/overlay0 already exists"
   echo "Exiting";exit 1
elif [ $success -ne 0 ]; then 
   echo "Failed creating ./overlayFSDir/overlay0, exiting"
   echo "Exiting";exit 1
fi

#7. Replicating the ./overlayFSDir/overlay0 file into the needed number of ./overlayFSDir/overlay* files (as many as processors*)
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

#8. Creating the processor* directories inside the ./overlayFSDir/overlay* files
createInsideProcessorDirs $insideDir $foam_numberOfSubdomains;success=$? #Calling the function for creatingthe inside directories 
if [ $success -eq 222 ]; then 
   echo "$insideDir/processor0 already exists inside the ./overlayFSDir/overlay0 file"
   echo "Exiting";exit 1
elif [ $success -ne 0 ]; then 
   echo "Failed creating the inside directories, exiting"
   echo "Exiting";exit 1
fi

#9. Transfer the content of the ./bakDir/bak.processor* directories into the ./overlayFSDir/overlay* files
echo "Copying OpenFOAM the files inside ./bakDir/bak.processor* into the ./overlayFSDir/overlay* files"
#Calling the function for copying into the ./overlayFSDir/overlay* (see usage instructions in the function definition)
#Note the use of single quotes for passing the wildcard '*' to the function without evaluation
#Also note the use of single quotes '...${ii}...' in the place where the number of the overlay${ii} (or processor${ii}) is needed
copyIntoOverlayII './bakDir/bak.processor${ii}/*' "$insideDir/"'processor${ii}/' "$foam_numberOfSubdomains" "true";success=$? 
if [ $success -ne 0 ]; then 
   echo "Failed creating the inside directories, exiting"
   echo "Exiting";exit 1
fi

#10. Mark the initial conditions time directory as already fully reconstructed
echo "Marking the time directory \"0\" as fully reconstructed"
touch 0/.reconstructDone

#11. List the content of directories inside the ./overlayFSDir/overlay* files
echo "Listing the content in ./overlayFSDir/overlay0 $insideDir/processor0"
srun -n 1 -N 1 singularity exec --overlay ./overlayFSDir/overlay0 $theImage ls -lat $insideDir/processor0/

#X. Final step
echo "Script done"
