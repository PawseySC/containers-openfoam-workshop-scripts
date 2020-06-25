#!/bin/bash -l
#SBATCH --ntasks=4 #Several tasks will be used for copying files. (Independent from the numberOfSubdomains)
#SBATCH --mem=4G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#@@#SBATCH --partition=copyq #Ideally use copyq for this kind of process
#SBATCH --partition=workq
#SBATCH --time=0:10:00
#SBATCH --export=none

#1. Loading the container settings, case settings and auxiliary functions (order is important)
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh

#2. Check existence of the case and moving into it
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
#Checking if an overlay0 already exists
if [ -f overlay0 ]; then
   echo "A file named overlay0 already exists."
   echo "Aborting the creation of overlay0 file in order to avoid loss of information"
   echo "Check your overlay files and content, and remove them from the working directory first, if new overlay0 is needed"
   echo "Exiting";exit 1
fi

#Creating the overlay0
#(Needs to use ubuntu:18.04 or higher to use the -d <root-dir> option to make them writable by simple users)
echo "Creating the overlay0 file"
echo "The size in Gb is overlaySizeGb=$overlaySizeGb"
if [ $overlaySizeGb -gt 0 ]; then
   countSize=$(( overlaySizeGb * 1024 * 1024 ))
   srun -n 1 -N 1 singularity exec docker://ubuntu:18.04 bash -c " \
        mkdir -p overlay_tmp/upper && \
        dd if=/dev/zero of=overlay0 count=$countSize bs=1024 && \
        mkfs.ext3 -d overlay_tmp overlay0 && rm -rf overlay_tmp \
        "
else
   echo "Variable overlaySizeGb was not set correctly"
   echo "In theory, this should have been set together with the singularity settings"
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
#Checking if the directories already exist
echo "Checking if $insideDir/processor0 directory is already there"
srun -n 1 -N 1 singularity exec --overlay overlay0 $theImage ls -dlh $insideDir/processor0
success=$?
if [ "$success" -eq 0 ]; then
   echo "Directory $insideDir/processor0 already exists. No further internal creation or deletion will be done"
   echo "Exiting";exit 1
fi
echo "Directory $insideDir/processor0 does not exist. Then will proceed with creation"

#Creating the directories inside
echo "Creating the directories inside the overlays"
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
   echo "Creating processor${ii} inside overlay${ii}"
   srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage mkdir -p $insideDir/processor${ii} &
done
wait

#Checking if the directories were created
echo "Checking if $insideDir/processor0 directory is already there"
srun -n 1 -N 1 singularity exec --overlay overlay0 $theImage ls -dlh $insideDir/processor0
success=$?
if [ "$success" -ne 0 ]; then
   echo "Directory $insideDir/processor0 does not exists."
   echo "Exiting";exit 1
fi

#8. Transfer the content of the bak.processor* directories into the overlayFS
echo "Copying OpenFOAM files inside bak.processor* into the overlays"
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
    echo "Writing into overlay${ii}"
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage cp -r bak.processor${ii}/* $insideDir/processor${ii}/ &
done
wait

#9. List the content of directories inside the overlay* files
echo "Listing the content in overlay0 $insideDir/processor0"
srun -n 1 -N 1 singularity exec --overlay overlay0 $theImage ls -lat $insideDir/processor0/

#X. Final step
echo "Script done"
