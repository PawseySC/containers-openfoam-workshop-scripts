#!/bin/bash -l
#SBATCH --ntasks=4 #Several tasks will be used for copying files. (Independent from the numberOfSubdomains)
#SBATCH --mem=4G
#SBATCH --ntasks-per-node=28
#SBATCH --clusters=zeus
#SBATCH --time=0:10:00
#SBATCH --partition=workq
#SBATCH --export=none

#1. Loading the container settings, case settings and auxiliary functions (order is important)
source $SLURM_SUBMIT_DIR/imageSettingsSingularity.sh
source $SLURM_SUBMIT_DIR/caseSettingsFoam.sh

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

#4. Transfer the content of the overlayFS into the bak.processor* directories
reconstructionTime=10
echo "Copying the times to reconstruct from the overlays into bak.processor*"
for ii in $(seq 0 $(( foam_numberOfSubdomains - 1 ))); do
   echo "Writing into bak.processor${ii}"
   srun -n 1 -N 1 --mem-per-cpu=0 --exclusive singularity exec --overlay overlay${ii} $theImage cp -r $insideDir/processor${ii}/$reconstructionTime bak.processor${ii} &
done
wait

#5. Point the soft links to the bak.processor* directories
#Removing any softling
echo "First removing existing soft links"
linkList=$(find . -type l -name "proc*")
for ll in $linkList; do
   rm $ll
done

#Creating the soft links towards the bak.processor* directories
echo "Creating the soft links to point towards the bak.processor* directories"
for ii in $(seq 0 $(( foam_numberOfSubdomains -1 ))); do
   echo "Linking to bak.processor${ii}"
   srun -n 1 -N 1 --mem-per-cpu=0 --exclusive ln -s bak.processor${ii} processor${ii} &
done
wait

#Testing:
ls -dlh processor0
success=$?
if [ $success -ne 0 ]; then 
   echo "Failed creating the soft links"
   echo "Exiting";exit 1
fi

#6. Reconstruct the indicated time
echo "Start reconstruction"
srun -n 1 -N 1 singularity exec $theImage reconstructPar -time ${reconstructionTime} 2>&1 | tee $logsDir/log.reconstructPar.$SLURM_JOBID
if grep -i 'error\|exiting' $logsDir/log.reconstructPar.$SLURM_JOBID; then
   echo "The reconstruction of time ${reconstructionTime} failed"
   echo "Exiting";exit 1
fi

#X. Final step
echo "Script done"
