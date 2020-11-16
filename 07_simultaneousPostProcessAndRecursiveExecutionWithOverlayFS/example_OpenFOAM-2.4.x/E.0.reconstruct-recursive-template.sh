#!/bin/bash -l
#-----------------------
##Defining the needed resources with SLURM parameters (modify as needed)
#SBATCH --job-name=recursiveReconstruct
#SBATCH --output="%x-%j.out"
#SBATCH --ntasks=5
#SBATCH --ntasks-per-node=28
#SBATCH --cluster=zeus
#SBATCH --partition=workq
##SBATCH --time=0:10:00
#SBATCH --time=0:01:30
#SBATCH --export=none
 
#-----------------------
##Setting modules
#Add the needed modules (uncomment and adapt the follwing lines)
#module swap the-module-to-swap the-module-i-need
#module load the-modules-i-need
 
#-----------------------
##Setting the variables for controlling recursion
#job iteration counter. It's default value is 1 (as for the first submission). For a subsequent submission, it will receive it value through the "sbatch --export" command from the "parent job".
: ${job_iteration:="1"}
this_job_iteration=${job_iteration}
 
#Maximum number of job iterations. It is always good to have a reasonable number here
job_iteration_max=5
 
echo "This jobscript is calling itself in recursively. This is iteration=${this_job_iteration}."
echo "The maximum number of iterations is set to job_iteration_max=${job_iteration_max}."
echo "The slurm job id is: ${SLURM_JOB_ID}"
 
#-----------------------
##Defining the name of the dependent script.
#This "dependentScript" is the name of the next script to be executed in workflow logic. The most common and more utilised is to re-submit the same script:
thisScript=`squeue -h -j $SLURM_JOBID -o %o`
export dependentScript=${thisScript}
 
#-----------------------
##Safety-net checks before proceding to the execution of this script
 
#Check 1: If the file with the exact name 'stopSlurmCycle' exists in the submission directory, then stop execution.
#         Users can create a file with this name if they need to interrupt the submission cycle by using the following command:
#             touch stopSlurmCycle
#         (Remember to remove the file before submitting this script again.)
if [[ -f stopSlurmCycle ]]; then
   echo "The file \"stopSlurmCycle\" exists, so the script \"${thisScript}\" will exit."
   echo "Remember to remove the file before submitting this script again, or the execution will be stopped."
   exit 1
fi

#Check 2: If the number of output files has reached a limit, then stop execution.
#         The existence of a large number of output files could be a sign of an infinite recursive loop.
#         In this case we check for the number of "slurm-XXXX.out" files.
#         (Remember to check your output files regularly and remove the not needed old ones or the execution may be stoppped.)
maxSlurmies=25
#slurmyBaseName=slurm #Use the base name of the output file
slurmyBaseName=$SLURM_JOB_NAME #Use the base name of the output file
slurmies=$(find . -maxdepth 1 -name "${slurmyBaseName}*" | wc -l)
if [ $slurmies -gt $maxSlurmies ]; then
   echo "There are slurmies=${slurmies} $slurmyBaseName-XXXX.out files in the directory."
   echo "The maximum allowed number of output files is maxSlurmies=${maxSlurmies}"
   echo "This could be a sign of an infinite loop of slurm resubmissions."
   echo "So the script ${thisScript} will exit."
   exit 2
fi

#Check 3: Add some other adequate checks to guarantee the correct execution of your workflow
#Check 4: etc.
 
#-----------------------
##Setup/Update of parameters/input for the current script
 
#The following variables will receive a value with the "sbatch --export" submission from the parent job.
#If this is the first time this script is called, then they will start with the default values given here:
#: ${var_start_time:="0"}
#: ${var_end_time:="10"}
#: ${var_increment:="10"}
: ${surnameTag:=""}  #surname tag to identify the overlay* file to process
echo "AEG:E.0.A: reconstructTimes=$reconstructTimes"
: ${reconstructTimes:="all"} #All the times inside the partial overlay will be reconstructed
echo "AEG:E.0.B: reconstructTimes=$reconstructTimes"
 
#Replacing the current values in the parameter/input file used by the executable:
 
#Creating the backup of the parameter file utilised in this job
 
#-----------------------
##Verify that everything that is needed is ready
#This section is IMPORTANT. For example, it can be used to verify that the results from the parent submission are there. If not, stop execution.
echo "Checking if previous job finished reconstruction already"
ls ${slurmyBaseName}* > listSlurms.$SLURM_JOBID
sort -n listSlurms.$SLURM_JOBID -o listSlurmsSorted.$SLURM_JOBID
rm listSlurms.$SLURM_JOBID
nSlurms=0
while read fileName; do
   nameArr[$nSlurms]=$fileName
   ((nSlurms++))
done < listSlurmsSorted.$SLURM_JOBID
rm listSlurmsSorted.$SLURM_JOBID
if [ $nSlurms -gt 1 ]; then
   prevSlurmFile=${nameArr[-2]}
   #Check A. Verify if reconstruction finished in the previous job
   prevReconstruct=$(sed -n '/Times to be reconstructed are:/{n;p}' $prevSlurmFile) 
   if [ "$prevReconstruct" = "-1" ]; then
      echo "The previous output file ($prevSlurmFile)"
      echo "Has the following info:"
      sed -n '/Times to be reconstructed are:/{N;p}' $prevSlurmFile
      echo "So the recursive reconstruction has finished."
      echo "Finishing"; exit 0
   fi
   #Check B. Verify if there are no messsages for stopping recursive jobs in the previous log
   nStops=$(grep -i "Stop recursive jobs if they exist" $prevSlurmFile | wc -l)
   if [ $nStops -gt 0 ]; then
      echo "The previous output file ($prevSlurmFile)"
      echo "Has nStops=$nStops messages with the phrase 'Stop recursive jobs if they exist'"
      echo "So the recursive reconstruction failed."
      echo "Exiting"; exit 4
   fi
fi
 
#-----------------------
##Submitting the dependent job
#IMPORTANT: Never use cycles that could fall into infinite loops. Numbered cycles are the best option.
 
#The following variable needs to be "true" for the cycle to proceed (it can be set to false to avoid recursion when testing):
useDependentCycle=true
 
#Check if the current iteration is within the limits of the maximum number of iterations, then submit the dependent job:
if [ "$useDependentCycle" = "true" ] && [ ${job_iteration} -lt ${job_iteration_max} ]; then
   #Update the counter of cycle iterations
   (( job_iteration++ ))
   #Update the values needed for the next submission
   #var_start_time=$var_end_time
   #(( var_end_time+=$var_increment ))
   #Dependent Job submission:
   #                         (Note that next_jobid has the ID given by the sbatch)
   #                         For the correct "--dependency" flag:
   #                         Use "afterok" when each job is expected to properly finish.
   #                         Use "afterany" when each job is expected to reach walltime.
   #                         Check documentation for other flags available.
   #IMPORTANT: The --export="list_of_exported_vars" guarantees that values are inherited to the dependent job
   #           Note that continuation-line sign '\' is not separated by a space in order to concatenate the list
   next_jobid=$(sbatch --job-name=$SLURM_JOB_NAME --partition=$SLURM_JOB_PARTITION \
       --export="job_iteration=${job_iteration},surnameTag=${surnameTag},reconstructTimes=${reconstructTimes}" \
       --dependency=singleton ${dependentScript} | awk '{print $4}')
   echo "Dependent job with slurm ID=${next_jobid} was submitted"
   echo "If you want to stop the submission chain it is recommended to use scancel on the dependent job first"
   echo "Or create a file named: \"stopSlurmCycle\""
   echo "And then you can scancel this job if needed too"
else
   echo "This is the last iteration of the cycle, no more dependent jobs will be submitted"
fi
    
#-----------------------
##Run the main executable.
#(Modify as needed)
#Syntax should allow restart from a checkpoint
#srun -N $SLURM_JOB_NUM_NODES -n $SLURM_NTASKS ./code.x
. $SLURM_SUBMIT_DIR/E.1.reconstructFromOverlay.sh
