#!/bin/bash -l
#SBATCH --ntasks=4
#SBATCH --mem=4G
#SBATCH --partition=copyq
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

#3. Reading the OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#4. Rename the processor* directories into bak.processor*
#(OpenFOAM wont be able to see these directories)
#(Access will be performed through soft links)
echo "Renaming the processor directories"
rename processor bak.processor processor*

#5. Creating a first overlay file (overlay0)
createOverlay0 $overlaySizeGb;success=$? #Calling the function for creating the overlay0 file
if [ $success -eq 222 ]; then 
   echo "overlay0 already exists"
   echo "Exiting";exit 1
elif [ $success -ne 0 ]; then 
   echo "Failed creating overlay0, exiting"
   echo "Exiting";exit 1
fi

#6. Replicating the overlay0 file into the needed number of overlay* files (as many as processors*)
echo "Replication overlay0 into the rest of the overlay* files"
for ii in $(seq 1 $(( foam_numberOfSubdomains - 1 ))); do
    if [ -f overlay${ii} ]; then
       echo "overlay${ii} already exists"
       echo "Deal with it first and remove it from the working directory"
       echo "Exiting";exit 1
    else
       echo "Replicating overlay0 into overlay${ii}"
       srun -n 1 -N 1 --mem-per-cpu=0 --exclusive cp overlay0 overlay${ii} &
    fi
done
wait

#7. Creating inside processor* directories inside the overlayFS 
createInsideProcessorDirs $insideDir $foam_numberOfSubdomains;success=$? #Calling the function for creatingthe inside directories 
if [ $success -eq 222 ]; then 
   echo "$insideDir/processor0 already exists"
   echo "Exiting";exit 1
elif [ $success -ne 0 ]; then 
   echo "Failed creating the inside directories, exiting"
   echo "Exiting";exit 1
fi

#8. Creating soft links towards directories inside the overlayFS files
#These links and directories will be recognized by each mpi instance of the container
#(Initially these links will appear broken as they are pointing towards the interior of the overlay* files.
# They will only be recognized within the containers)
pointToOverlay $insideDir $foam_numberOfSubdomains;success=$? #Calling function to point towards the interior
if [ $success -ne 0 ]; then 
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#9. Transfer the content of the bak.processor* directories into the overlayFS using the softlinks processor*
echo "Copying OpenFOAM files inside bak.processor* into the overlays"
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
    echo "Writing into overlay${ii}"
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage bash -c "cp -r bak.processor${ii}/* processor${ii}/" &
done
wait

#10. Mark the initial conditions time directory as already fully reconstructed
echo "Marking the time directory \"0\" as fully reconstructed"
touch 0/.reconstructDone

#X. Final step
echo "Script done"
