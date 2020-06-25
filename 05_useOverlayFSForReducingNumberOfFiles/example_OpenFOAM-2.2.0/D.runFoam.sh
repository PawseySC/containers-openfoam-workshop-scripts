#!/bin/bash -l
#SBATCH --ntasks=5
#SBATCH --mem=16G
#SBATCH --ntasks-per-node=28
#SBATCH --cluster=zeus
#@@#SBATCH --ntasks-per-node=24
#@@#SBATCH --cluster=magnus
#SBATCH --partition=workq
#SBATCH --time=0:10:00
#SBATCH --export=none

#1. Loading the container settings, case settings and auxiliary functions (order is important)
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh

#2. Going into the case and creating the logs dir
if [ -d $caseDir ]; then
   cd $caseDir
   echo "pwd=$(pwd)"
else
   echo "For some reason, the case=$caseDir, does not exist"
   echo "Exiting"; exit 1
fi
logsDir=./logs/run
if ! [ -d $logsDir ]; then
   mkdir -p $logsDir
fi

#3. Reading OpenFOAM decomposeParDict settings
foam_numberOfSubdomains=$(grep "^numberOfSubdomains" ./system/decomposeParDict | tr -dc '0-9')

#4. Checking if the number of tasks coincide with the number of subdomains
if [[ $foam_numberOfSubdomains -ne $SLURM_NTASKS ]]; then
   echo "foam_numberOfSubdomains read from ./system/decomposeParDict is $foam_numberOfSubdomains"
   echo "and"
   echo "SLURM_NTASKS in this job is $SLURM_NTASKS"
   echo "These should be the same"
   echo "Therefore, exiting this job"
   echo "Exiting"; exit 1
fi

#5. Defining OpenFOAM controlDict settings for this run
foam_startFrom=startTime
#foam_startFrom=latestTime
foam_startTime=0
#foam_startTime=10
foam_endTime=10
#foam_endTime=20
#foam_endTime=100
foam_writeInterval=1
foam_purgeWrite=0 #Just for testing in this exercise. In reality this should have a reasonable value if possible
#foam_purgeWrite=10 #Just 10 times will be preserved

#6. Changing OpenFOAM controlDict settings
sed -i 's,^startFrom.*,startFrom    '"$foam_startFrom"';,' system/controlDict
sed -i 's,^startTime.*,startTime    '"$foam_startTime"';,' system/controlDict
sed -i 's,^endTime.*,endTime    '"$foam_endTime"';,' system/controlDict
sed -i 's,^writeInterval.*,writeInterval    '"$foam_writeInterval"';,' system/controlDict
sed -i 's,^purgeWrite.*,purgeWrite    '"$foam_purgeWrite"';,' system/controlDict

#7. Creating soft links towards directories inside the overlayFS files
#These links and directories will be recognized by each mpi instance of the container
#(Initially these links will appear broken as they are pointing towards the interior of the overlay* files.
# They will only be recognized within the containers)
#Removing any softling
echo "First removing existing soft links"
linkList=$(find . -type l -name "proc*")
for ll in $linkList; do
   rm $ll
done

#Creating the soft links (will initially appear as broken)
echo "Creating the soft links to point towards the interior of the overlay files"
for ii in $(seq 0 $(( foam_numberOfSubdomains -1 ))); do
   echo "Linking to $insideDir/processor${ii} in overlay${ii}"
   srun -n 1 -N 1 --mem-per-cpu=0 --exclusive ln -s $insideDir/processor${ii} processor${ii} &
done
wait

#Testing:
srun -n 1 -N 1 singularity exec --overlay overlay0 $theImage ls -dlh processor0
success=$?
if [ $success -ne 0 ]; then 
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#8. (OpenFOAM-2.2.0 is looking for dictionaries inside the processor* directories, so this will be copied into):
echo "Copying dictionaries and properties into the overlays"
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
    echo "Writing into overlay${ii}"
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage cp -rf system $insideDir/processor${ii}/ &
done
wait
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage cp -rf constant/*Properties $insideDir/processor${ii}/constant/ &
done
wait
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
    srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage cp -rf constant/*Dict $insideDir/processor${ii}/constant/ &
done
wait

#9. Execute the case using the softlinks to write inside the overlays
echo "About to execute the case"
srun -n $SLURM_NTASKS -N $SLURM_JOB_NUM_NODES bash -c 'singularity exec --overlay overlay${SLURM_PROCID} '"$theImage"' pimpleFoam -parallel 2>&1' | tee $logsDir/log.pimpleFoam.$SLURM_JOBID
echo "Execution finished"

#10. List the existing times inside the overlays 
echo "Listing the available times inside overlay0"
srun -n 1 -N 1 singularity exec --overlay overlay0 $theImage ls -lat processor0/

#X. Final step
echo "Script done"
